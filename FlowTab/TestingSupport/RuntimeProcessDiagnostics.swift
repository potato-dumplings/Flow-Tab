#if FLOWTAB_TESTING
import Darwin
import Foundation

struct RuntimeProcessCPUSnapshot: Equatable, Sendable {
    let userNanoseconds: UInt64
    let systemNanoseconds: UInt64
    let isValid: Bool
}

enum RuntimeProcessDiagnosticClock {
    static func cpuSnapshot() -> RuntimeProcessCPUSnapshot {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else {
            return RuntimeProcessCPUSnapshot(
                userNanoseconds: 0,
                systemNanoseconds: 0,
                isValid: false
            )
        }
        return RuntimeProcessCPUSnapshot(
            userNanoseconds: nanoseconds(usage.ru_utime),
            systemNanoseconds: nanoseconds(usage.ru_stime),
            isValid: true
        )
    }

    private static func nanoseconds(_ value: timeval) -> UInt64 {
        UInt64(max(0, value.tv_sec)) * 1_000_000_000
            + UInt64(max(0, value.tv_usec)) * 1_000
    }
}
#endif
