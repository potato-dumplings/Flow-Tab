import XCTest

extension FlowTabUITests {
    func runAppPanelPressureInteraction(
        observer: AppPanelPressureUITestObserver,
        flow: AppPanelPressureUITestFlow,
        scenario: AppPanelPressureUITestScenario,
        cycle: Int,
        opened: AppPanelPressureUITestEvidence,
        lastSequence: inout UInt64
    ) -> AppPanelPressureUITestEvidence? {
        switch flow {
        case .application:
            guard observer.post(
                command: .advanceRight,
                traceLabel:
                    "app-panel-pressure.application."
                    + "\(cycle).highlight"
            ) else {
                return nil
            }
        case .applicationToWindow:
            var entryTarget = opened
            var remainingSelections = min(
                max(opened.appCount, 1),
                20
            )
            while entryTarget.selectedWindowCount < 2,
                  remainingSelections > 0
            {
                guard observer.post(
                    command: .advanceRight,
                    traceLabel:
                        "app-panel-pressure.app-to-window."
                        + "\(cycle).find-target"
                ) else {
                    return nil
                }
                guard let candidate = observer.wait(
                    phase: "highlighted",
                    after: lastSequence,
                    timeout:
                        AppPanelPressureUITestPolicy
                            .eventWatchdogSeconds
                ) else {
                    XCTFail(
                        "Window-panel target evidence watchdog expired"
                    )
                    return nil
                }
                lastSequence = candidate.sequence
                entryTarget = candidate
                remainingSelections -= 1
            }
            guard entryTarget.selectedWindowCount >= 2 else {
                XCTFail(
                    "No local application exposes two windows"
                )
                return nil
            }
            guard observer.post(
                command: .advanceDown,
                traceLabel:
                    "app-panel-pressure.app-to-window."
                    + "\(cycle).enter"
            ) else {
                return nil
            }
        case .search:
            do {
                try FlowTabUITestSwitcherCommandPayload
                    .write(scenario.searchQuery)
            } catch {
                XCTFail(
                    "Failed to write search pressure query: "
                        + error.localizedDescription
                )
                return nil
            }
            guard observer.post(
                command: .searchQuery,
                traceLabel:
                    "app-panel-pressure.search."
                    + "\(cycle).query"
            ) else {
                return nil
            }
        }

        guard let evidence = observer.wait(
            phase: "highlighted",
            after: lastSequence,
            timeout:
                AppPanelPressureUITestPolicy
                    .eventWatchdogSeconds
        ) else {
            XCTFail(
                "Pressure interaction evidence watchdog expired "
                    + "flow=\(flow.rawValue)"
            )
            return nil
        }
        return evidence
    }
}
