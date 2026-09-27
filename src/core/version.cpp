#include <maccortex/version.hpp>
 
namespace mcx {
 
std::string_view version() noexcept {
    return "0.0.1";
}
 
std::string_view build_info() noexcept {
#if defined(MCX_HAS_METAL) && defined(MCX_HAS_SME)
    return "cpu(neon,sme,accelerate) + metal";
#elif defined(MCX_HAS_METAL)
    return "cpu(neon,accelerate) + metal";
#elif defined(MCX_HAS_SME)
    return "cpu(neon,sme,accelerate)";
#else
    return "cpu(neon,accelerate)";
#endif
}
 
}  // namespace mcx
