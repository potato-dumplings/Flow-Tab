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

    @MainActor
    func waitForLaunchBootstrapSearchAndSeededLogs(
        panelController: SwitcherPanelController,
        seededLogCount: Int,
        timeoutNanoseconds: UInt64 = 4_000_000_000,
        pollIntervalNanoseconds: UInt64 = 100_000_000
    ) async -> [String] {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        var lines: [String] = []

        repeat {
            lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 200, minimumLevel: .debug)
            let actualSeededLogCount = lines.filter {
                $0.contains("[UITest]") && $0.contains("message.fieldCount=0")
            }.count
            if
                panelController.modelForTesting.isSearchActive,
                panelController.modelForTesting.session != nil,
                actualSeededLogCount == seededLogCount
            {
                return lines
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        } while DispatchTime.now().uptimeNanoseconds < deadline

        return lines
    }

    @MainActor
    func waitForHotkeyReplaySuppressionToEnd(
        panelController: SwitcherPanelController,
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollIntervalNanoseconds: UInt64 = 10_000_000
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        repeat {
            if !panelController.suppressHotkeyReplayUntilReleaseForTesting {
                return true
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        } while DispatchTime.now().uptimeNanoseconds < deadline

        return !panelController.suppressHotkeyReplayUntilReleaseForTesting
    }
}
