import AppKit
import ApplicationServices
import Foundation
import XCTest

private enum FlowTabUITestCGWindowDefaults {
    static let minimumValidWindowWidth: CGFloat = 80
    static let minimumValidWindowHeight: CGFloat = 60
    static let minimumValidWindowArea: CGFloat = 20_000
    static let fullscreenSpaceWindowScreenCoverageRatio: CGFloat = 0.8
    static let visibleAlphaThreshold = 0.001
    static let standardBufferedStoreType = 1
}

struct WorkflowCGWindowObservation: Equatable {
    let number: CGWindowID
    let title: String?
    let frame: CGRect?

    func matches(number expectedNumber: CGWindowID?, title expectedTitle: String?) -> Bool {
        if let expectedNumber, number == expectedNumber {
            return true
        }
        if let expectedTitle, title == expectedTitle {
            return true
        }
        return false
    }

    func matchesWorkflowSpaceWindow(title expectedTitle: String) -> Bool {
        if title == expectedTitle {
            return true
        }
        return title == nil && isFullscreenSpaceSized
    }

    var isFullscreenSpaceSized: Bool {
        guard let frame else { return false }
        guard let largestScreenFrame = NSScreen.screens
            .map({ $0.frame.standardized })
            .max(by: { ($0.width * $0.height) < ($1.width * $1.height) })
        else {
            return false
        }
        return frame.width >= largestScreenFrame.width * FlowTabUITestCGWindowDefaults.fullscreenSpaceWindowScreenCoverageRatio
            && frame.height >= largestScreenFrame.height * FlowTabUITestCGWindowDefaults.fullscreenSpaceWindowScreenCoverageRatio
    }
}

extension FlowTabUITests {
    func workflowWindowTitleIsObservable(
        _ title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> Bool {
        let expectedTitles = Set([title, "Selected Tab: \(title)"])
        return workflowWindowTitleExistsInXCTest(
            expectedTitles,
            bundleIdentifier: workflowApp.identity.bundleIdentifier
        ) || workflowWindowTitleExistsInAX(
            expectedTitles,
            bundleIdentifier: workflowApp.identity.bundleIdentifier
        )
    }

    private func workflowWindowTitleExistsInXCTest(
        _ expectedTitles: Set<String>,
        bundleIdentifier: String
    ) -> Bool {
        let fixtureApp = XCUIApplication(bundleIdentifier: bundleIdentifier)
        return expectedTitles.contains { fixtureApp.staticTexts[$0].exists }
    }

    private func workflowWindowTitleExistsInAX(
        _ expectedTitles: Set<String>,
        bundleIdentifier: String
    ) -> Bool {
        guard let runningApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated })
        else {
            return false
        }

        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        return axWindows(in: appElement).contains {
            var remainingNodeBudget = 250
            return axTreeContainsExpectedTitle(
                $0,
                expectedTitles: expectedTitles,
                remainingDepth: 8,
                remainingNodeBudget: &remainingNodeBudget
            )
        }
    }

    func activeWindowTitle(forBundleIdentifier bundleIdentifier: String) -> String? {
        guard let runningApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated })
        else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        return windowTitle(
            for: kAXFocusedWindowAttribute as CFString,
            in: appElement
        ) ?? windowTitle(
            for: kAXMainWindowAttribute as CFString,
            in: appElement
        ) ?? frontmostCGWindowTitle(forPID: runningApp.processIdentifier)
    }

    func waitForExactFrontmostSpaceFixtureWindow(
        title: String,
        titleAccessibilityIdentifier: String,
        processIdentifier: pid_t,
        bundleIdentifier: String,
        timeout: TimeInterval
    ) -> WorkflowCGWindowObservation? {
        let expectation =
            SpaceFixtureWorkflowDesktopAnchorExpectation(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: processIdentifier,
                windows: [
                    SpaceFixtureWorkflowDesktopAnchorWindowExpectation(
                        planIndex: 1,
                        title: title,
                        accessibilityIdentifier:
                            titleAccessibilityIdentifier
                    )
                ]
            )
        let application = XCUIApplication(
            bundleIdentifier: bundleIdentifier
        )
        let observationOwner =
            SpaceFixtureWorkflowDesktopAnchorObservationOwner(
                expectation: expectation,
                watchdogSeconds: timeout
            ) {
                self.workflowDesktopAnchorSnapshot(
                    expectation: expectation,
                    application: application
                )
            }
        observationOwner.start()
        defer { observationOwner.cancel() }

        guard let evidence =
                observationOwner.waitForResolution()
        else {
            XCTFail(
                "Expected exact frontmost fixture window "
                    + "\(bundleIdentifier) / \(title): "
                    + observationOwner.diagnosticSummary
            )
            return nil
        }
        guard let windowNumber =
                evidence.snapshot.topmostCGWindowNumber
        else {
            XCTFail(
                "Resolved fixture evidence omitted the CG window: "
                    + evidence.snapshot.logFields
            )
            return nil
        }
        return WorkflowCGWindowObservation(
            number: windowNumber,
            title: evidence.snapshot.topmostCGWindowTitle,
            frame: evidence.snapshot.topmostCGWindowFrame
        )
    }

    func frontmostCGWindow(
        forBundleIdentifier bundleIdentifier: String,
        expectedTitle: String,
        expectedWindowNumber: CGWindowID
    ) -> WorkflowCGWindowObservation? {
        guard let runningApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated })
        else {
            return nil
        }
        return frontmostCGWindow(
            forPID: runningApp.processIdentifier,
            expectedTitle: expectedTitle,
            expectedWindowNumber: expectedWindowNumber
        )
    }

    func waitForExactFrontmostWorkflowCGWindow(
        windowNumber: CGWindowID,
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App,
        timeout: TimeInterval
    ) -> Bool {
        let bundleIdentifier =
            workflowApp.identity.bundleIdentifier
        let owner =
            FlowTabUITestWorkflowWindowActivationObservationOwner(
                expectedBundleIdentifier: bundleIdentifier,
                expectedWindowNumber: windowNumber,
                expectedTitle: title,
                observationRegistration:
                    FlowTabUITestWorkflowWindowActivationObservation
                        .registration(
                            bundleIdentifier: bundleIdentifier
                        ),
                readback: {
                    self.workflowWindowActivationSnapshot(
                        title: title,
                        app: workflowApp
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard owner.waitForResolution(timeout: timeout) != nil else {
            XCTFail(
                "Expected exact frontmost CG window "
                    + "\(workflowApp.appName) / \(title) / "
                    + "\(windowNumber). "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    func waitForFrontmostWorkflowSpaceCGWindow(
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App,
        timeout: TimeInterval
    ) -> WorkflowCGWindowObservation? {
        let deadline = Date().addingTimeInterval(timeout)
        var latestFrontmostBundleIdentifier: String?
        var latestWindowNumber: CGWindowID?
        var latestTitle: String?
        var latestFrame: CGRect?
        repeat {
            latestFrontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let latestCGWindow = topmostOnScreenCGWindow(
                forBundleIdentifier: workflowApp.identity.bundleIdentifier
            )
            latestWindowNumber = latestCGWindow?.number
            latestTitle = latestCGWindow?.title
            latestFrame = latestCGWindow?.frame

            if latestFrontmostBundleIdentifier == workflowApp.identity.bundleIdentifier,
               let latestCGWindow,
               latestCGWindow.matchesWorkflowSpaceWindow(title: title) {
                return latestCGWindow
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail(
            """
            Expected frontmost workflow Space window \(workflowApp.appName) / \(title), \
            found frontmost bundle \(latestFrontmostBundleIdentifier ?? "nil") \
            with CG title \(latestTitle ?? "nil") \
            window number \(latestWindowNumber.map(String.init) ?? "nil") \
            and frame \(workflowCGFrameDescription(latestFrame)).
            """
        )
        return nil
    }

    func waitForActiveSpaceWorkflowCGWindow(
        windowNumber: CGWindowID,
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var latestWindowNumber: CGWindowID?
        var latestTitle: String?
        repeat {
            let latestCGWindow = topmostOnScreenCGWindow(
                forBundleIdentifier: workflowApp.identity.bundleIdentifier
            )
            latestWindowNumber = latestCGWindow?.number
            latestTitle = latestCGWindow?.title
            if latestCGWindow?.number == windowNumber {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail(
            """
            Expected active-space CG window \(workflowApp.appName) / \(title) / \(windowNumber), \
            found CG title \(latestTitle ?? "nil") \
            and window number \(latestWindowNumber.map(String.init) ?? "nil").
            """
        )
        return false
    }

    func waitForActiveSpaceWorkflowCGWindow(
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var latestWindowNumber: CGWindowID?
        var latestTitle: String?
        var latestFrame: CGRect?
        repeat {
            let latestCGWindow = topmostOnScreenCGWindow(
                forBundleIdentifier: workflowApp.identity.bundleIdentifier
            )
            latestWindowNumber = latestCGWindow?.number
            latestTitle = latestCGWindow?.title
            latestFrame = latestCGWindow?.frame
            if let latestCGWindow,
               latestCGWindow.matchesWorkflowSpaceWindow(title: title) {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail(
            """
            Expected active-space CG window \(workflowApp.appName) / \(title), \
            found CG title \(latestTitle ?? "nil") \
            window number \(latestWindowNumber.map(String.init) ?? "nil") \
            and frame \(workflowCGFrameDescription(latestFrame)).
            """
        )
        return false
    }

    func waitForWorkflowSpaceContainingCGWindow(
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var latestDescriptions: [String] = []
        repeat {
            let observations = workflowCGWindowObservations(
                bundleIdentifier: workflowApp.identity.bundleIdentifier,
                options: [.optionOnScreenOnly, .excludeDesktopElements]
            )
            latestDescriptions = observations.map { observation in
                "\(observation.number):\(observation.title ?? "nil")@\(workflowCGFrameDescription(observation.frame))"
            }
            if observations.contains(where: { $0.matchesWorkflowSpaceWindow(title: title) }) {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail(
            """
            Expected active workflow Space to contain \(workflowApp.appName) / \(title), \
            found CG windows [\(latestDescriptions.joined(separator: ";"))].
            """
        )
        return false
    }

    func logWorkflowSpaceObservation(
        _ stage: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App
    ) {
        logFlowTabUITestTrace(workflowSpaceObservationDescription(stage, app: workflowApp))
    }

    func workflowSpaceObservationDescription(
        _ stage: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> String {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        let activeTitle = activeWindowTitle(forBundleIdentifier: workflowApp.identity.bundleIdentifier) ?? "nil"
        let onScreenWindows = workflowCGWindowDebugDescriptions(
            bundleIdentifier: workflowApp.identity.bundleIdentifier,
            options: [.optionOnScreenOnly, .excludeDesktopElements]
        )
        let allWindows = workflowCGWindowDebugDescriptions(
            bundleIdentifier: workflowApp.identity.bundleIdentifier,
            options: [.optionAll, .excludeDesktopElements]
        )
        return """
        [\(stage)] frontmost=\(frontmost) target=\(workflowApp.identity.bundleIdentifier) \
        activeTitle=\(activeTitle) onScreen=[\(onScreenWindows.joined(separator: ";"))] \
        all=[\(allWindows.joined(separator: ";"))]
        """
    }

    private func frontmostCGWindowTitle(forPID pid: pid_t) -> String? {
        frontmostCGWindow(forPID: pid)?.title
    }

    func topmostOnScreenCGWindow(
        forBundleIdentifier bundleIdentifier: String
    ) -> WorkflowCGWindowObservation? {
        guard let runningApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated })
        else {
            return nil
        }
        return topmostOnScreenCGWindow(forPID: runningApp.processIdentifier)
    }

    func topmostOnScreenCGWindow(forPID pid: pid_t) -> WorkflowCGWindowObservation? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            guard cgWindowPID(window[kCGWindowOwnerPID as String]) == pid else {
                continue
            }
            guard cgWindowPassesValidityConstraints(window) else { continue }
            guard let number = cgWindowNumber(window[kCGWindowNumber as String]) else {
                continue
            }
            let frame = cgWindowFrame(window)
            let title = (window[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return WorkflowCGWindowObservation(
                number: number,
                title: title?.isEmpty == false ? title : nil,
                frame: frame
            )
        }
        return nil
    }

    private func workflowCGWindowDebugDescriptions(
        bundleIdentifier: String,
        options: CGWindowListOption
    ) -> [String] {
        workflowCGWindowObservations(
            bundleIdentifier: bundleIdentifier,
            options: options
        ).map { observation in
            "\(observation.number):\(observation.title ?? "nil")@\(workflowCGFrameDescription(observation.frame))"
        }
    }

    private func workflowCGWindowObservations(
        bundleIdentifier: String,
        options: CGWindowListOption
    ) -> [WorkflowCGWindowObservation] {
        guard let runningApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated })
        else {
            return []
        }
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windows.compactMap { window -> WorkflowCGWindowObservation? in
            guard cgWindowPID(window[kCGWindowOwnerPID as String]) == runningApp.processIdentifier else {
                return nil
            }
            guard cgWindowPassesValidityConstraints(window) else { return nil }
            guard let number = cgWindowNumber(window[kCGWindowNumber as String]) else {
                return nil
            }
            let title = (window[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return WorkflowCGWindowObservation(
                number: number,
                title: title?.isEmpty == false ? title : nil,
                frame: cgWindowFrame(window)
            )
        }
    }

    private func frontmostCGWindow(
        forPID pid: pid_t,
        expectedTitle: String? = nil,
        expectedWindowNumber: CGWindowID? = nil
    ) -> WorkflowCGWindowObservation? {
        let onScreenObservation = cgWindowObservation(
            forPID: pid,
            expectedTitle: expectedTitle,
            expectedWindowNumber: expectedWindowNumber,
            options: [.optionOnScreenOnly, .excludeDesktopElements],
            allowsTitledFallback: true
        )
        if onScreenObservation?.matches(number: expectedWindowNumber, title: expectedTitle) == true {
            return onScreenObservation
        }

        if expectedTitle != nil || expectedWindowNumber != nil {
            let exactObservation = cgWindowObservation(
                forPID: pid,
                expectedTitle: expectedTitle,
                expectedWindowNumber: expectedWindowNumber,
                options: [.optionAll, .excludeDesktopElements],
                allowsTitledFallback: false
            )
            if exactObservation?.matches(number: expectedWindowNumber, title: expectedTitle) == true {
                return exactObservation
            }
        }

        return onScreenObservation
    }

    private func cgWindowObservation(
        forPID pid: pid_t,
        expectedTitle: String?,
        expectedWindowNumber: CGWindowID?,
        options: CGWindowListOption,
        allowsTitledFallback: Bool
    ) -> WorkflowCGWindowObservation? {
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        var firstValidTitledWindow: WorkflowCGWindowObservation?
        for window in windows {
            guard cgWindowPID(window[kCGWindowOwnerPID as String]) == pid else {
                continue
            }
            guard cgWindowPassesValidityConstraints(window) else { continue }
            guard let number = cgWindowNumber(window[kCGWindowNumber as String]) else {
                continue
            }

            let title = (window[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let observation = WorkflowCGWindowObservation(
                number: number,
                title: title?.isEmpty == false ? title : nil,
                frame: cgWindowFrame(window)
            )
            if observation.matches(number: expectedWindowNumber, title: expectedTitle) {
                return observation
            }
            if allowsTitledFallback, observation.title != nil, firstValidTitledWindow == nil {
                firstValidTitledWindow = observation
            }
        }

        return firstValidTitledWindow
    }

    private func cgWindowPID(_ value: Any?) -> pid_t? {
        if let pid = value as? pid_t {
            return pid
        }
        if let number = value as? NSNumber {
            return pid_t(number.int32Value)
        }
        return nil
    }

    private func cgWindowPassesValidityConstraints(_ window: [String: Any]) -> Bool {
        guard (window[kCGWindowLayer as String] as? Int) == 0 else { return false }
        let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
        guard alpha > FlowTabUITestCGWindowDefaults.visibleAlphaThreshold else { return false }
        let storeType = (window[kCGWindowStoreType as String] as? NSNumber)?.intValue
            ?? FlowTabUITestCGWindowDefaults.standardBufferedStoreType
        guard storeType == FlowTabUITestCGWindowDefaults.standardBufferedStoreType else {
            return false
        }
        guard let bounds = (window[kCGWindowBounds as String] as? [String: Any])
            .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) })?
            .standardized
        else {
            return false
        }
        guard bounds.width >= FlowTabUITestCGWindowDefaults.minimumValidWindowWidth else {
            return false
        }
        guard bounds.height >= FlowTabUITestCGWindowDefaults.minimumValidWindowHeight else {
            return false
        }
        return bounds.width * bounds.height >= FlowTabUITestCGWindowDefaults.minimumValidWindowArea
    }

    private func cgWindowFrame(_ window: [String: Any]) -> CGRect? {
        (window[kCGWindowBounds as String] as? [String: Any])
            .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }?
            .standardized
    }

    private func workflowCGFrameDescription(_ frame: CGRect?) -> String {
        guard let frame else { return "nil" }
        return "\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.width))x\(Int(frame.height))"
    }

    private func cgWindowNumber(_ value: Any?) -> CGWindowID? {
        if let windowNumber = value as? CGWindowID {
            return windowNumber
        }
        if let number = value as? NSNumber {
            return CGWindowID(number.uint32Value)
        }
        return nil
    }

    private func windowTitle(for attribute: CFString, in appElement: AXUIElement) -> String? {
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            attribute,
            &windowValue
        ) == .success,
            let windowValue
        else {
            return nil
        }

        let window = windowValue as! AXUIElement
        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXTitleAttribute as CFString,
            &titleValue
        ) == .success else {
            return nil
        }

        return (titleValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func axWindows(in appElement: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func axTreeContainsExpectedTitle(
        _ element: AXUIElement,
        expectedTitles: Set<String>,
        remainingDepth: Int,
        remainingNodeBudget: inout Int
    ) -> Bool {
        guard remainingDepth >= 0, remainingNodeBudget > 0 else {
            return false
        }
        remainingNodeBudget -= 1
        if axElementMatchesExpectedTitle(element, expectedTitles: expectedTitles) {
            return true
        }
        return axChildren(in: element).contains {
            axTreeContainsExpectedTitle(
                $0,
                expectedTitles: expectedTitles,
                remainingDepth: remainingDepth - 1,
                remainingNodeBudget: &remainingNodeBudget
            )
        }
    }

    private func axElementMatchesExpectedTitle(
        _ element: AXUIElement,
        expectedTitles: Set<String>
    ) -> Bool {
        [
            kAXTitleAttribute as CFString,
            kAXValueAttribute as CFString,
            kAXDescriptionAttribute as CFString
        ].contains {
            guard let value = axStringAttribute($0, in: element) else {
                return false
            }
            return expectedTitles.contains(value)
        }
    }

    private func axChildren(in element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func axStringAttribute(_ attribute: CFString, in element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
