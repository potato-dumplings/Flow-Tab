import Foundation
import XCTest

private enum FlowTabUITestPointerSwitcherPresentationPolicy {
    static let triggerDeliveryWatchdog: TimeInterval = 4
    static let panelPresentationWatchdog: TimeInterval = 5
}

enum FlowTabUITestStationaryPointerPolicy {
    static let applicationReadinessWatchdog: TimeInterval = 10
    static let elementReadbackWatchdog: TimeInterval = 5
    static let panelDismissalWatchdog: TimeInterval = 3
    static let gateEvidenceWatchdog: TimeInterval = 5
    static let processTerminationWatchdog: TimeInterval = 5
}

final class FlowTabUITestPointerSelectionGateObservationOwner {
    private let runtimeLogOwner:
        FlowTabUITestRuntimeLogObservationOwner

    init(
        targetKind: String,
        targetID: String,
        targetAppID: String? = nil,
        preservedSelection: String,
        baseline: FlowTabUITestRuntimeLogObservationBaseline
    ) {
        var marker =
            "pointerSelectionGate outcome=blocked "
            + "targetKind=\(targetKind) "
            + "targetID=\(Self.escaped(targetID))"
        if let targetAppID {
            marker +=
                " targetAppID=\(Self.escaped(targetAppID))"
        }
        marker +=
            " preservedSelection="
            + Self.escaped(preservedSelection)
        runtimeLogOwner =
            FlowTabUITestRuntimeLogObservationOwner(
                expectation: .allMarkers([marker]),
                observationRegistration:
                    baseline.observationRegistration(),
                readback: baseline.makeReadback
            )
    }

    func start() {
        runtimeLogOwner.start()
    }

    func waitForResolution(timeout: TimeInterval) -> Bool {
        runtimeLogOwner.waitForResolution(timeout: timeout)
            != nil
    }

    var diagnosticSummary: String {
        runtimeLogOwner.diagnosticSummary
    }

    func cancel() {
        runtimeLogOwner.cancel()
    }

    private static func escaped(_ value: String) -> String {
        value.addingPercentEncoding(
            withAllowedCharacters:
                CharacterSet.alphanumerics.union(
                    CharacterSet(charactersIn: "-._~")
                )
        ) ?? ""
    }
}

extension FlowTabUITests {
    var optionTabPointerHoverArguments: [String] {
        [
            "--flowtab-ui-reset-defaults",
            "--flowtab-ui-mock-runtime",
            "--flowtab-ui-listen-switcher-trigger",
            "--flowtab-ui-runtime-log-level",
            "DEBUG",
            "--flowtab-ui-enable-verbose-logs",
            "-showPermissionReminder",
            "NO"
        ]
    }

    var controlTabPointerHoverArguments: [String] {
        [
            "--flowtab-ui-reset-defaults",
            "--flowtab-ui-mock-runtime",
            "--flowtab-ui-mock-window-previews",
            "--flowtab-ui-mock-runtime-variant",
            "focused-current-app",
            "--flowtab-ui-frontmost-bundle-id",
            FlowTabUITestAppIdentity.configured()
                .bundleIdentifier,
            "--flowtab-ui-listen-switcher-trigger",
            "--flowtab-ui-runtime-log-level",
            "DEBUG",
            "--flowtab-ui-enable-verbose-logs",
            "-showPermissionReminder",
            "NO"
        ]
    }

    func openGlobalSwitcherForPointerHover(
        _ diagnosticsSummary: XCUIElement,
        traceLabel: String
    ) -> Bool {
        openSwitcherForPointerHover(
            .global,
            diagnosticsSummary: diagnosticsSummary,
            traceLabel: traceLabel
        )
    }

    func openInAppSwitcherForPointerHover(
        _ diagnosticsSummary: XCUIElement,
        traceLabel: String
    ) -> Bool {
        openSwitcherForPointerHover(
            .inApp,
            diagnosticsSummary: diagnosticsSummary,
            traceLabel: traceLabel
        )
    }

    func openSearchSwitcherForPointerHover(
        _ diagnosticsSummary: XCUIElement,
        traceLabel: String
    ) -> Bool {
        openSwitcherForPointerHover(
            .search,
            diagnosticsSummary: diagnosticsSummary,
            traceLabel: traceLabel
        )
    }

    private func openSwitcherForPointerHover(
        _ trigger: FlowTabUITestSwitcherTrigger,
        diagnosticsSummary: XCUIElement,
        traceLabel: String
    ) -> Bool {
        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
            trigger,
            traceLabel: traceLabel,
            receiptTimeout:
                FlowTabUITestPointerSwitcherPresentationPolicy
                    .triggerDeliveryWatchdog,
            completionTimeout:
                FlowTabUITestPointerSwitcherPresentationPolicy
                    .triggerDeliveryWatchdog
        )
        return diagnosticsSummary.waitForExistence(
            timeout:
                FlowTabUITestPointerSwitcherPresentationPolicy
                    .panelPresentationWatchdog
        )
    }

    func preparePointerSelectionGateObservation(
        targetKind: String,
        targetID: String,
        targetAppID: String? = nil,
        preservedSelection: String
    ) -> FlowTabUITestPointerSelectionGateObservationOwner {
        let owner =
            FlowTabUITestPointerSelectionGateObservationOwner(
                targetKind: targetKind,
                targetID: targetID,
                targetAppID: targetAppID,
                preservedSelection: preservedSelection,
                baseline: makeRuntimeLogFileSnapshot()
            )
        owner.start()
        return owner
    }

    func assertPointerSelectionGateBlocked(
        _ owner:
            FlowTabUITestPointerSelectionGateObservationOwner,
        diagnosticsSummary: XCUIElement,
        selectionKey: String,
        expectedSelection: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard
            owner.waitForResolution(
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .gateEvidenceWatchdog
            )
        else {
            XCTFail(
                "Pointer-selection gate evidence watchdog "
                    + "expired. \(owner.diagnosticSummary)",
                file: file,
                line: line
            )
            return
        }
        XCTAssertEqual(
            switcherPanelDiagnosticsValue(
                diagnosticsSummary,
                key: selectionKey
            ),
            expectedSelection,
            "The exact selected identity must remain "
                + "unchanged after the blocked hover. "
                + "summary=\(diagnosticsSummary.value ?? "")",
            file: file,
            line: line
        )
    }

    func dismissStationaryPointerSearch(
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitForNonExistence(
                diagnosticsSummary,
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .panelDismissalWatchdog
            ),
            file: file,
            line: line
        )
    }

    func assertStationaryPointerFrame(
        _ frame: CGRect,
        contains point: CGPoint,
        tolerance: CGFloat = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expandedFrame = frame.insetBy(
            dx: -tolerance,
            dy: -tolerance
        )
        XCTAssertTrue(
            expandedFrame.contains(point),
            "Expected stationary pointer point \(point) "
                + "to remain inside target frame \(frame).",
            file: file,
            line: line
        )
    }

    func hoverStationaryPointerScreenPoint(
        _ point: CGPoint,
        relativeTo element: XCUIElement
    ) {
        element.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        )
        .withOffset(
            CGVector(
                dx: point.x - element.frame.minX,
                dy: point.y - element.frame.minY
            )
        )
        .hover()
    }

    func terminateStationaryPointerPlacementApplication(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        app.terminate()
        XCTAssertTrue(
            app.wait(
                for: .notRunning,
                timeout:
                    FlowTabUITestStationaryPointerPolicy
                        .processTerminationWatchdog
            ),
            file: file,
            line: line
        )
    }
}
