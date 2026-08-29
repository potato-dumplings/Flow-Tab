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
    var completionRequirementSatisfied: Bool? = nil
    let stageMetrics: [String: Double]

    var isSatisfied: Bool {
        if let completionRequirementSatisfied {
            return completionRequirementSatisfied
        }
        switch phase {
        case .opened, .highlighted:
            return panelPresented
                && userVisible
                && selectedAppID != nil
                && appCount > 1
        case .closed:
            return !panelPresented
                && !userVisible
                && selectedAppID == nil
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
