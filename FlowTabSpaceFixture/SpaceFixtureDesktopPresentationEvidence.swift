import CoreGraphics

struct SpaceFixtureDesktopPresentationSnapshot: Equatable {
    let windowPlanIndex: Int
    let windowNumber: CGWindowID
    let applicationIsActive: Bool
    let isKeyWindow: Bool
    let isMainWindow: Bool
    let isVisible: Bool
    let isMiniaturized: Bool
    let isOnActiveSpace: Bool
    let isOcclusionVisible: Bool
    let isCGWindowOnScreen: Bool

    var isPresented: Bool {
        applicationIsActive
            && isKeyWindow
            && isMainWindow
            && isVisible
            && !isMiniaturized
            && isOnActiveSpace
            && isOcclusionVisible
            && isCGWindowOnScreen
    }

    var unmetConditions: [String] {
        var conditions: [String] = []
        if !applicationIsActive {
            conditions.append("applicationActive")
        }
        if !isKeyWindow {
            conditions.append("windowKey")
        }
        if !isMainWindow {
            conditions.append("windowMain")
        }
        if !isVisible {
            conditions.append("windowVisible")
        }
        if isMiniaturized {
            conditions.append("windowNotMiniaturized")
        }
        if !isOnActiveSpace {
            conditions.append("windowOnActiveSpace")
        }
        if !isOcclusionVisible {
            conditions.append("windowOcclusionVisible")
        }
        if !isCGWindowOnScreen {
            conditions.append("exactCGWindowOnScreen")
        }
        return conditions
    }

    func unmetConditions(
        expectedWindowPlanIndex: Int
    ) -> [String] {
        var conditions = unmetConditions
        if windowPlanIndex != expectedWindowPlanIndex {
            conditions.insert("windowPlanIdentity", at: 0)
        }
        return conditions
    }

    var logFields: String {
        "windowPlanIndex=\(windowPlanIndex) "
            + "windowNumber=\(windowNumber) "
            + "applicationActive=\(applicationIsActive) "
            + "key=\(isKeyWindow) "
            + "main=\(isMainWindow) "
            + "visible=\(isVisible) "
            + "miniaturized=\(isMiniaturized) "
            + "onActiveSpace=\(isOnActiveSpace) "
            + "occlusionVisible=\(isOcclusionVisible) "
            + "cgOnScreen=\(isCGWindowOnScreen)"
    }
}

enum SpaceFixtureDesktopPresentationEvidenceSource:
    String,
    Equatable
{
    case initialReadback
    case triggerReturnReadback
    case retryReadback
    case retryTriggerReturnReadback
    case windowDidBecomeKey
    case windowDidBecomeMain
    case windowDidChangeOcclusion
    case windowDidDeminiaturize
    case applicationDidBecomeActive
    case activeSpaceDidChange
    case watchdogReadback
}

struct SpaceFixtureDesktopPresentationEvidence: Equatable {
    let source: SpaceFixtureDesktopPresentationEvidenceSource
    let observationGeneration: Int
    let snapshot: SpaceFixtureDesktopPresentationSnapshot
}

struct SpaceFixtureDesktopRefocusWatchdogFailure: Equatable {
    let observationGeneration: Int
    let expectedWindowPlanIndex: Int
    let watchdogMilliseconds: Int
    let lastEvidence: SpaceFixtureDesktopPresentationEvidence
    let finalEvidence: SpaceFixtureDesktopPresentationEvidence

    var logFields: String {
        let unmet = finalEvidence.snapshot.unmetConditions(
            expectedWindowPlanIndex: expectedWindowPlanIndex
        )
            .joined(separator: ",")
        return "condition=desktopAnchorPresented "
            + "watchdogMs=\(watchdogMilliseconds) "
            + "generation=\(observationGeneration) "
            + "unmet=[\(unmet)] "
            + "lastSource=\(lastEvidence.source.rawValue) "
            + "last{\(lastEvidence.snapshot.logFields)} "
            + "final{\(finalEvidence.snapshot.logFields)}"
    }
}
