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
        let action: @MainActor @Sendable () -> Void
        private(set) var isCancelled = false

        init(
            action:
                @escaping @MainActor @Sendable () -> Void
        ) {
            self.action = action
        }

        func cancel() {
            isCancelled = true
        }
    }

    private(set) var tokens: [Token] = []

    func schedule(
        after _: TimeInterval,
        _ action:
            @escaping @MainActor @Sendable () -> Void
    ) -> any FlowTabUITestInitialPresentationCancellable {
        let token = Token(action: action)
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
