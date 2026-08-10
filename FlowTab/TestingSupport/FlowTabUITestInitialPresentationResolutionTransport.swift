#if FLOWTAB_TESTING
import Foundation

struct FlowTabUITestInitialPresentationResolutionRoute:
    Equatable
{
    let notificationName: Notification.Name
    let readbackURL: URL
}

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

    static let currentSchemaVersion = 1

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
        panelIsPresented = panelController.isPanelPresented
        sessionMode = model.session?.mode.debugName
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
