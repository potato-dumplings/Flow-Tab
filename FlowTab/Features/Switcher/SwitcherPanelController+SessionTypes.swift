import AppKit
import FlowTabCore

extension SwitcherPanelController {
    struct PendingFocusedWindowSessionPresentation {
        let request: PendingFocusedAppWindowSession
        let initialKeyInput: KeyInput?
        let showStartMilliseconds: Double
        let observationGeneration: Int
    }

    enum HotkeySessionKind {
        case globalAppSwitcher
        case inAppWindowSwitcher
    }

    enum PanelVisibilityRecoveryMode: Equatable {
        case softReorder
        case hardReorder

        var debugName: String {
            switch self {
            case .softReorder:
                "softReorder"
            case .hardReorder:
                "hardReorder"
            }
        }
    }

    enum PanelVisibilityRecoveryState: Equatable {
        case idle
        case presenting(trigger: String, generation: Int)
        case visibleConfirmed(trigger: String, generation: Int, reason: String)
        case suspectedHidden(trigger: String, generation: Int)
        case recovering(
            trigger: String,
            generation: Int,
            attempt: Int,
            totalAttempts: Int,
            mode: PanelVisibilityRecoveryMode
        )
        case failed(trigger: String, generation: Int, reason: String)
    }

    enum ModifierReleaseCancellationReason: String, Equatable {
        case suppressedForTesting
        case explicitCancel
        case panelHidden
        case searchInteraction
        case sessionChanged
    }

    enum ModifierReleaseState: Equatable {
        case idle
        case pressed(generation: Int)
        case releaseObserved(trigger: String, generation: Int)
        case confirming(trigger: String, generation: Int, releasedSamples: Int)
        case confirmed(trigger: String, generation: Int)
        case replaySuppression(trigger: String, generation: Int, releasedSamples: Int)
        case replaySuppressionEnded(trigger: String, generation: Int)
        case canceled(reason: ModifierReleaseCancellationReason, generation: Int)
    }

}
