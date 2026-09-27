# MacCortex

[![ci](https://github.com/Avrora4/maccortex/actions/workflows/ci.yml/badge.svg)](https://github.com/Avrora4/maccortex/actions/workflows/ci.yml)

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
Verified toolchains: [docs/environment/](docs/environment/).

## Getting started

`git clone` does not carry hooks or local configuration. Run this once per clone:

```sh
./tools/setup_clone.zsh <m3air16|m4air32>
```

## Build

Requires Xcode with the Metal Toolchain component, CMake 3.28 or later, and Ninja.
Deactivate conda and leave `CC`/`CXX` unset before building.

```sh
cmake --preset macos-release
cmake --build --preset macos-release
ctest --preset macos-release
```

## Benchmarks

See the [protocol](docs/benchmarks/PROTOCOL.md). Plotting needs a Python
virtual environment:

```sh
python3 -m venv .venv
.venv/bin/pip install -r tools/requirements.txt
```

## Documentation

- [Roadmap](docs/ROADMAP.md) (Japanese)
- [Conventions](docs/conventions.md)
- [Architecture decision records](docs/adr/)
- [Benchmark schema](docs/benchmarks/SCHEMA.md) and [protocol](docs/benchmarks/PROTOCOL.md)

## License

MIT
