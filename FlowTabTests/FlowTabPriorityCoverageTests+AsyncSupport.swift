import Foundation
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
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
            let actualSeededLogCount = lines.filter { $0.contains("[UITest] seeded-") }.count
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
}
