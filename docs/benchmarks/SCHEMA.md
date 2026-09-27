# Benchmark result schema — v1

Every result is one JSON object per line (JSONL) under
`docs/benchmarks/results/`. Measurements cannot be re-run later — the compiler,
OS and code of that moment will be gone — so the schema is fixed before the
first measurement.

## Fields

| Field | Type | Req. | Description |
|---|---|---|---|
| `schema` | int | ✓ | `1` for this version |
| `ts` | string | ✓ | ISO 8601 UTC, e.g. `2026-10-01T10:15:00Z` |
| `machine` | string | ✓ | `m3air16` \| `m4air32` |
| `phase` | int | ✓ | roadmap phase number |
| `subject` | string | ✓ | what is measured, e.g. `gemm_f32`, `thermal_decay` |
| `variant` | string | ✓ | implementation, e.g. `naive`, `neon`, `accelerate` |
| `round` | int | ✓ | 1-based interleaving round (`1` for a single continuous run) |
| `t_s` | number | | seconds since the start of the run, for time series |
| `params` | object | ✓ | problem parameters, e.g. `{"m":1024,"n":1024,"k":1024}` |
| `metric` | string | ✓ | `throughput` \| `latency` \| `bandwidth` \| … |
| `unit` | string | ✓ | `GFLOP/s` \| `ms` \| `GB/s` \| `tok/s` \| … |
| `value` | number | ✓ | the measurement |
| `thermal.state` | string | ✓ | `burst` \| `steady` \| `decay` \| `unknown` |
| `thermal.cpu_mhz` | number | | from `powermetrics`, if captured |
| `thermal.room_c` | number | | room temperature, if recorded |
| `env.macos` | string | ✓ | e.g. `26.6.2/25G83` |
| `env.xcode` | string | ✓ | e.g. `26.6/17F113` |
| `env.metal_toolchain` | string | ✓ | e.g. `17F109` (versioned independently of Xcode) |
| `env.compiler` | string | ✓ | reported by the benchmark binary |
| `env.flags` | string | ✓ | reported by the benchmark binary |
| `git` | string | ✓ | short hash; `-dirty` suffix if the tree was not clean |
| `notes` | string | | free text |

### `thermal.state`

- `burst` — first measurement from a cold machine
- `steady` — measured after sustained saturation
- `decay` — a sample from a continuous run, meaningful only together with `t_s`
- `unknown` — not controlled; never cite these in articles

## Where each field comes from

- `machine`, `env.macos`, `env.xcode`, `env.metal_toolchain`, `git`:
  `tools/bench_context.zsh`
- `env.compiler`, `env.flags`: baked into the benchmark binary at build time.
  The shell must not guess them — it cannot know how a binary was built.
- Everything else: the benchmark binary.

`tools/bench_context.zsh` refuses to run when a conda environment is active
(it replaces `ld` and `ar` for Homebrew LLVM) or when `CC`/`CXX` are exported
(they override the preset's compiler). A context that cannot be collected
cannot be recorded.

## Rules

1. Result files are append-only. Never edit or delete a recorded line.
2. Adding an optional field keeps the version. Renaming or removing a field,
   making an optional field required, or changing a field's meaning or unit
   increments `schema`.
3. Every reader must handle every schema version present in the repository.
4. Results with a `-dirty` git hash are exploratory only and are never cited
   in articles or the README.
5. Numbers without `thermal.state` are not interpretable on a fanless machine.
6. A result file must stay under the 1 MB limit of the pre-commit hook. Split
   long runs into several files or lower the sampling rate; do not raise the
   limit.

## File naming

`docs/benchmarks/results/<YYYYMMDDThhmmssZ>_<machine>_<subject>.jsonl`

## Example

```json
{"schema":1,"ts":"2026-10-01T10:15:00Z","machine":"m3air16","phase":2,"subject":"gemm_f32","variant":"neon","round":3,"params":{"m":1024,"n":1024,"k":1024},"metric":"throughput","unit":"GFLOP/s","value":142.7,"thermal":{"state":"burst"},"env":{"macos":"26.6.2/25G83","xcode":"26.6/17F113","metal_toolchain":"17F109","compiler":"Apple clang version 21.0.0","flags":"-O3 -mcpu=apple-m3"},"git":"a1b2c3d"}
```
