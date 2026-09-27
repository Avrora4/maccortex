add_executable(hello_maccortex main.cpp)
target_link_libraries(hello_maccortex PRIVATE MacCortex::core)
mcx_set_warnings(hello_maccortex)
