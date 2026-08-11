import XCTest
@testable import FlowTab
import FlowTabCore

@MainActor
final class ManualInitialPresentationScheduler:
    FlowTabUITestInitialPresentationScheduling
{
    final class Token:
        FlowTabUITestInitialPresentationCancellable
    {
        let interval: TimeInterval
        let action: @MainActor @Sendable () -> Void
        private(set) var isCancelled = false

        init(
            interval: TimeInterval,
            action:
                @escaping @MainActor @Sendable () -> Void
        ) {
            self.interval = interval
            self.action = action
        }

        func cancel() {
            isCancelled = true
        }
    }

    private(set) var tokens: [Token] = []

    func schedule(
        after interval: TimeInterval,
        _ action:
            @escaping @MainActor @Sendable () -> Void
    ) -> any FlowTabUITestInitialPresentationCancellable {
        let token = Token(
            interval: interval,
            action: action
        )
        tokens.append(token)
        return token
    }

    func fire(
        _ token: Token,
        includingCancelled: Bool = false
    ) {
        guard includingCancelled
                || !token.isCancelled
        else {
            return
        }
        token.action()
    }
}

extension FlowTabTests {
    @MainActor
    func makeInitialPresentationOwner(
        notificationCenter: NotificationCenter =
            NotificationCenter(),
        notificationObject: AnyObject = NSObject(),
        scheduler: ManualInitialPresentationScheduler,
        readback:
            @escaping @MainActor () ->
                FlowTabUITestInitialPresentationSnapshot
    ) -> FlowTabUITestInitialPresentationObservationOwner {
        FlowTabUITestInitialPresentationObservationOwner(
            notificationRoutes: [
                .init(
                    name:
                        .runtimeAppSwitcherProjectionDidUpdate,
                    source:
                        .appSwitcherProjectionDidUpdate
                )
            ],
            notificationObject: notificationObject,
            notificationCenter: notificationCenter,
            scheduler: scheduler,
            readback: readback
        )
    }

    func initialPresentationSnapshot(
        generation: UInt64,
        isComplete: Bool = true,
        itemIDs: [String]
    ) -> FlowTabUITestInitialPresentationSnapshot {
        FlowTabUITestInitialPresentationSnapshot(
            mode: .global,
            projectionIsPresent: true,
            projectionIsComplete: isComplete,
            sourceGeneration:
                RuntimeReadModelGeneration(
                    projection: generation
                ),
            processIdentifier: nil,
            itemIDs: itemIDs,
            dirtyAppIDs:
                isComplete ? [] : ["app-a"],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes:
                isComplete ? [] : ["coldStart"]
        )
    }

    @MainActor
    func initialPresentationInputReadinessSnapshot(
        generation: UInt64,
        projectionIsComplete: Bool = true,
        presentationGeneration: Int = 3,
        itemIDs: [String] = ["app-a", "app-b"],
        selectedAppID: String? = "app-a",
        panelIsPresented: Bool = true,
        panelIsVisibleToUser: Bool = true,
        panelPresentationDiagnosticProbePending: Bool = false,
        initialVisibilityPending: Bool = false,
        panelVisibilityRecoveryPending: Bool = false,
        activeSpaceTransitionPending: Bool = false,
        applicationActivationSuppressed: Bool = false,
        terminateInterruptionProtectionPending: Bool = false
    ) -> FlowTabUITestInitialPresentationInputReadinessSnapshot {
        FlowTabUITestInitialPresentationInputReadinessSnapshot(
            projection: initialPresentationSnapshot(
                generation: generation,
                isComplete: projectionIsComplete,
                itemIDs: itemIDs
            ),
            presentationGeneration: presentationGeneration,
            panelIsPresented: panelIsPresented,
            panelIsVisibleToUser: panelIsVisibleToUser,
            panelIsKey: true,
            applicationIsActive: true,
            sessionItemIDs: itemIDs,
            selectedAppID: selectedAppID,
            sessionMode: "appCycle",
            panelPresentationDiagnosticProbePending:
                panelPresentationDiagnosticProbePending,
            initialVisibilityPending: initialVisibilityPending,
            panelVisibilityRecoveryPending:
                panelVisibilityRecoveryPending,
            activeSpaceTransitionPending:
                activeSpaceTransitionPending,
            applicationActivationSuppressed:
                applicationActivationSuppressed,
            terminateInterruptionProtectionPending:
                terminateInterruptionProtectionPending
        )
    }

    @MainActor
    func makeInitialPresentationInputReadinessOwner(
        notificationCenter: NotificationCenter =
            NotificationCenter(),
        notificationObject: AnyObject = NSObject(),
        scheduler: ManualInitialPresentationScheduler,
        readback:
            @escaping @MainActor () ->
                FlowTabUITestInitialPresentationInputReadinessSnapshot
    ) -> FlowTabUITestInitialPresentationInputReadinessObservationOwner {
        FlowTabUITestInitialPresentationInputReadinessObservationOwner(
            notificationNames: [
                .runtimeAppSwitcherProjectionDidUpdate
            ],
            notificationObject: notificationObject,
            notificationCenter: notificationCenter,
            scheduler: scheduler,
            readback: readback
        )
    }
}

extension FlowTabPriorityCoverageTests {
    func incompleteInitialPresentationProjection(
        app: AppSwitchCandidate
    ) -> RuntimeAppSwitcherProjection {
        RuntimeAppSwitcherProjection(
            apps: [app],
            contextsByID: [:],
            freshness: RuntimeProjectionFreshness(
                generatedAt: 1,
                sourceGeneration:
                    RuntimeReadModelGeneration(projection: 1),
                dirtyAppIDs: [app.id],
                dirtyPIDs: [],
                dirtyCGWindowIDs: [],
                pendingRepairScopes: ["coldStart"],
                isCompleteForScope: false
            )
        )
    }
}
