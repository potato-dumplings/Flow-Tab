import Foundation
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func waitUntil(
        _ description: String,
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollIntervalNanoseconds: UInt64 = 50_000_000,
        predicate: @escaping () -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        repeat {
            if predicate() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        } while DispatchTime.now().uptimeNanoseconds < deadline

        RuntimeLog.debug("TestWait", "timeout description=\(description)")
        return predicate()
    }
}
