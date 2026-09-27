// Reads the OS thermal pressure without sudo, through NSProcessInfo.
// Returns 0 nominal, 1 fair, 2 serious, 3 critical.
//
// powermetrics would give frequencies and power, but needs root and a parsed
// child process; see ADR-0005 for why this is the Phase 0 choice.

#import <Foundation/Foundation.h>

extern "C" int mcx_thermal_state() noexcept {
    @autoreleasepool {
        return static_cast<int>([[NSProcessInfo processInfo] thermalState]);
    }
}
