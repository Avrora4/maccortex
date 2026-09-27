#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>
 
#include <maccortex/version.hpp>
 
TEST_CASE("version string is non-empty") {
    CHECK_FALSE(mcx::version().empty());
    CHECK_FALSE(mcx::build_info().empty());
}
