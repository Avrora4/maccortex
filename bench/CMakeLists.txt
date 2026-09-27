# Codegen-relevant flags of this build type, reported in every result.
# Warning flags are omitted on purpose: they do not change the generated code.
string(TOUPPER "${CMAKE_BUILD_TYPE}" _mcx_build_type)
set(MCX_BENCH_FLAGS "${CMAKE_CXX_FLAGS} ${CMAKE_CXX_FLAGS_${_mcx_build_type}}")
string(STRIP "${MCX_BENCH_FLAGS}" MCX_BENCH_FLAGS)
configure_file(build_info.hpp.in ${CMAKE_CURRENT_BINARY_DIR}/build_info.hpp @ONLY)

find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)

add_executable(bench_hello bench_hello.cpp thermal_state.mm)
target_include_directories(bench_hello PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
# The new Accelerate headers; the classic CBLAS interface is deprecated and
# would fail the -Werror build in CI.
target_compile_definitions(bench_hello PRIVATE ACCELERATE_NEW_LAPACK)
target_link_libraries(bench_hello PRIVATE MacCortex::core ${FOUNDATION_FRAMEWORK})
mcx_set_warnings(bench_hello)
