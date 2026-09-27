# ADR-0002: Compiler and editor selection

- Status: accepted
- Date: 2026-08-17 (measurements recorded 2026-09-28)
- Phase: 0

## Context

Three clang toolchains coexist on macOS — Apple Clang, Homebrew LLVM, and the
Metal shader compiler — and the project runs on two fanless MacBook Airs. A
consistent choice matters more than an optimal one: any drift between the two
machines invalidates cross-machine benchmarks.

## Decision

### Compiler

| Role | Choice |
|---|---|
| Default C++ compiler | **Apple Clang** (bundled with Xcode) |
| Secondary | Homebrew LLVM — C++26 experiments, codegen comparison, and the source of clangd / clang-format / clang-tidy |
| Metal shaders | `xcrun -sdk macosx metal` (no alternative exists) |

Apple Clang is the default because the C++23 library features this project
relies on (`std::mdspan`, `std::expected`, `std::print`) are present, and
because it avoids libc++ ABI mixing, keeps Objective-C++ interop working, and
integrates with the SDK availability attributes.

### Identical toolchains on both machines

As recorded in `docs/environment/`, both machines run the same macOS
(26.6.2, 25G83), Xcode (26.6, 17F113), Metal Toolchain (17F109) and Apple Clang
(21.0.0). Automatic Xcode updates are disabled so that this stays true; any
upgrade is done on both machines together and re-recorded with
`tools/record_env.zsh`.

### No conda in builds or benchmarks

Activating a conda environment places its own `ld` and `ar` ahead on `PATH`.
Homebrew LLVM picks them up; Apple Clang does not. Builds and benchmarks
therefore run with conda deactivated. `tools/bench_context.zsh` refuses to run
while a conda environment is active, and `tools/record_env.zsh` inherits that
check.

### `-mcpu` policy

- Build natively on each machine; never copy binaries between them.
- For cross-machine comparisons, build both with the lower common baseline
  (`-mcpu=apple-m3`), so compiler code generation does not contaminate the
  hardware comparison.
- The compiler and flags are reported in every benchmark result
  (`env.compiler`, `env.flags`).

### Editor

VS Code with clangd on both machines. Configuration lives in `.vscode/` and
`.clangd` inside the repository so the two machines cannot drift apart. The
editor is closed before any benchmark: background indexing heats a fanless
chassis.

## Feature probe results

Full macro lists: `docs/environment/m3air16.md`, `docs/environment/m4air32.md`.

The two compilers differ only locally: Apple Clang lacks 7 library macros that
Homebrew LLVM has (including `__cpp_lib_ranges_zip`) and reports older values
for 6 others. The macros that decide this project's design are covered in
ADR-0003.

## Consequences

- One editor configuration, committed and shared by both machines.
- Metal shader editing is syntax-highlighting only; correctness is checked by
  `xcrun metal -fsyntax-only`.
- Profiling happens outside the editor, via `xctrace` or Xcode.
- The environment checker published with the setup articles lives in the
  article repository (`Avrora4/zenn-contents`, `scripts/check-env.zsh`); see
  ADR-0004.

## Rejected because

- **Homebrew LLVM as the default:** libc++ ABI mixing and Objective-C++ friction
  outweigh a newer standard library, given that Apple Clang already covers the
  C++23 features this project uses. The belief that Apple Clang lags upstream by
  two or three major versions was wrong: measured, it is 21.0.0 against 22.1.8.
- **CLion:** no Metal shading language support (two full phases of this
  project), no Instruments integration, and a 2–4 GB resident footprint on a
  fanless chassis. Non-commercial use is free, so revisit if debugging the
  autodiff engine outgrows CodeLLDB.
- **Xcode as the editor:** its multi-config generator conflicts with the preset
  layout, and its indexer is weaker on template-heavy code.
