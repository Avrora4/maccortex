include(FetchContent)
# v2.4.12 or later is required: v2.4.11 declares cmake_minimum_required(3.0),
# which CMake 4.x refuses to configure. SYSTEM keeps our strict warning flags
# from firing inside the third-party header.
FetchContent_Declare(doctest
    GIT_REPOSITORY https://github.com/doctest/doctest.git
    GIT_TAG v2.4.12
    SYSTEM)
FetchContent_MakeAvailable(doctest)
 
add_executable(mcx_tests
    unit/test_version.cpp)
target_link_libraries(mcx_tests PRIVATE MacCortex::core doctest::doctest)
mcx_set_warnings(mcx_tests)
 
include(${doctest_SOURCE_DIR}/scripts/cmake/doctest.cmake)
doctest_discover_tests(mcx_tests)
