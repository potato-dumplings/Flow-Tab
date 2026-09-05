#if FLOWTAB_TESTING
import Foundation

enum ControlTabPressureSpanScope: String, Sendable {
    case timelineExclusive = "timeline_exclusive"
    case componentInclusive = "component_inclusive"
}

struct ControlTabPressureSpan: Equatable, Sendable {
    let phase: ControlTabPressurePhase
    let sequence: UInt64
    let name: String
    let parent: String?
    let startedAtNanoseconds: UInt64
    let completedAtNanoseconds: UInt64
    let duration: ControlTabPressureDuration
    let scope: ControlTabPressureSpanScope
    let outcome: String
    let workUnits: Int
}

struct ControlTabPressureSpanEvidence: Sendable {
    let spans: [ControlTabPressureSpan]
    let requiredComponentsPresent: Bool
    let timelineReconciled: Bool
    let componentTimingValid: Bool

    var isValid: Bool {
        requiredComponentsPresent
            && timelineReconciled
            && componentTimingValid
    }
}

enum ControlTabPressureSpanRequirements {
    static func components(
        for phase: ControlTabPressurePhase
    ) -> Set<SwitcherInteractionComponent> {
        switch phase {
        case .open:
            return [
                .inputRouting, .projectionRead,
                .axCGSpaceReconciliation, .sessionBuild,
                .onScreenCGRead, .allCGRead, .axRead,
                .mappingSpaceFilter,
                .sessionPublish, .previewPlanning,
                .previewCapture,
                .previewShareableContentLookup,
                .previewScreenshotManagerCapture,
                .previewCoreGraphicsCapture,
                .previewTransparentTrim, .previewImageScale,
                .previewTitleBarInference,
                .previewImageProcessCache,
                .appKitPanelPresentation, .swiftUILayoutFirstDraw,
                .visibilityReadback
            ]
        case .forward, .reverse:
            return [
                .inputRouting, .selectionMutation, .sessionPublish,
                .panelGeometryUpdate, .previewCapture,
                .previewImageProcessCache, .swiftUIDiffLayoutDraw,
                .selectionReadback
            ]
        case .commit:
            return [
                .targetResolution, .activationDispatch,
                .exactWindowActivation, .focusReadback,
                .panelTeardown, .observerRemoval,
                .delayedTaskCancellation, .cacheSessionCleanup
            ]
        case .cancel:
            return [
                .panelTeardown, .observerRemoval,
                .delayedTaskCancellation, .cacheSessionCleanup,
                .reusableShellPrepare, .closedStateReadback
            ]
        case .cooldown:
            return []
        }
    }
}
#endif
