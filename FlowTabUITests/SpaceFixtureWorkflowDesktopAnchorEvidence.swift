import CoreGraphics
import Darwin
import Foundation

struct SpaceFixtureWorkflowDesktopAnchorWindowExpectation:
    Equatable
{
    let planIndex: Int
    let title: String
    let accessibilityIdentifier: String

    init(
        planIndex: Int,
        title: String,
        accessibilityIdentifier: String
    ) {
        precondition(planIndex > 0)
        precondition(!title.isEmpty)
        precondition(!accessibilityIdentifier.isEmpty)
        self.planIndex = planIndex
        self.title = title
        self.accessibilityIdentifier =
            accessibilityIdentifier
    }
}

struct SpaceFixtureWorkflowDesktopAnchorExpectation:
    Equatable
{
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let windows:
        [SpaceFixtureWorkflowDesktopAnchorWindowExpectation]

    init(
        bundleIdentifier: String,
        processIdentifier: pid_t,
        windows:
            [SpaceFixtureWorkflowDesktopAnchorWindowExpectation]
    ) {
        precondition(!bundleIdentifier.isEmpty)
        precondition(processIdentifier > 0)
        precondition(!windows.isEmpty)
        precondition(
            Set(windows.map(\.planIndex)).count
                == windows.count
        )
        precondition(
            Set(windows.map(\.accessibilityIdentifier))
                .count == windows.count
        )
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.windows = windows
    }
}

struct SpaceFixtureWorkflowDesktopAnchorSnapshot:
    Equatable
{
    let runningBundleIdentifier: String?
    let runningProcessIdentifier: pid_t?
    let applicationIsActive: Bool
    let applicationIsTerminated: Bool
    let xcuiRunningForeground: Bool
    let frontmostBundleIdentifier: String?
    let frontmostProcessIdentifier: pid_t?
    let identifiedXCUIWindowFrame: CGRect?
    let identifiedWindowPlanIndex: Int?
    let identifiedWindowTitle: String?
    let identifiedAccessibilityIdentifier: String?
    let observedXCUIWindowFrames: [CGRect]
    let topmostCGWindowNumber: CGWindowID?
    let topmostCGWindowTitle: String?
    let topmostCGWindowFrame: CGRect?
    let topmostCGWindowIsFullscreenSpaceSized: Bool

    func isResolved(
        expectation:
            SpaceFixtureWorkflowDesktopAnchorExpectation
    ) -> Bool {
        unmetConditions(expectation: expectation).isEmpty
    }

    func unmetConditions(
        expectation:
            SpaceFixtureWorkflowDesktopAnchorExpectation
    ) -> [String] {
        var conditions: [String] = []
        if runningBundleIdentifier
                != expectation.bundleIdentifier
            || runningProcessIdentifier
                != expectation.processIdentifier
            || applicationIsTerminated
        {
            conditions.append("runningProcessIdentity")
        }
        if !applicationIsActive {
            conditions.append("applicationActive")
        }
        if !xcuiRunningForeground {
            conditions.append("xcuiRunningForeground")
        }
        if frontmostBundleIdentifier
                != expectation.bundleIdentifier
            || frontmostProcessIdentifier
                != expectation.processIdentifier
        {
            conditions.append("frontmostProcessIdentity")
        }
        if identifiedXCUIWindowFrame == nil {
            conditions.append("exactXCUIWindowIdentity")
        }
        if !matchesExpectedWindow(
            expectation.windows
        ) {
            conditions.append("windowPlanIdentity")
        }
        if !Self.exactWindowIdentityMatches(
            cgWindowNumber: topmostCGWindowNumber,
            xcuiWindowFrame: identifiedXCUIWindowFrame,
            cgWindowFrame: topmostCGWindowFrame
        ) {
            conditions.append("exactCGWindowIdentity")
        }
        if topmostCGWindowIsFullscreenSpaceSized {
            conditions.append("desktopSpace")
        }
        return conditions
    }

    var logFields: String {
        "runningBundle=\(value(runningBundleIdentifier)) "
            + "runningPID=\(value(runningProcessIdentifier)) "
            + "active=\(applicationIsActive) "
            + "terminated=\(applicationIsTerminated) "
            + "xcuiForeground=\(xcuiRunningForeground) "
            + "frontmostBundle=\(value(frontmostBundleIdentifier)) "
            + "frontmostPID=\(value(frontmostProcessIdentifier)) "
            + "identifiedXCUIWindowFrame="
            + "\(frame(identifiedXCUIWindowFrame)) "
            + "identifiedPlan=\(value(identifiedWindowPlanIndex)) "
            + "identifiedTitle=\(value(identifiedWindowTitle)) "
            + "identifiedXCUIIdentifier="
            + "\(value(identifiedAccessibilityIdentifier)) "
            + "observedXCUIWindowFrames="
            + "\(observedXCUIWindowFrames.map(frame)) "
            + "topmostCGWindow=\(value(topmostCGWindowNumber)) "
            + "topmostCGTitle=\(value(topmostCGWindowTitle)) "
            + "topmostCGFrame=\(frame(topmostCGWindowFrame)) "
            + "cgFullscreenSized="
            + "\(topmostCGWindowIsFullscreenSpaceSized)"
    }

    static func windowFramesMatch(
        _ lhs: CGRect?,
        _ rhs: CGRect?,
        tolerance: CGFloat = 2
    ) -> Bool {
        guard let lhs,
              let rhs,
              !lhs.isNull,
              !rhs.isNull,
              lhs.width > 0,
              lhs.height > 0,
              rhs.width > 0,
              rhs.height > 0
        else {
            return false
        }
        let left = lhs.standardized
        let right = rhs.standardized
        return abs(left.minX - right.minX) <= tolerance
            && abs(left.minY - right.minY) <= tolerance
            && abs(left.width - right.width) <= tolerance
            && abs(left.height - right.height) <= tolerance
    }

    static func exactWindowIdentityMatches(
        cgWindowNumber: CGWindowID?,
        xcuiWindowFrame: CGRect?,
        cgWindowFrame: CGRect?
    ) -> Bool {
        guard cgWindowNumber != nil else { return false }
        return windowFramesMatch(
            xcuiWindowFrame,
            cgWindowFrame
        )
    }

    private func matchesExpectedWindow(
        _ expectedWindows:
            [SpaceFixtureWorkflowDesktopAnchorWindowExpectation]
    ) -> Bool {
        expectedWindows.contains {
            $0.planIndex == identifiedWindowPlanIndex
                && $0.title == identifiedWindowTitle
                && $0.accessibilityIdentifier
                    == identifiedAccessibilityIdentifier
        }
    }

    private func value<T>(
        _ value: T?
    ) -> String {
        value.map(String.init(describing:)) ?? "nil"
    }

    private func frame(_ value: CGRect?) -> String {
        guard let value else { return "nil" }
        return "\(Int(value.minX)),\(Int(value.minY)),"
            + "\(Int(value.width))x\(Int(value.height))"
    }
}

enum SpaceFixtureWorkflowDesktopAnchorEvidenceSource:
    String,
    Equatable
{
    case initialReadback
    case applicationDidActivate
    case activeSpaceDidChange
    case triggerReturnReadback
    case conditionPollReadback
    case watchdogReadback
}

struct SpaceFixtureWorkflowDesktopAnchorEvidence:
    Equatable
{
    let observationGeneration: Int
    let source:
        SpaceFixtureWorkflowDesktopAnchorEvidenceSource
    let snapshot:
        SpaceFixtureWorkflowDesktopAnchorSnapshot
}

struct SpaceFixtureWorkflowDesktopAnchorWatchdogFailure:
    Equatable
{
    let observationGeneration: Int
    let watchdogSeconds: TimeInterval
    let expectation:
        SpaceFixtureWorkflowDesktopAnchorExpectation
    let lastEvidence:
        SpaceFixtureWorkflowDesktopAnchorEvidence
    let finalEvidence:
        SpaceFixtureWorkflowDesktopAnchorEvidence

    var logFields: String {
        let unmet = finalEvidence.snapshot
            .unmetConditions(expectation: expectation)
            .joined(separator: ",")
        let expectedPlans = expectation.windows
            .map(\.planIndex)
            .sorted()
            .map(String.init)
            .joined(separator: ",")
        return "condition=workflowDesktopAnchorPresented "
            + "watchdogSeconds=\(watchdogSeconds) "
            + "generation=\(observationGeneration) "
            + "expectedBundle=\(expectation.bundleIdentifier) "
            + "expectedPID=\(expectation.processIdentifier) "
            + "expectedPlans=[\(expectedPlans)] "
            + "unmet=[\(unmet)] "
            + "lastSource=\(lastEvidence.source.rawValue) "
            + "last{\(lastEvidence.snapshot.logFields)} "
            + "final{\(finalEvidence.snapshot.logFields)}"
    }
}
