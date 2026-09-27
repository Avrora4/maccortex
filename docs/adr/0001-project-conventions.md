# ADR-0001: Project name, namespace and identifier conventions
 
- Status: accepted
- Date: 2026-08-17
- Phase: 0
 
## Context
Renaming a project after publication breaks article links, tags and include
paths, so naming is fixed before the first commit.
 
## Decision
| Concern | Value |
|---|---|
| Display name | `MacCortex` |
| Repository / include dir / CMake package | `maccortex` |
| C++ namespace | `mcx` |
| Macro / option / env prefix | `MCX_` |
| CMake targets | `MacCortex::core`, `MacCortex::backend_metal`, ... |
| Metal kernels | `mcx_<op>_<dtype>_<variant>` |
 
Short namespace `mcx` is preferred over `maccortex` because it appears on
almost every line of kernel code, while the long form stays in include paths
where it aids discoverability.
 
## Consequences
- `#include <maccortex/core/tensor.hpp>` but `mcx::Tensor` in code.
- Any future C API uses the `mcx_` function prefix, matching the macros.
 
## Rejected because
- `maccortex::` as the code namespace: too long for dense numeric code.
- `mc::`: too generic, high collision risk with other libraries.
