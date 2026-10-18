#!/bin/zsh
# tools/bench_preflight.zsh — 計測開始前の状態を記録し、開始してよいかを判定する
#
# 使い方:  ./tools/bench_preflight.zsh <m3air16|m4air32>
# 終了コード: 0 = NG なし（WARN は内容を見て判断） / 1 = NG あり
#
# - 読み取りのみ。何も変更しない。sudo も使わない
# - 結果は ~/maccortex-logs/ に保存する（/tmp は macOS が掃除するので使わない。
#   リポジトリの中にも置かない：生ログを履歴に入れない規則と、作業ツリーを汚さないため）
# - しきい値（CPU idle 95% など）は暫定値。熱計測ハーネスの設計で見直す

emulate -R zsh
setopt no_unset pipe_fail

# このスクリプトは <repo>/tools/ に置く前提。リポジトリの場所はスクリプトの位置から求める
REPO="${MCX_REPO:-${0:A:h:h}}"
LOG_DIR="${MCX_LOG_DIR:-$HOME/maccortex-logs}"
MACHINE="${1:-unknown}"
TS="$(date +%Y%m%d-%H%M%S)"

typeset -i n_ng=0 n_warn=0

ok()      { print -r -- "[OK]   $*" }
warn()    { print -r -- "[WARN] $*"; (( n_warn++ )) }
ng()      { print -r -- "[NG]   $*"; (( n_ng++ )) }
info()    { print -r -- "[INFO] $*" }
section() { print -r -- ""; print -r -- "== $* ==" }

main() {
  local chip batt pct lpm tp topout idle busy tracked untracked
  local nd wifi_if tool tool_path proc app

  print -r -- "MacCortex preflight  $(date '+%Y-%m-%d %H:%M:%S %z')"

  # ---------------------------------------------------------------- 機体
  section "機体"
  chip="$(sysctl -n machdep.cpu.brand_string)"
  info "machine: $MACHINE"
  info "host:    $(scutil --get LocalHostName 2>/dev/null)"
  info "chip:    $chip"
  info "macOS:   $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  info "uptime: $(uptime)"
  case "$MACHINE" in
    m4air32) [[ $chip == *"M4"* ]] && ok "機体名とチップが一致" || ng "m4air32 なのにチップが $chip" ;;
    m3air16) [[ $chip == *"M3"* ]] && ok "機体名とチップが一致" || ng "m3air16 なのにチップが $chip" ;;
    *)       warn "機体名が指定されていない（引数に m3air16 か m4air32）" ;;
  esac

  # ---------------------------------------------------------------- 電源
  section "電源"
  batt="$(pmset -g batt)"
  pct="$(print -r -- "$batt" | grep -Eo '[0-9]+%' | head -n 1)"
  if [[ $batt == *"'AC Power'"* ]]; then
    ok "AC 電源"
  else
    warn "バッテリー駆動（AC に繋いで測るなら接続する）"
  fi
  if [[ $batt == *"; charging;"* || $batt == *"finishing charge"* ]]; then
    warn "充電中 (${pct:-?})。充電が終わってから始める"
  else
    ok "充電は動いていない (${pct:-?})"
  fi
  lpm="$(pmset -g | awk '/lowpowermode/ {print $2}')"
  [[ $lpm == 0 ]] && ok "低電力モード: オフ" || ng "低電力モード: ${lpm:-不明}（オフにする）"

  # ---------------------------------------------------------------- 熱
  section "熱"
  # 0=Nominal 1=Moderate 2=Heavy 3=Trapping 4=Sleeping
  tp="$(notifyutil -g com.apple.system.thermalpressurelevel 2>/dev/null | awk '{print $2}')"
  case "$tp" in
    0)     ok "thermal pressure: Nominal（必要条件。これだけでは冷え切った保証にならない）" ;;
    1)     ng "thermal pressure: Moderate（まだ温かい。冷ましてから）" ;;
    2|3|4) ng "thermal pressure: level $tp" ;;
    *)     warn "thermal pressure を取得できない。sudo powermetrics -n 1 -i 1000 --samplers thermal で確認" ;;
  esac

  # ---------------------------------------------------------------- CPU
  section "CPU 負荷（3 秒間隔で 2 回取り、2 回目を使う）"
  topout="$(top -l 2 -s 3 -o cpu -n 12 -stats pid,cpu,command 2>/dev/null)"
  idle="$(print -r -- "$topout" | awk '/^CPU usage/ {v=$7} END {sub(/%/, "", v); print v}')"
  if [[ -z $idle ]]; then
    warn "CPU idle を取得できない"
  elif (( idle >= 95 )); then
    ok "CPU idle: ${idle}%"
  elif (( idle >= 90 )); then
    warn "CPU idle: ${idle}%（少し落ち着くのを待つ）"
  else
    ng "CPU idle: ${idle}%"
  fi
  busy="$(print -r -- "$topout" | awk '/^ *PID/ {n++; next} n==2 && $2+0 >= 5 && $3 != "top" {print "    " $0}')"
  if [[ -n $busy ]]; then
    warn "CPU を 5% 以上使っているプロセス:"
    print -r -- "$busy"
  else
    ok "CPU を 5% 以上使っているプロセスなし"
  fi
  info "上位プロセス:"
  print -r -- "$topout" | awk '/^ *PID/ {n++} n==2 {print "    " $0}'

  # ---------------------------------------------------------------- 止めるべきもの
  section "止めるべきアプリ・プロセス"
  for app in "Visual Studio Code.app" "Xcode.app" "Simulator.app" "Google Chrome.app" \
             "Safari.app" "Claude.app" "Slack.app" "Docker.app"; do
    pgrep -f "/${app}/" >/dev/null && ng "起動中: ${app}"
  done
  for proc in clangd java maestro claude ollama cmake ninja clang xcodebuild; do
    pgrep -x "$proc" >/dev/null && ng "起動中: ${proc}"
  done
  if xcrun simctl list devices booted 2>/dev/null | grep -q "(Booted)"; then
    ng "起動中のシミュレータあり（xcrun simctl shutdown all）"
  else
    ok "起動中のシミュレータなし"
  fi
  if tmutil status 2>/dev/null | grep -q "Running = 1"; then
    ng "Time Machine がバックアップ中（tmutil stopbackup）"
  else
    ok "Time Machine: 動いていない"
  fi
  info "crontab（計測中に起動するものが無いか目で確認）:"
  crontab -l 2>/dev/null | sed 's/^/    /'
  info "ユーザーの launchd ジョブ（com.apple 以外。wine-map の無人実行などが無いか確認）:"
  launchctl list | awk 'NR > 1 && $3 !~ /^(com\.apple\.|application\.com\.apple\.)/ {print "    " $0}'

  # ---------------------------------------------------------------- シェルとツールチェイン
  section "シェルとツールチェイン（ADR-0002）"
  if [[ -n ${CONDA_PREFIX:-} || -n ${CONDA_DEFAULT_ENV:-} ]]; then
    ng "conda が有効 (${CONDA_DEFAULT_ENV:-${CONDA_PREFIX:-}})"
  else
    ok "conda: 無効"
  fi
  if [[ -n ${CC:-} || -n ${CXX:-} ]]; then
    ng "CC/CXX が export されている (CC=${CC:-} CXX=${CXX:-})"
  else
    ok "CC/CXX: export されていない"
  fi
  for tool in ld ar; do
    tool_path="$(command -v $tool)"
    [[ $tool_path == /usr/bin/$tool ]] && ok "$tool: $tool_path" || ng "$tool: $tool_path（/usr/bin/$tool であること）"
  done
  info "Xcode: $(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
  info "clang: $(clang --version 2>/dev/null | head -n 1)"

  # ---------------------------------------------------------------- リポジトリ
  section "リポジトリ"
  if [[ -d $REPO/.git ]]; then
    tracked="$(git -C "$REPO" status --porcelain --untracked-files=no)"
    untracked="$(git -C "$REPO" status --porcelain | grep '^??')"
    [[ -z $tracked ]] && ok "追跡ファイルに変更なし" || ng "追跡ファイルに変更あり（-dirty になる）"
    [[ -z $untracked ]] || warn "未追跡ファイルあり（中身を確認）"
    info "HEAD: $(git -C "$REPO" describe --always --dirty)  branch: $(git -C "$REPO" branch --show-current)"
  else
    ng "リポジトリが見つからない: $REPO"
  fi

  # ---------------------------------------------------------------- 周辺機器・ネットワーク
  section "周辺機器・ネットワーク"
  nd="$(system_profiler SPDisplaysDataType 2>/dev/null | grep -c 'Resolution:')"
  if (( nd <= 1 )); then
    ok "ディスプレイ: ${nd} 台"
  else
    warn "ディスプレイ: ${nd} 台（外部モニターを外す）"
  fi
  wifi_if="$(networksetup -listallhardwareports | awk '/Hardware Port: Wi-Fi/ {getline; print $2}')"
  info "$(networksetup -getairportpower "${wifi_if:-en0}" 2>/dev/null)（オン/オフは毎回揃える）"

  # ---------------------------------------------------------------- 手動確認
  section "手動で確認すること（スクリプトでは分からない）"
  print -r -- "  [ ] 硬い机の上、蓋を開けている、ケースなし、直射日光・暖房の近くでない"
  print -r -- "  [ ] 付属の充電器を直接接続。ハブ・ドック・USB 機器なし"
  print -r -- "  [ ] ビルド後 20 分以上、何もせずに置いた"
  print -r -- "  [ ] 記録: 空調（オン/オフ・設定温度）、温度計があれば室温"
  print -r -- "  [ ] 計測用のターミナル 1 つ以外のアプリは全て終了した"

  # ---------------------------------------------------------------- 結果
  section "結果"
  print -r -- "NG: ${n_ng}  WARN: ${n_warn}"
  if (( n_ng == 0 )); then
    print -r -- "→ 開始してよい（WARN は内容を見て判断）"
    return 0
  else
    print -r -- "→ NG を解消してから再実行"
    return 1
  fi
}

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/preflight-${MACHINE}-${TS}.log"
main | tee "$LOG"
rc=${pipestatus[1]}
print -r -- ""
print -r -- "log: $LOG"
exit $rc
