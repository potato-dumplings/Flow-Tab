import Foundation
import XCTest

private enum FlowTabUITestPointerSwitcherPresentationPolicy {
    static let triggerDeliveryWatchdog: TimeInterval = 4
    static let panelPresentationWatchdog: TimeInterval = 5
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
            timeout:
                FlowTabUITestPointerSwitcherPresentationPolicy
                    .triggerDeliveryWatchdog
        )
        return diagnosticsSummary.waitForExistence(
            timeout:
                FlowTabUITestPointerSwitcherPresentationPolicy
                    .panelPresentationWatchdog
        )
    }
}
