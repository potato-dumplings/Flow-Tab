import AppKit
import ApplicationServices
import Foundation
import XCTest

private enum FlowTabUITestCGWindowDefaults {
    static let minimumValidWindowWidth: CGFloat = 80
    static let minimumValidWindowHeight: CGFloat = 60
    static let minimumValidWindowArea: CGFloat = 20_000
    static let visibleAlphaThreshold = 0.001
    static let standardBufferedStoreType = 1
}

struct WorkflowCGWindowObservation: Equatable {
    let number: CGWindowID
    let title: String?

    func matches(number expectedNumber: CGWindowID?, title expectedTitle: String?) -> Bool {
        if let expectedNumber, number == expectedNumber {
            return true
        }
        if let expectedTitle, title == expectedTitle {
            return true
        }
        return false
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

    private func frontmostCGWindowTitle(forPID pid: pid_t) -> String? {
        frontmostCGWindow(forPID: pid)?.title
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
                title: title?.isEmpty == false ? title : nil
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
