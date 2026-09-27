// bench_hello: the smallest benchmark that exercises the Phase 0 harness.
//
// It prints benchmark schema v1 records (docs/benchmarks/SCHEMA.md) to stdout,
// one JSON object per line, WITHOUT the context fields (machine, env.macos,
// env.xcode, env.metal_toolchain, git). tools/bench_runner.zsh adds those, so
// that the context is collected once, by one tool, with its guards.
//
// Two modes:
//   single window (default)  one record measured over --duration-s seconds
//   --state decay            one record every --interval-s seconds for
//                            --duration-s seconds, each with t_s
//
// The workload is SGEMM, because Phase 2 is about SGEMM and the harness should
// be proven on the same kind of load it will measure.

#include "build_info.hpp"

#include <Accelerate/Accelerate.h>

#include <chrono>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <exception>
#include <format>
#include <string>
#include <string_view>
#include <vector>

extern "C" int mcx_thermal_state() noexcept;  // thermal_state.mm

namespace {

using Clock = std::chrono::steady_clock;

constexpr std::string_view kSubject = "hello_gemm";

struct Options {
    std::string variant = "accelerate";  // accelerate | naive
    std::string state = "unknown";       // burst | steady | decay | unknown
    int round = 1;
    int phase = 0;
    int n = 0;                // 0: per-variant default
    double duration_s = 0.2;  // window (single mode) or total run (decay mode)
    double interval_s = 2.0;  // sample interval in decay mode
};

[[noreturn]] void usage_error(std::string_view message) {
    std::fprintf(stderr, "bench_hello: %.*s\n", static_cast<int>(message.size()), message.data());
    std::fprintf(stderr,
                 "usage: bench_hello [--variant accelerate|naive] [--state burst|steady|decay|unknown]\n"
                 "                   [--round N] [--phase N] [--n N] [--duration-s S] [--interval-s S]\n");
    std::exit(2);
}

Options parse(int argc, char** argv) {
    Options o;
    for (int i = 1; i < argc; ++i) {
        const std::string_view key = argv[i];
        if (i + 1 >= argc) {
            usage_error(std::format("missing value for {}", key));
        }
        const std::string value = argv[++i];
        try {
            if (key == "--variant") {
                o.variant = value;
            } else if (key == "--state") {
                o.state = value;
            } else if (key == "--round") {
                o.round = std::stoi(value);
            } else if (key == "--phase") {
                o.phase = std::stoi(value);
            } else if (key == "--n") {
                o.n = std::stoi(value);
            } else if (key == "--duration-s") {
                o.duration_s = std::stod(value);
            } else if (key == "--interval-s") {
                o.interval_s = std::stod(value);
            } else {
                usage_error(std::format("unknown option {}", key));
            }
        } catch (const std::exception&) {
            usage_error(std::format("invalid value for {}: {}", key, value));
        }
    }
    if (o.variant != "accelerate" && o.variant != "naive") {
        usage_error(std::format("unknown variant {}", o.variant));
    }
    if (o.state != "burst" && o.state != "steady" && o.state != "decay" && o.state != "unknown") {
        usage_error(std::format("unknown state {}", o.state));
    }
    if (o.n == 0) {
        // Sizes chosen so that one call takes a few milliseconds on an M3:
        // short enough to fill a 200 ms burst window with many calls.
        o.n = (o.variant == "accelerate") ? 1024 : 256;
    }
    if (o.n <= 0 || o.duration_s <= 0.0 || o.interval_s <= 0.0) {
        usage_error("sizes and durations must be positive");
    }
    return o;
}

class Gemm {
public:
    explicit Gemm(int n)
        : n_(n), size_(static_cast<std::size_t>(n) * static_cast<std::size_t>(n)), a_(size_),
          b_(size_), c_(size_) {
        for (std::size_t i = 0; i < size_; ++i) {
            a_[i] = static_cast<float>(i % 7) * 0.25f;
            b_[i] = static_cast<float>(i % 5) * 0.5f;
        }
    }

    void run(std::string_view variant) {
        if (variant == "accelerate") {
            cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, n_, n_, n_, 1.0f, a_.data(), n_,
                        b_.data(), n_, 0.0f, c_.data(), n_);
        } else {
            naive();
        }
        // Read the result so the work cannot be optimised away.
        sink_ = sink_ + static_cast<double>(c_[size_ / 2]);
    }

    [[nodiscard]] double flops_per_call() const {
        const double n = static_cast<double>(n_);
        return 2.0 * n * n * n;
    }

private:
    // ikj order: the deliberately simple baseline Phase 2 starts from.
    void naive() {
        const std::size_t n = static_cast<std::size_t>(n_);
        for (std::size_t i = 0; i < size_; ++i) {
            c_[i] = 0.0f;
        }
        for (std::size_t i = 0; i < n; ++i) {
            for (std::size_t k = 0; k < n; ++k) {
                const float aik = a_[i * n + k];
                for (std::size_t j = 0; j < n; ++j) {
                    c_[i * n + j] += aik * b_[k * n + j];
                }
            }
        }
    }

    int n_;
    std::size_t size_;
    std::vector<float> a_;
    std::vector<float> b_;
    std::vector<float> c_;
    volatile double sink_ = 0.0;
};

// Runs whole calls until the window has elapsed; returns GFLOP/s.
double measure(Gemm& gemm, std::string_view variant, double window_s) {
    const auto start = Clock::now();
    long calls = 0;
    std::chrono::duration<double> elapsed{0.0};
    do {
        gemm.run(variant);
        ++calls;
        elapsed = Clock::now() - start;
    } while (elapsed.count() < window_s);
    return static_cast<double>(calls) * gemm.flops_per_call() / elapsed.count() / 1e9;
}

std::string utc_now() {
    const std::time_t now = std::time(nullptr);
    std::tm tm{};
    gmtime_r(&now, &tm);
    char buf[32];
    std::strftime(buf, sizeof buf, "%Y-%m-%dT%H:%M:%SZ", &tm);
    return buf;
}

std::string_view pressure_name(int state) {
    switch (state) {
    case 0:
        return "nominal";
    case 1:
        return "fair";
    case 2:
        return "serious";
    case 3:
        return "critical";
    default:
        return "unknown";
    }
}

std::string json_escape(std::string_view s) {
    std::string out;
    out.reserve(s.size());
    for (const char ch : s) {
        switch (ch) {
        case '"':
            out += "\\\"";
            break;
        case '\\':
            out += "\\\\";
            break;
        case '\n':
            out += "\\n";
            break;
        default:
            out += ch;
        }
    }
    return out;
}

void emit(const Options& o, double gflops, const double* t_s) {
    std::string line = std::format(
        R"({{"schema":1,"ts":"{}","phase":{},"subject":"{}","variant":"{}","round":{},)",
        utc_now(), o.phase, kSubject, o.variant, o.round);
    if (t_s != nullptr) {
        line += std::format(R"("t_s":{:.3f},)", *t_s);
    }
    line += std::format(
        R"("params":{{"n":{}}},"metric":"throughput","unit":"GFLOP/s","value":{:.3f},)", o.n,
        gflops);
    line += std::format(R"("thermal":{{"state":"{}","pressure":"{}"}},)", o.state,
                        pressure_name(mcx_thermal_state()));
    line += std::format(R"("env":{{"compiler":"{}","flags":"{}"}}}})",
                        json_escape(mcx::bench::kCompiler), json_escape(mcx::bench::kFlags));
    std::puts(line.c_str());
    std::fflush(stdout);  // the runner reads records as they are produced
}

}  // namespace

int main(int argc, char** argv) {
    const Options o = parse(argc, argv);
    Gemm gemm(o.n);

    if (o.state != "decay") {
        emit(o, measure(gemm, o.variant, o.duration_s), nullptr);
        return 0;
    }

    const auto start = Clock::now();
    for (;;) {
        const double gflops = measure(gemm, o.variant, o.interval_s);
        const double t_s = std::chrono::duration<double>(Clock::now() - start).count();
        emit(o, gflops, &t_s);
        if (t_s >= o.duration_s) {
            break;
        }
    }
    return 0;
}
