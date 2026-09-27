# Architecture Decision Records

## Rules

1. Numbers are never reused. Rejected or abandoned ADRs stay in the repository.
2. An accepted ADR is never rewritten. To change a decision, write a new ADR.
3. The superseded ADR receives exactly one added line:
   `Status: superseded by ADR-XXXX`.
4. Every ADR states the options that were NOT taken, and why.
5. Typos and broken links may be fixed in place, as long as the meaning does
   not change.
6. Numbers are assigned when a decision is made, not when it is committed, so
   the commit order of ADRs may differ from their numbering.

These rules have no enforcement mechanism, which is why they are written here.

## Index

| ADR | Title | Status |
|---|---|---|
| [0001](0001-project-conventions.md) | Project name, namespace and identifier conventions | accepted |
| [0002](0002-toolchain-and-editor.md) | Compiler and editor selection | accepted |
| [0003](0003-tensor-view-strategy.md) | Tensor view strategy (mdspan without submdspan) | accepted |
| [0004](0004-repository-rules.md) | Repository rules | accepted |

Template: [0000-template.md](0000-template.md)

## Beliefs overturned by measurement

Kept on purpose: the reason a belief was wrong is itself a finding.

| Believed | Measured | See |
|---|---|---|
| Apple Clang lags upstream LLVM by two or three major versions | Apple Clang 21.0.0 against LLVM 22.1.8; 7 macros missing, 6 older | ADR-0002 |
| `std::simd` and `std::linalg` could be evaluated in Phase 2 | Absent on both compilers as of 2026-08 | ADR-0003 |
| `std::submdspan` would be available alongside `std::mdspan` | `mdspan` at 202406L, `submdspan` absent on both | ADR-0003 |
| Installing Xcode provides the `metal` compiler | Since Xcode 26 the Metal Toolchain is a separate MobileAsset component | ADR-0002 |
