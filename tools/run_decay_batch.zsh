#!/bin/zsh
# tools/run_decay_batch.zsh — D-① の予備計測（fma → sgemm）を無人で続けて流す
#
# 使い方:  ./tools/run_decay_batch.zsh <m3air16|m4air32>
#
# 流れ: 最初の待機（既定 30 分）→ fma → 待機（既定 30 分）→ sgemm
#   - 各計測の前に、充電が終わるまで待つ（5 分ごと、最大 60 分）
#   - 各計測の前に確認スクリプトを実行し、NG なら 10 分待って最大 3 回まで再確認する。
#     それでも NG ならその計測は飛ばし、次へ進む
#   - 全体のログを ~/maccortex-logs/batch-*.log に残す
#
# 環境変数で変えられるもの:
#   MCX_INITIAL_WAIT_MIN  最初の待機（分、既定 30）
#   MCX_INTERVAL_MIN      計測の間の待機（分、既定 30）
#
# sudo について:
#   powermetrics に sudo が要るので、最初に 1 回だけパスワードを入れる。
#   その後は、このスクリプトが動いている間だけ認証の期限を延長し続け、
#   終了時（Ctrl-C で止めた場合も含む）に sudo -k で認証を破棄する。
#   認証が切れていたら、パスワード入力で止まらないよう、その計測は飛ばす。

emulate -R zsh
setopt no_unset pipe_fail

if (( $# != 1 )); then
  print -u2 "usage: $0 <m3air16|m4air32>"
  exit 2
fi
MACHINE=$1
case $MACHINE in
  m3air16|m4air32) ;;
  *) print -u2 "unknown machine: $MACHINE"; exit 2 ;;
esac

REPO=${0:A:h:h}
LOG_DIR=${MCX_LOG_DIR:-$HOME/maccortex-logs}
INITIAL_WAIT_MIN=${MCX_INITIAL_WAIT_MIN:-30}
INTERVAL_MIN=${MCX_INTERVAL_MIN:-30}
RETRY_WAIT_MIN=10
MAX_TRIES=3
WORKLOADS=(fma sgemm)

if [[ ! -x $REPO/tools/run_decay.zsh ]]; then
  print -u2 "not found: $REPO/tools/run_decay.zsh"
  exit 1
fi

mkdir -p $LOG_DIR
BATCH_LOG=$LOG_DIR/batch-$MACHINE-$(date +%Y%m%d-%H%M%S).log
exec > >(tee -a $BATCH_LOG) 2>&1

stamp() { print -r -- "[$(date '+%m-%d %H:%M:%S')] $*" }
wait_min() {
  stamp "$1 分待つ（$2）。再開予定 $(date -v+${1}M '+%H:%M')"
  sleep $(( $1 * 60 ))
}

# ---------------------------------------------------------------- sudo とスリープ防止
sudo -v || exit 1
( while kill -0 $$ 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 50; done ) &
keepalive_pid=$!
caffeinate -i -w $$ &          # このスクリプトが終わるまでスリープさせない

trap 'exit 130' INT TERM
trap 'kill $keepalive_pid 2>/dev/null; sudo -k; stamp "batch 終了。ログ: $BATCH_LOG"' EXIT

# ---------------------------------------------------------------- 本体
typeset -A result
stamp "batch 開始: $MACHINE  (${WORKLOADS[*]})"
stamp "HEAD: $(git -C $REPO describe --always --dirty)"
stamp "所要時間の目安: 約 $(( INITIAL_WAIT_MIN + INTERVAL_MIN + 31 * ${#WORKLOADS} )) 分"

pmset displaysleepnow
wait_min $INITIAL_WAIT_MIN "最初の冷却"

for i in {1..${#WORKLOADS}}; do
  w=${WORKLOADS[$i]}
  (( i > 1 )) && wait_min $INTERVAL_MIN "次の計測までの冷却"

  # 充電中はバッテリーが熱源になるので、終わるまで待つ
  for (( c = 0; c < 12; c++ )); do
    pmset -g batt | grep -q '; charging;' || break
    stamp "$w: 充電中。5 分待つ"
    sleep 300
  done

  # 確認スクリプト。NG なら少し待って再確認
  ok=0
  for (( t = 1; t <= MAX_TRIES; t++ )); do
    if zsh $REPO/tools/bench_preflight.zsh $MACHINE > /dev/null; then
      ok=1
      break
    fi
    stamp "$w: 確認で NG（${t}/${MAX_TRIES}）。詳細は $LOG_DIR/preflight-$MACHINE-*.log の最新"
    (( t < MAX_TRIES )) && wait_min $RETRY_WAIT_MIN "再確認まで"
  done
  if (( ! ok )); then
    stamp "$w: 確認が通らないので飛ばす"
    result[$w]="skipped (preflight NG)"
    continue
  fi

  if ! sudo -n true 2>/dev/null; then
    stamp "$w: sudo の認証が切れているので飛ばす"
    result[$w]="skipped (sudo expired)"
    continue
  fi

  stamp "$w: 計測開始"
  if $REPO/tools/run_decay.zsh $MACHINE $w; then
    result[$w]="ok"
  else
    result[$w]="failed (exit $?)"
  fi
  stamp "$w: ${result[$w]}"
done

stamp "結果:"
for w in $WORKLOADS; do
  print -r -- "    $w: ${result[$w]:-not run}"
done
