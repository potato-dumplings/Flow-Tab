import Foundation
import XCTest

enum FlowTabUITestStatusItemObservationPolicy {
    static let elementWatchdog: TimeInterval = 6
}

private struct FlowTabUITestStatusElementSnapshot {
    struct Query {
        let source: String
        let exists: Bool
    }

    let queries: [Query]

    var firstExistingIndex: Int? {
        queries.firstIndex(where: { $0.exists })
    }

    var diagnosticSummary: String {
        let descriptions = queries.map {
            "\($0.source){exists=\($0.exists)}"
        }
        return "queries=[\(descriptions.joined(separator: ","))]"
    }
}

extension FlowTabUITests {
    func flowTabStatusItem(
        in app: XCUIApplication? = nil,
        timeout: TimeInterval =
            FlowTabUITestStatusItemObservationPolicy.elementWatchdog
    ) -> XCUIElement {
        let systemUIServer = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
        let predicate = NSPredicate(
            format: "identifier == %@ OR label == %@ OR label == %@",
            Identifier.statusItem,
            "FlowTab",
            "Flow Tab"
        )
        let queries = ([app].compactMap { $0 } + [systemUIServer]).map {
            $0.descendants(matching: .any).matching(predicate).firstMatch
        }

        return waitForFlowTabStatusElement(
            queries: queries,
            querySources: querySources(hasFlowTabApplication: app != nil),
            timeout: timeout,
            description: "FlowTab status item"
        )
    }

    func flowTabStatusMenuQuitItem(
        in app: XCUIApplication? = nil,
        openingWith statusItem: XCUIElement,
        timeout: TimeInterval =
            FlowTabUITestStatusItemObservationPolicy.elementWatchdog
    ) -> XCUIElement {
        let systemUIServer = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
        let predicate = NSPredicate(
            format: "identifier == %@ OR label == %@ OR label == %@",
            Identifier.statusItemQuit,
            "退出",
            "Quit"
        )
        let queries = ([app].compactMap { $0 } + [systemUIServer]).map {
            $0.descendants(matching: .any).matching(predicate).firstMatch
        }

        return waitForFlowTabStatusElement(
            queries: queries,
            querySources: querySources(hasFlowTabApplication: app != nil),
            timeout: timeout,
            description: "status-item quit menu item",
            trigger: {
                XCUIElement.perform(withKeyModifiers: .control) {
                    statusItem.tap()
                }
            }
        )
    }

    private func waitForFlowTabStatusElement(
        queries: [XCUIElement],
        querySources: [String],
        timeout: TimeInterval,
        description: String,
        trigger: (() -> Void)? = nil
    ) -> XCUIElement {
        let owner = FlowTabUITestConditionObservationOwner(
            observationRegistration:
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
            readback: {
                FlowTabUITestStatusElementSnapshot(
                    queries: zip(querySources, queries).map { pair in
                        FlowTabUITestStatusElementSnapshot.Query(
                            source: pair.0,
                            exists: pair.1.exists
                        )
                    }
                )
            },
            isSatisfied: { $0.firstExistingIndex != nil },
            describe: \.diagnosticSummary
        )
        owner.start()
        defer { owner.cancel() }

        if owner.resolvedEvidence == nil {
            trigger?()
        }

        guard
            let evidence = owner.waitForResolution(timeout: timeout),
            let index = evidence.value.firstExistingIndex
        else {
            XCTFail("Missing \(description). \(owner.diagnosticSummary)")
            return queries.first
                ?? XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
                    .descendants(matching: .any)
                    .firstMatch
        }
        return queries[index]
    }

    private func querySources(
        hasFlowTabApplication: Bool
    ) -> [String] {
        if hasFlowTabApplication {
            return ["FlowTab application", "SystemUIServer"]
        } else {
            return ["SystemUIServer"]
        }
    }
}
