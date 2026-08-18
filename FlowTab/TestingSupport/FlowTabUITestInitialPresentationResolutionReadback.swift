#if FLOWTAB_TESTING
import Foundation

struct FlowTabUITestInitialPresentationResolutionReadback:
    Codable,
    Equatable
{
    struct Generation: Codable, Equatable {
        let appLifecycle: UInt64
        let cg: UInt64
        let space: UInt64
        let axDirty: UInt64
        let projection: UInt64

        init(
            _ generation: RuntimeReadModelGeneration
        ) {
            appLifecycle = generation.appLifecycle
            cg = generation.cg
            space = generation.space
            axDirty = generation.axDirty
            projection = generation.projection
        }
    }

    static let currentSchemaVersion = 3

    let schemaVersion: Int
    let observationGeneration: UInt64
    let source: String
    let resolution: String
    let baselineMode: String
    let baselineSourceGeneration: Generation?
    let candidateMode: String
    let candidateProjectionIsPresent: Bool
    let candidateProjectionIsComplete: Bool
    let candidateSourceGeneration: Generation?
    let candidateProcessIdentifier: Int32?
    let candidateItemIDs: [String]
    let didPresent: Bool
    let sessionItemIDs: [String]
    let selectedAppID: String
    let inputReadinessObservationGeneration: UInt64
    let inputReadinessSource: String
    let inputReadinessResolved: Bool
    let inputReadinessBaselineSourceGeneration: Generation?
    let inputReadinessSourceGeneration: Generation?
    let inputReadinessPresentationGeneration: Int
    let inputReadinessPanelIsVisibleToUser: Bool
    let inputReadinessPanelIsKey: Bool
    let inputReadinessApplicationIsActive: Bool
    let inputReadinessSessionItemIDs: [String]
    let inputReadinessSelectedAppID: String?
    let inputReadinessPanelPresentationDiagnosticProbePending: Bool
    let inputReadinessInitialVisibilityPending: Bool
    let inputReadinessPanelVisibilityRecoveryPending: Bool
    let inputReadinessActiveSpaceTransitionPending: Bool
    let inputReadinessApplicationActivationSuppressed: Bool
    let inputReadinessTerminateInterruptionProtectionPending: Bool
    let attemptSearchIsActiveOrPending: Bool
    let postPresentationMode: String
    let postPresentationSourceGeneration: Generation?
    let postPresentationProcessIdentifier: Int32?
    let postPresentationItemIDs: [String]
    let panelIsPresented: Bool
    let sessionMode: String?
    let searchFeatureEnabled: Bool
    let searchIsActive: Bool
    let searchActivationIsPending: Bool

    @MainActor
    init?(
        evidence:
            FlowTabUITestInitialPresentationEvidence,
        inputReadinessEvidence:
            FlowTabUITestInitialPresentationInputReadinessEvidence,
        panelController: SwitcherPanelController
    ) {
        guard
            let resolution = evidence.resolution,
            let attempt = evidence.attempt,
            let postPresentationReadback =
                evidence.postPresentationReadback
        else {
            return nil
        }
        let model = panelController.modelForTesting
        guard let session = model.session else {
            return nil
        }
        schemaVersion = Self.currentSchemaVersion
        observationGeneration =
            evidence.observationGeneration
        source = evidence.source.rawValue
        self.resolution = resolution.rawValue
        baselineMode = evidence.baseline.mode.rawValue
        baselineSourceGeneration =
            evidence.baseline.sourceGeneration.map(Generation.init)
        candidateMode = evidence.candidate.mode.rawValue
        candidateProjectionIsPresent =
            evidence.candidate.projectionIsPresent
        candidateProjectionIsComplete =
            evidence.candidate.projectionIsComplete
        candidateSourceGeneration =
            evidence.candidate.sourceGeneration.map(Generation.init)
        candidateProcessIdentifier =
            evidence.candidate.processIdentifier
        candidateItemIDs = evidence.candidate.itemIDs
        didPresent = attempt.didPresent
        sessionItemIDs = attempt.sessionItemIDs
        selectedAppID = session.selectedApp.id
        inputReadinessObservationGeneration =
            inputReadinessEvidence.observationGeneration
        inputReadinessSource =
            inputReadinessEvidence.source.rawValue
        inputReadinessResolved =
            inputReadinessEvidence.isSatisfied
        inputReadinessBaselineSourceGeneration =
            inputReadinessEvidence.baseline
                .sourceGeneration.map(Generation.init)
        inputReadinessSourceGeneration =
            inputReadinessEvidence.snapshot
                .projection.sourceGeneration.map(Generation.init)
        inputReadinessPresentationGeneration =
            inputReadinessEvidence.snapshot
                .presentationGeneration
        inputReadinessPanelIsVisibleToUser =
            inputReadinessEvidence.snapshot
                .panelIsVisibleToUser
        inputReadinessPanelIsKey =
            inputReadinessEvidence.snapshot.panelIsKey
        inputReadinessApplicationIsActive =
            inputReadinessEvidence.snapshot
                .applicationIsActive
        inputReadinessSessionItemIDs =
            inputReadinessEvidence.snapshot.sessionItemIDs
        inputReadinessSelectedAppID =
            inputReadinessEvidence.snapshot.selectedAppID
        inputReadinessPanelPresentationDiagnosticProbePending =
            inputReadinessEvidence.snapshot
                .panelPresentationDiagnosticProbePending
        inputReadinessInitialVisibilityPending =
            inputReadinessEvidence.snapshot
                .initialVisibilityPending
        inputReadinessPanelVisibilityRecoveryPending =
            inputReadinessEvidence.snapshot
                .panelVisibilityRecoveryPending
        inputReadinessActiveSpaceTransitionPending =
            inputReadinessEvidence.snapshot
                .activeSpaceTransitionPending
        inputReadinessApplicationActivationSuppressed =
            inputReadinessEvidence.snapshot
                .applicationActivationSuppressed
        inputReadinessTerminateInterruptionProtectionPending =
            inputReadinessEvidence.snapshot
                .terminateInterruptionProtectionPending
        attemptSearchIsActiveOrPending =
            attempt.searchIsActiveOrPending
        postPresentationMode =
            postPresentationReadback.mode.rawValue
        postPresentationSourceGeneration =
            postPresentationReadback.sourceGeneration.map(
                Generation.init
            )
        postPresentationProcessIdentifier =
            postPresentationReadback.processIdentifier
        postPresentationItemIDs =
            postPresentationReadback.itemIDs
        panelIsPresented =
            inputReadinessEvidence.snapshot.panelIsPresented
        sessionMode = session.mode.debugName
        searchFeatureEnabled =
            panelController.searchFeatureEnabled
        searchIsActive = model.isSearchActive
        searchActivationIsPending =
            model.pendingSearchActivationAfterFreshnessBarrier
    }
}

enum FlowTabUITestInitialPresentationResolutionTransport {
    static func post(
        _ readback:
            FlowTabUITestInitialPresentationResolutionReadback,
        route:
            FlowTabUITestInitialPresentationResolutionRoute,
        center:
            DistributedNotificationCenter = .default()
    ) {
        do {
            try writeReadback(
                readback,
                to: route.readbackURL
            )
        } catch {
            RuntimeLog.error(
                "UITest",
                "initial presentation resolution readback "
                    + "write failed path=\(route.readbackURL.path) "
                    + "error=\(error)"
            )
            return
        }
        center.postNotificationName(
            route.notificationName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func writeReadback(
        _ readback:
            FlowTabUITestInitialPresentationResolutionReadback,
        to readbackURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(readback)
        try data.write(
            to: readbackURL,
            options: .atomic
        )
    }
}
#endif
