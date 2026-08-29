#if FLOWTAB_TESTING
import Foundation

enum AppPanelPressureEvidencePhase:
    String,
    Equatable,
    Sendable
{
    case opened
    case highlighted
    case closed
}

struct AppPanelPressureEvidence:
    Equatable,
    Sendable
{
    let sequence: UInt64
    let phase: AppPanelPressureEvidencePhase
    let elapsedMilliseconds: Double
    let panelPresented: Bool
    let userVisible: Bool
    let selectedAppID: String?
    let appCount: Int
    let selectedWindowCount: Int
    var panelWidth: Double = 0
    var visibleFrameWidth: Double = 0
    var visibleHomeWindowCount: Int = 0
    var completionRequirementSatisfied: Bool? = nil
    let stageMetrics: [String: Double]

    var isSatisfied: Bool {
        guard completionRequirementSatisfied != false else { return false }
        switch phase {
        case .opened, .highlighted:
            return panelPresented
                && userVisible
                && selectedAppID != nil
                && appCount > 1
                && panelWidth >= 440
                && visibleFrameWidth > 0
                && panelWidth
                    <= max(440, visibleFrameWidth - 80) + 0.5
                && visibleHomeWindowCount == 0
        case .closed:
            return !panelPresented
                && !userVisible
                && selectedAppID == nil
                && visibleHomeWindowCount == 0
        }
    }
}

enum AppPanelPressureCompletionRequirement:
    Equatable,
    Sendable
{
    case phaseDefault
    case windowLayer
    case searchReady
    case committedSearchResults(query: String)
}

struct AppPanelPressureMeasurementToken:
    Equatable,
    Sendable
{
    let sequence: UInt64
    let phase: AppPanelPressureEvidencePhase
    let startedAtNanoseconds: UInt64
    let triggerReceivedAtNanoseconds: UInt64?
    let mainActorEnteredAtNanoseconds: UInt64?
    let completionRequirement:
        AppPanelPressureCompletionRequirement
}
#endif
