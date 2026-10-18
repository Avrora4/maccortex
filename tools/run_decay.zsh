#!/bin/zsh
# tools/run_decay.zsh — D-① の予備計測を 1 回実行する
#
# 使い方:  ./tools/run_decay.zsh <m3air16|m4air32> <fma|sgemm>
#
#   1. 確認スクリプト（bench_preflight.zsh）を実行し、NG があれば何もせずに終わる
#   2. 画面を消す
#   3. powermetrics（1 秒ごと）を裏で動かしながら、bench_thermal_decay を 30 分実行する
#   4. 1 分ごとの性能・周波数・電力と、thermal pressure の内訳を表示する
#
# 前提: macos-release でビルド済み、作業ツリーがクリーン、機体を 20 分以上冷やしてある
# 出力: ~/maccortex-logs/ に decay-*.csv（性能）と pm-*.txt（powermetrics）
#
# 変数名に CC / CXX / PATH など意味のある名前を使わない（引き継ぎ資料 §8）

emulate -R zsh
setopt no_unset pipe_fail

if (( $# != 2 )); then
  print -u2 "usage: $0 <m3air16|m4air32> <fma|sgemm>"
  exit 2
fi
MACHINE=$1
WORKLOAD=$2
case $MACHINE in
  m3air16|m4air32) ;;
  *) print -u2 "unknown machine: $MACHINE"; exit 2 ;;
esac
case $WORKLOAD in
  fma|sgemm) ;;
  *) print -u2 "unknown workload: $WORKLOAD"; exit 2 ;;
esac

REPO=${0:A:h:h}
BENCH=$REPO/build/macos-release/bench/bench_thermal_decay
LOG_DIR=${MCX_LOG_DIR:-$HOME/maccortex-logs}
DURATION_S=1800
PM_SAMPLES=$(( DURATION_S + 30 ))   # 計測より 30 秒長く取り、終わりの区間も覆う

if [[ ! -x $BENCH ]]; then
  print -u2 "not found: $BENCH"
  print -u2 "先に cmake --build --preset macos-release を実行する"
  exit 1
fi

mkdir -p $LOG_DIR
TS=$(date +%Y%m%d-%H%M%S)
CSV=$LOG_DIR/decay-$MACHINE-$WORKLOAD-$TS.csv
PM=$LOG_DIR/pm-$MACHINE-$WORKLOAD-$TS.txt

# powermetrics 用。画面を消す前にパスワードを入れておく
sudo -v || exit 1

if ! MCX_LOG_DIR=$LOG_DIR zsh $REPO/tools/bench_preflight.zsh $MACHINE; then
  print -u2 ""
  print -u2 "preflight で NG。計測は始めていない"
  exit 1
fi

print ""
print "start: $(date '+%H:%M:%S')   終了予定: $(date -v+${DURATION_S}S '+%H:%M:%S')"
print "csv:   $CSV"
print "pm:    $PM"

pmset displaysleepnow
sudo powermetrics -i 1000 -n $PM_SAMPLES --samplers cpu_power,thermal -o $PM >/dev/null 2>&1 &
pm_pid=$!
caffeinate -i $BENCH --workload $WORKLOAD --duration $DURATION_S > $CSV
rc=$?
print ""
print "bench 終了 (exit $rc)。powermetrics の終了を待つ（最大 30 秒）"
wait $pm_pid

# ---------------------------------------------------------------- 要約
print ""
print "== 1 分ごとの平均性能 (GFLOP/s) =="
awk -F, '/^[0-9]/ { m = int(($1 - 0.001) / 60); s[m] += $2; c[m]++ }
         END { for (i = 0; i < 60; i++) if (c[i]) printf "  %2d-%2d min  %9.2f\n", i, i + 1, s[i] / c[i] }' $CSV

# powermetrics の書式は機種や OS で変わりうる。何も出なければ pm-*.txt を直接見る
print ""
print "== 1 分ごとの P クラスタ周波数と CPU 電力（powermetrics）=="
awk '/^\*\*\* Sampled system activity/ { k++ }
     /P[0-9]*-Cluster HW active frequency/ { m = int((k - 1) / 60); f[m] += $(NF - 1); fc[m]++ }
     /^CPU Power:/ { m = int((k - 1) / 60); p[m] += $3; pc[m]++ }
     END { for (i = 0; i < 60; i++) if (fc[i] || pc[i])
             printf "  %2d-%2d min  %6.0f MHz  %6.0f mW\n", i, i + 1,
                    (fc[i] ? f[i] / fc[i] : 0), (pc[i] ? p[i] / pc[i] : 0) }' $PM

print ""
print "== thermal pressure の内訳（サンプル数）=="
grep -o 'Current pressure level: [A-Za-z]*' $PM | sort | uniq -c

exit $rc
