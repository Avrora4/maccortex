# ADR-0003: Tensor view strategy (mdspan without submdspan)
 
- Status: accepted
- Date: 2026-08-22
- Phase: 1
 
## Context
Measured on macOS 26.6.2 (25G83) with Xcode 26.6 (17F113):
 
| Feature macro | Apple Clang 21.0.0 | Homebrew LLVM 22.1.8 |
|---|---|---|
| `__cpp_lib_mdspan` | 202406L | 202406L |
| `__cpp_lib_submdspan` | **absent** | **absent** |
| `__cpp_lib_aligned_accessor` | 202411L | 202411L |
| `__cpp_lib_hardware_interference_size` | 201703L | 201703L |
| `__cpp_lib_simd` | **absent** | **absent** |
| `__cpp_lib_linalg` | **absent** | **absent** |
 
`std::mdspan` is available at a level newer than C++23 requires (202406L), but
`submdspan` (P2630) is implemented by neither compiler. Zero-copy slicing is
the single most used operation in a tensor library, so this gap is on the
critical path.
 
## Options considered
1. **Write a fully custom TensorView** (pointer + shape + strides).
   Full control, but discards a standard facility that is otherwise complete,
   and leaves no migration path when `submdspan` lands.
2. **Use `mdspan` with `layout_stride` and implement only `mcx::subview`.**
   Fills exactly the missing piece.
3. **Wait / avoid slicing.** Not viable.
 
## Decision
Option 2. Represent every tensor view as
`std::mdspan<T, std::dextents<size_t, Rank>, std::layout_stride>` and provide
 
```cpp
namespace mcx {
// std::submdspan (P2630) is unimplemented as of 2026-08 on both Apple Clang 21
// and LLVM 22, so this fills the gap for layout_stride mdspans.
template <class T, class Extents, class... Slices>
constexpr auto subview(std::mdspan<T, Extents, std::layout_stride> src,
                       Slices... slices);
}
```
 
Slicing reduces to offsetting the data handle and rebuilding extents/strides,
which is roughly 150 lines including `full_extent`, integral index and
`strided_slice` support.
 
Use `std::aligned_accessor` (202411L, available on both) to express the
alignment guarantee of tensor storage, and `hardware_destructive_interference_size`
for cache-line padding rather than hardcoding 128.
 
## Consequences
- Tests must compare `mcx::subview` against a hand-rolled reference, since no
  standard implementation exists to check against.
- When `submdspan` ships, `mcx::subview` becomes a thin forwarding wrapper and
  can be deleted. The migration path is preserved.
- `std::simd` and `std::linalg` are absent, so Phase 2 uses NEON intrinsics
  directly and Accelerate BLAS as the reference, with no standard fallback.
 
## Rejected because
- A fully custom TensorView throws away a working standard `mdspan` and the
  `layout_stride` machinery that already models strided views correctly.
