// bench/thermal_decay.cpp
//
// D-① 30 分の性能低下（decay）の予備計測ハーネス
//
// 冷間から一定の負荷をかけ続け、interval ごとのスループット（GFLOP/s）を CSV で stdout に出す。
// 測定の文脈（git hash、環境）はこのプログラムでは取らない。tools/bench_context.zsh で別に取る。
// 出力はスキーマ v1 の結果ではなく生データ。リポジトリの外（~/maccortex-logs/）に保存する。
//
// 使い方:
//   bench_thermal_decay --workload fma   [--threads N] [--duration 1800] [--interval 1.0]
//   bench_thermal_decay --workload sgemm [--threads N] [--duration 1800] [--interval 1.0] [--n 1024]
//
// 負荷:
//   fma   : NEON の FMA を 16 本の独立なアキュムレータで回し続ける。CPU コアの FP パイプを埋める。
//           既定のスレッド数は P コア数（hw.perflevel0.physicalcpu）
//   sgemm : Accelerate の cblas_sgemm（n×n）を回し続ける。M3 は AMX、M4 は SME 経由になる想定。
//           既定のスレッド数は 1（Accelerate が内部で並列化するかはブラックボックスなので、呼び出し側は増やさない）
//
// しきい値・既定値はすべて暫定。調整チャットで決まったら合わせる。

#include <Accelerate/Accelerate.h>
#include <arm_neon.h>
#include <pthread/qos.h>
#include <sys/sysctl.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cinttypes>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <functional>
#include <new>
#include <optional>
#include <string_view>
#include <thread>
#include <vector>

namespace {

using Clock = std::chrono::steady_clock;

// スレッドごとの完了数。別スレッドのカウンタが同じキャッシュラインに乗ると偽共有になるので離す
struct alignas(std::hardware_destructive_interference_size) Counter {
  std::atomic<std::uint64_t> units{0};
};

enum class Workload { fma, sgemm };

struct Options {
  Workload workload = Workload::fma;
  int threads = 0;  // 0 = 負荷ごとの既定値
  double duration_s = 1800.0;
  double interval_s = 1.0;
  int n = 1024;  // sgemm の行列サイズ
};

// ---------------------------------------------------------------- fma

constexpr int kFmaIters = 1 << 20;  // 1 単位あたりの反復回数
constexpr int kAcc = 16;            // 独立なアキュムレータ数（FMA のレイテンシ × パイプ数を埋める）
constexpr double kFmaFlopsPerUnit =
    static_cast<double>(kFmaIters) * kAcc * 4.0 /*lanes*/ * 2.0 /*mul+add*/;

// acc = c + acc * b を繰り返す。b < 1 なので値は c / (1 - b) に収束し、溢れも非正規化数も出ない
float fma_unit(float seed) {
  float32x4_t acc[kAcc];
  for (int i = 0; i < kAcc; ++i) {
    acc[i] = vdupq_n_f32(seed + static_cast<float>(i));
  }
  const float32x4_t b = vdupq_n_f32(0.9999f);
  const float32x4_t c = vdupq_n_f32(0.001f);
  for (int it = 0; it < kFmaIters; ++it) {
    for (int i = 0; i < kAcc; ++i) {
      acc[i] = vfmaq_f32(c, acc[i], b);
    }
  }
  float32x4_t s = acc[0];
  for (int i = 1; i < kAcc; ++i) {
    s = vaddq_f32(s, acc[i]);
  }
  return vaddvq_f32(s);
}

void fma_worker(Counter& counter, const std::atomic<bool>& stop, float& out) {
  pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);  // P コアに載りやすくする
  // 前回の結果を次の入力に使う。入力が毎回同じだと、コンパイラが計算をループの外に出せてしまう
  float x = 0.0f;
  while (!stop.load(std::memory_order_relaxed)) {
    x = fma_unit(x * 1e-6f);
    counter.units.fetch_add(1, std::memory_order_relaxed);
  }
  out = x;
}

// ---------------------------------------------------------------- sgemm

void sgemm_worker(int n, Counter& counter, const std::atomic<bool>& stop, float& out) {
  pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
  const std::size_t nn = static_cast<std::size_t>(n) * static_cast<std::size_t>(n);
  std::vector<float> a(nn), b(nn), c(nn);
  for (std::size_t i = 0; i < nn; ++i) {
    a[i] = static_cast<float>(i % 7) * 0.01f;
    b[i] = static_cast<float>(i % 5) * 0.01f;
  }
  while (!stop.load(std::memory_order_relaxed)) {
    cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, n, n, n, 1.0f, a.data(), n, b.data(), n,
                0.0f, c.data(), n);
    counter.units.fetch_add(1, std::memory_order_relaxed);
  }
  out = c[0] + c[nn - 1];
}

// ---------------------------------------------------------------- 補助

int performance_core_count() {
  int value = 0;
  std::size_t len = sizeof(value);
  if (sysctlbyname("hw.perflevel0.physicalcpu", &value, &len, nullptr, 0) == 0 && value > 0) {
    return value;
  }
  return 0;
}

void usage() {
  std::fprintf(stderr,
               "usage: bench_thermal_decay --workload fma|sgemm [--threads N] [--duration SEC]\n"
               "                           [--interval SEC] [--n SIZE]\n");
}

std::optional<Options> parse(int argc, char** argv) {
  Options o;
  for (int i = 1; i < argc; ++i) {
    const std::string_view arg = argv[i];
    if (i + 1 >= argc) {
      return std::nullopt;  // すべてのオプションが値を取る
    }
    const char* value = argv[++i];
    if (arg == "--workload") {
      const std::string_view v = value;
      if (v == "fma") {
        o.workload = Workload::fma;
      } else if (v == "sgemm") {
        o.workload = Workload::sgemm;
      } else {
        return std::nullopt;
      }
    } else if (arg == "--threads") {
      o.threads = std::atoi(value);
    } else if (arg == "--duration") {
      o.duration_s = std::strtod(value, nullptr);
    } else if (arg == "--interval") {
      o.interval_s = std::strtod(value, nullptr);
    } else if (arg == "--n") {
      o.n = std::atoi(value);
    } else {
      return std::nullopt;
    }
  }
  if (o.threads < 0 || o.duration_s <= 0.0 || o.interval_s <= 0.0 || o.n <= 0) {
    return std::nullopt;
  }
  if (o.threads == 0) {
    if (o.workload == Workload::fma) {
      o.threads = performance_core_count();
      if (o.threads == 0) {
        std::fprintf(stderr, "P コア数を取得できない。--threads で指定する\n");
        return std::nullopt;
      }
    } else {
      o.threads = 1;
    }
  }
  return o;
}

double mean_between(const std::vector<double>& t, const std::vector<double>& v, double lo,
                    double hi) {
  double sum = 0.0;
  std::size_t count = 0;
  for (std::size_t i = 0; i < t.size(); ++i) {
    if (t[i] > lo && t[i] <= hi) {
      sum += v[i];
      ++count;
    }
  }
  return count == 0 ? 0.0 : sum / static_cast<double>(count);
}

}  // namespace

int main(int argc, char** argv) {
  const std::optional<Options> parsed = parse(argc, argv);
  if (!parsed) {
    usage();
    return 2;
  }
  const Options& opt = *parsed;
  const auto num_threads = static_cast<std::size_t>(opt.threads);

  const double flops_per_unit =
      opt.workload == Workload::fma
          ? kFmaFlopsPerUnit
          : 2.0 * static_cast<double>(opt.n) * static_cast<double>(opt.n) * static_cast<double>(opt.n);

  // 時刻合わせ用（powermetrics のログと突き合わせる）
  char wall[64];
  const std::time_t now_wall = std::time(nullptr);
  std::tm tm_local{};
  localtime_r(&now_wall, &tm_local);
  std::strftime(wall, sizeof(wall), "%Y-%m-%dT%H:%M:%S%z", &tm_local);

  std::printf("# mcx thermal_decay v0\n");
  std::printf("# start_wall: %s\n", wall);
  std::printf("# workload: %s\n", opt.workload == Workload::fma ? "fma" : "sgemm");
  std::printf("# threads: %d\n", opt.threads);
  std::printf("# duration_s: %.1f\n", opt.duration_s);
  std::printf("# interval_s: %.3f\n", opt.interval_s);
  if (opt.workload == Workload::sgemm) {
    std::printf("# n: %d\n", opt.n);
  }
  std::printf("# flops_per_unit: %.0f\n", flops_per_unit);
  std::printf("t_s,gflops,units\n");
  std::fflush(stdout);

  std::vector<Counter> counters(num_threads);
  std::vector<float> sinks(num_threads, 0.0f);
  std::atomic<bool> stop{false};
  std::vector<std::thread> workers;
  workers.reserve(num_threads);

  const auto t0 = Clock::now();
  for (std::size_t i = 0; i < num_threads; ++i) {
    if (opt.workload == Workload::fma) {
      workers.emplace_back(fma_worker, std::ref(counters[i]), std::cref(stop), std::ref(sinks[i]));
    } else {
      workers.emplace_back(sgemm_worker, opt.n, std::ref(counters[i]), std::cref(stop),
                           std::ref(sinks[i]));
    }
  }

  const auto interval = std::chrono::duration_cast<Clock::duration>(
      std::chrono::duration<double>(opt.interval_s));
  const auto end = t0 + std::chrono::duration_cast<Clock::duration>(
                            std::chrono::duration<double>(opt.duration_s));

  std::vector<std::uint64_t> prev(num_threads, 0);
  std::vector<double> ts;
  std::vector<double> gs;
  auto next = t0;
  auto prev_time = t0;

  // 単位の途中で区切るので、1 区間の値には最大 1 単位分の量子化誤差が乗る
  while (next + interval <= end) {
    next += interval;
    std::this_thread::sleep_until(next);
    const auto now = Clock::now();
    std::uint64_t delta = 0;
    for (std::size_t i = 0; i < num_threads; ++i) {
      const std::uint64_t cur = counters[i].units.load(std::memory_order_relaxed);
      delta += cur - prev[i];
      prev[i] = cur;
    }
    const double dt = std::chrono::duration<double>(now - prev_time).count();
    const double t = std::chrono::duration<double>(now - t0).count();
    const double gflops = static_cast<double>(delta) * flops_per_unit / dt / 1e9;
    std::printf("%.3f,%.3f,%" PRIu64 "\n", t, gflops, delta);
    std::fflush(stdout);
    ts.push_back(t);
    gs.push_back(gflops);
    prev_time = now;
  }

  stop.store(true, std::memory_order_relaxed);
  for (auto& w : workers) {
    w.join();
  }

  float sink_sum = 0.0f;
  for (const float s : sinks) {
    sink_sum += s;
  }

  // 要約（暫定の定義）: burst = 最初の 10 秒、steady = 最後の min(300 秒, 全体の半分)
  const double steady_window = std::min(300.0, opt.duration_s / 2.0);
  const double burst = mean_between(ts, gs, 0.0, 10.0);
  const double steady = mean_between(ts, gs, opt.duration_s - steady_window, opt.duration_s);
  std::fprintf(stderr, "burst  (0-10 s)      : %10.2f GFLOP/s\n", burst);
  std::fprintf(stderr, "steady (last %4.0f s) : %10.2f GFLOP/s\n", steady_window, steady);
  if (burst > 0.0) {
    std::fprintf(stderr, "steady / burst        : %10.3f\n", steady / burst);
  }
  std::fprintf(stderr, "(sink %g)\n", static_cast<double>(sink_sum));
  return 0;
}
