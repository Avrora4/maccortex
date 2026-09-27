cmake_minimum_required(VERSION 3.28)

project(MacCortex
    VERSION 0.0.1
    DESCRIPTION "From-scratch deep learning framework for Apple Silicon"
    LANGUAGES CXX)

# --- Guard: this project targets Apple Silicon only ---------------------------
if(NOT APPLE)
    message(FATAL_ERROR "MacCortex targets macOS on Apple Silicon only.")
endif()

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# --- Options (all prefixed MCX_ so they never collide with dependencies) -----
option(MCX_BUILD_TESTS    "Build unit / gradcheck / golden tests" ON)
option(MCX_BUILD_BENCH    "Build benchmarks"                      ON)
option(MCX_BUILD_EXAMPLES "Build examples"                        ON)
option(MCX_ENABLE_METAL   "Build the Metal GPU backend"           OFF)
option(MCX_ENABLE_SME     "Build SME kernels (M4 generation+)"    OFF)
option(MCX_WARNINGS_AS_ERRORS "Treat warnings as errors"          OFF)

include(cmake/MacCortexWarnings.cmake)

# --- Core library -------------------------------------------------------------
add_library(mcx_core)
add_library(MacCortex::core ALIAS mcx_core)

target_sources(mcx_core PRIVATE src/core/version.cpp)
target_include_directories(mcx_core PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>)
target_compile_features(mcx_core PUBLIC cxx_std_23)
mcx_set_warnings(mcx_core)

# Accelerate provides BLAS/LAPACK/BNNS and is the reference upper bound for
# every hand-written CPU kernel in Phase 2.
find_library(ACCELERATE_FRAMEWORK Accelerate REQUIRED)
target_link_libraries(mcx_core PUBLIC ${ACCELERATE_FRAMEWORK})

if(MCX_ENABLE_SME)
    target_compile_options(mcx_core PRIVATE -march=armv8-a+sme)
    target_compile_definitions(mcx_core PUBLIC MCX_HAS_SME=1)
endif()

if(MCX_ENABLE_METAL)
    find_library(METAL_FRAMEWORK Metal REQUIRED)
    find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
    target_link_libraries(mcx_core PUBLIC ${METAL_FRAMEWORK} ${FOUNDATION_FRAMEWORK})
    target_compile_definitions(mcx_core PUBLIC MCX_HAS_METAL=1)
endif()

# --- Subdirectories -----------------------------------------------------------
if(MCX_BUILD_EXAMPLES)
    add_subdirectory(examples/hello_maccortex)
endif()

if(MCX_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

if(MCX_BUILD_BENCH)
    # Objective-C++ is needed only to read the OS thermal state (ADR-0005).
    # enable_language must run in the top-level directory.
    enable_language(OBJCXX)
    add_subdirectory(bench)
endif()
