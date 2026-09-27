# ADR-0005: Benchmark harness

- Status: accepted
- Date: 2026-09-28
- Phase: 0

## Context

Both machines are fanless MacBook Airs. Under sustained load their throughput
falls over time, so a benchmark result depends on how long the chassis has
been loaded and on what ran immediately before. The harness has to make that
visible rather than average it away, and it has to produce records in schema
v1 (`docs/benchmarks/SCHEMA.md`), which cannot change retroactively.

Phase 0 requires three things from it: a benchmark that emits schema records,
a 30-minute decay curve, and proof that an interleaved comparison gives the
same answer in both execution orders.

## Decision

- **A hand-written harness instead of a benchmarking library.** The benchmark
  binary (`bench/bench_hello`) measures one window, or a series of windows, and
  prints raw records. Order, repetition and cooldown are controlled from
  outside by `tools/bench_runner.zsh`.
- **Cooldown after every measurement**, not only between rounds.
- **Thermal pressure from `NSProcessInfo.thermalState`**, recorded as the
  optional field `thermal.pressure`. It needs no root. Adding an optional field
  keeps schema version 1.
- **Context collected once per run** by `tools/bench_context.zsh` and merged by
  the runner; compiler and flags are baked into the binary by CMake
  (`bench/build_info.hpp.in`).
- **Incomplete runs are never results.** The runner writes `*.jsonl.partial`
  and renames it only when the run completes.
- **Untracked files do not make a tree dirty.** Otherwise the result file of the
  first run would block the second run of an order-bias check.
- **Python only for figures** (`tools/plot_bench.py`, matplotlib in `.venv`).

## Consequences

- Every benchmark binary follows one contract: accept
  `--variant V --round R`, print schema v1 records without context to stdout.
- Burst and steady values come from explicit runs, not from a statistics
  package's warm-up heuristics.
- Frequencies and power are not recorded yet. `thermal.cpu_mhz` stays empty
  until `powermetrics` is integrated.
- Phase 0's structured logging and CLI parser were deferred: nothing needs them
  yet, and the benchmark binary's argument parsing is enough for now.

## Rejected because

- **nanobench (or Google Benchmark):** they choose epochs, warm-up and
  statistics themselves and report a summary. On a fanless machine that summary
  hides exactly the effect being measured, and the libraries control
  repetition order internally, which defeats interleaving.
- **`powermetrics` in Phase 0:** it requires root, a long-running child process
  and parsing of its output. The OS thermal state answers the Phase 0 question —
  when does the curve bend — without any of that.
- **Temperature-based cooldown** (wait until a threshold): no temperature is
  readable without root. A fixed cooldown is recorded in `notes` and validated
  by the order-bias check instead.
- **Cooldown only between rounds:** within a fixed order the second variant
  always starts warmer than the first, which is the bias the check exists to
  catch.
