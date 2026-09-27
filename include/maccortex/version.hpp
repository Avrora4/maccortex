#pragma once
 
#include <string_view>
 
namespace mcx {
 
/// Semantic version of the library, bumped once per completed phase.
[[nodiscard]] std::string_view version() noexcept;
 
/// Human readable summary of the backends compiled into this build.
[[nodiscard]] std::string_view build_info() noexcept;
 
}  // namespace mcx
