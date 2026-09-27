#include <maccortex/version.hpp>
 
#include <print>
 
int main() {
    std::println("MacCortex {} [{}]", mcx::version(), mcx::build_info());
    return 0;
}
