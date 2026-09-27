# MacCortex

A from-scratch deep learning framework in C++23 for Apple Silicon.
No CUDA — NEON, SME, Accelerate and Metal only.

## Status

Phase 0 (build, test and benchmark foundation) — in progress.
Almost nothing works yet.

## Target machines

| ID | Machine | Notes |
|---|---|---|
| `m3air16` | MacBook Air M3, 16 GB | fanless; matrix hardware (AMX) reachable only via Accelerate |
| `m4air32` | MacBook Air M4, 32 GB | fanless; ARM SME available |

Both machines are fanless, so every benchmark in this repository follows an
interleaved protocol with explicit burst and steady-state figures.

## Getting started

`git clone` does not carry hooks or local configuration. Run this once per clone:

```sh
./tools/setup_clone.zsh <m3air16|m4air32>
```

## License

MIT
