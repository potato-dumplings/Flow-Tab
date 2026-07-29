import Foundation

@MainActor
final class ManualSpaceFixtureProjectionAcknowledgementObservation {
    struct Observation {
        let notificationName: Notification.Name
        let token: ManualSpaceFixtureCancellable
        let handler:
            @MainActor (
                SpaceFixtureProjectionAcknowledgement
            ) -> Void
    }

    private(set) var observations: [Observation] = []
    var onInstall:
        (@MainActor (
            @escaping @MainActor (
                SpaceFixtureProjectionAcknowledgement
            ) -> Void
        ) -> Void)?

    func install(
        notificationName: Notification.Name,
        handler:
            @escaping @MainActor (
                SpaceFixtureProjectionAcknowledgement
            ) -> Void
    ) -> any SpaceFixtureCancellable {
        let token = ManualSpaceFixtureCancellable()
        observations.append(
            Observation(
                notificationName: notificationName,
                token: token,
                handler: handler
            )
        )
        onInstall?(handler)
        return token
    }

    func emit(
        _ acknowledgement:
            SpaceFixtureProjectionAcknowledgement,
        at index: Int = 0,
        includingCancelled: Bool = false
    ) {
        let observation = observations[index]
        guard includingCancelled
                || !observation.token.isCancelled
        else {
            return
        }
        observation.handler(acknowledgement)
    }
}

@MainActor
final class SpaceFixtureApplicationAXExposureProbe {
    var exposure: SpaceFixtureApplicationAXExposure
    private(set) var readCount = 0

    init(
        childWindowCount: Int,
        windowsAttributeCount: Int
    ) {
        exposure = SpaceFixtureApplicationAXExposure(
            childWindowCount: childWindowCount,
            windowsAttributeCount: windowsAttributeCount
        )
    }

    func read() -> SpaceFixtureApplicationAXExposure {
        readCount += 1
        return exposure
    }

    func set(windowCount: Int) {
        exposure = SpaceFixtureApplicationAXExposure(
            childWindowCount: windowCount,
            windowsAttributeCount: windowCount
        )
    }
}

@MainActor
final class SpaceFixtureApplicationAXSuppressionCompletionProbe {
    private(set) var completions:
        [SpaceFixtureApplicationAXSuppressionCompletion] = []

    func record(
        _ completion:
            SpaceFixtureApplicationAXSuppressionCompletion
    ) {
        completions.append(completion)
    }
}

enum SpaceFixtureApplicationAXSuppressionTestSupport {
    static let identity = SpaceFixtureApplicationIdentity(
        bundleIdentifier: "com.example.fixture",
        processIdentifier: 4_321
    )

    static let route =
        SpaceFixtureApplicationAXSuppressionRoute(
            projectionAcknowledgementNotificationName:
                Notification.Name(
                    "test.fixture.projection.ack"
                ),
            suppressionCompletionNotificationName:
                Notification.Name(
                    "test.fixture.ax.suppressed"
                )
        )

    static func acknowledgement(
        generation: UInt64 = 1,
        bundleIdentifier: String =
            identity.bundleIdentifier,
        processIdentifier: pid_t =
            identity.processIdentifier,
        windowCount: Int = 2,
        sourceGeneration: String = "projection=1"
    ) -> SpaceFixtureProjectionAcknowledgement {
        SpaceFixtureProjectionAcknowledgement(
            acknowledgementGeneration: generation,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            windowCount: windowCount,
            sourceGeneration: sourceGeneration
        )
    }

    @MainActor
    static func makeOwner(
        scheduler: ManualSpaceFixtureScheduler,
        observation:
            ManualSpaceFixtureProjectionAcknowledgementObservation,
        exposure: SpaceFixtureApplicationAXExposureProbe,
        completionProbe:
            SpaceFixtureApplicationAXSuppressionCompletionProbe? =
                nil
    ) -> SpaceFixtureApplicationAXSuppressionOwner {
        let resolvedCompletionProbe =
            completionProbe
            ?? SpaceFixtureApplicationAXSuppressionCompletionProbe()
        return SpaceFixtureApplicationAXSuppressionOwner(
            scheduler: scheduler,
            acknowledgementObservationInstaller: {
                name,
                handler in
                observation.install(
                    notificationName: name,
                    handler: handler
                )
            },
            exposureProvider: {
                exposure.read()
            },
            completionPublisher: {
                completion,
                _ in
                resolvedCompletionProbe.record(completion)
            }
        )
    }
}
