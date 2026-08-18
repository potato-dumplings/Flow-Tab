import ApplicationServices
import Darwin
import XCTest
@testable import FlowTab

@MainActor
private final class
    ManualUITestAXSuppressionReadbackToken:
    FlowTabUITestAXSuppressionReadbackCancellable
{
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

@MainActor
private final class
    ManualUITestAXSuppressionReadbackScheduler:
    FlowTabUITestAXSuppressionReadbackScheduling
{
    struct Entry {
        let interval: TimeInterval
        let token:
            ManualUITestAXSuppressionReadbackToken
        let action: @MainActor @Sendable () -> Void
    }

    private(set) var entries: [Entry] = []

    func schedule(
        after interval: TimeInterval,
        _ action:
            @escaping @MainActor @Sendable () -> Void
    ) -> any FlowTabUITestAXSuppressionReadbackCancellable {
        let token =
            ManualUITestAXSuppressionReadbackToken()
        entries.append(
            Entry(
                interval: interval,
                token: token,
                action: action
            )
        )
        return token
    }

    func runLast() {
        guard let entry = entries.last,
              !entry.token.isCancelled
        else {
            return
        }
        entry.action()
    }
}

extension FlowTabTests {
    @MainActor
    func testAXSuppressionReadbackRoutesRequireCompleteUniqueTuples() {
        let argument =
            FlowTabTestLaunchOptions
                .axSuppressionReadbackRouteArgument
        withLaunchArgumentsForTesting([
            argument,
            "  test.suppression.one  ",
            "  test.external.one  ",
            "  com.example.fixture  ",
            "2",
            argument,
            "test.suppression.one",
            "test.external.duplicate-completion",
            "com.example.duplicate",
            "3",
            argument,
            "test.suppression.duplicate-verification",
            "test.external.one",
            "com.example.duplicate",
            "3",
            argument,
            "test.suppression.zero",
            "test.external.zero",
            "com.example.zero",
            "0",
            argument,
            "test.incomplete",
        ]) {
            XCTAssertEqual(
                FlowTabTestLaunchOptions
                    .axSuppressionReadbackRoutes,
                [
                    FlowTabUITestAXSuppressionReadbackRoute(
                        completionNotificationName:
                            .init(
                                "test.suppression.one"
                            ),
                        verificationNotificationName:
                            .init(
                                "test.external.one"
                            ),
                        bundleIdentifier:
                            "com.example.fixture",
                        expectedWindowCount: 2
                    )
                ]
            )
        }

        withLaunchArgumentsForTesting(
            [
                argument,
                "test.suppression.disabled",
                "test.external.disabled",
                "com.example.disabled",
                "1",
            ],
            environment: [:]
        ) {
            XCTAssertTrue(
                FlowTabTestLaunchOptions
                    .axSuppressionReadbackRoutes
                    .isEmpty
            )
        }
    }

    @MainActor
    func testAXSuppressionReadbackInstallsObserverBeforeImmediateReadback() {
        let route = axSuppressionReadbackRoute()
        var callback:
            ((FlowTabUITestAXSuppressionCompletion) -> Void)?
        var order: [String] = []
        var published:
            [FlowTabUITestAXSuppressionReadbackEvidence] = []
        let owner =
            FlowTabUITestAXSuppressionReadbackOwner(
                routes: [route],
                completionRegistration: {
                    _, observe in
                    order.append("observer")
                    callback = observe
                    return
                        ManualUITestAXSuppressionReadbackToken()
                },
                readback: { _ in
                    order.append("readback")
                    return
                        self.axSuppressionApplicationReadback()
                },
                publisher: {
                    order.append("publisher")
                    published.append($0)
                }
            )

        let generation = owner.start()
        XCTAssertTrue(owner.isObserving)
        XCTAssertEqual(order, ["observer"])

        callback?(axSuppressionCompletion())

        XCTAssertEqual(generation, 1)
        XCTAssertEqual(
            order,
            ["observer", "readback", "publisher"]
        )
        XCTAssertEqual(
            published.map(\.source),
            [.completionNotification]
        )
        XCTAssertEqual(
            published.map(\.observationGeneration),
            [1]
        )
        XCTAssertEqual(
            published.map(\.verificationGeneration),
            [1]
        )
        owner.cancel()
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testAXSuppressionReadbackRetriesOnlyUntilAuthorizedAXConverges() {
        let scheduler =
            ManualUITestAXSuppressionReadbackScheduler()
        var callback:
            ((FlowTabUITestAXSuppressionCompletion) -> Void)?
        var currentReadback =
            axSuppressionApplicationReadback(
                childCount: 1,
                windowCount: 1
            )
        var published:
            [FlowTabUITestAXSuppressionReadbackEvidence] = []
        let owner =
            FlowTabUITestAXSuppressionReadbackOwner(
                routes: [axSuppressionReadbackRoute()],
                completionRegistration: {
                    _, observe in
                    callback = observe
                    return
                        ManualUITestAXSuppressionReadbackToken()
                },
                scheduler: scheduler,
                readback: { _ in currentReadback },
                publisher: { published.append($0) }
            )
        owner.start()
        defer { owner.cancel() }

        callback?(axSuppressionCompletion())

        XCTAssertTrue(published.isEmpty)
        XCTAssertEqual(scheduler.entries.count, 1)
        XCTAssertEqual(
            scheduler.entries[0].interval,
            FlowTabUITestAXSuppressionReadbackPolicy
                .propagationReadbackCadence
        )

        currentReadback =
            axSuppressionApplicationReadback()
        scheduler.runLast()

        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(
            published.first?.source,
            .scheduledReadback
        )
        XCTAssertEqual(scheduler.entries.count, 1)
    }

    @MainActor
    func testAXSuppressionReadbackRejectsStaleDuplicateAndRegressedGenerationsUnderPressure() {
        for iteration in 0..<100 {
            let route = axSuppressionReadbackRoute(
                suffix: "\(iteration)"
            )
            var callbacks: [
                (FlowTabUITestAXSuppressionCompletion) -> Void
            ] = []
            var tokens: [
                ManualUITestAXSuppressionReadbackToken
            ] = []
            var published:
                [FlowTabUITestAXSuppressionReadbackEvidence] = []
            let owner =
                FlowTabUITestAXSuppressionReadbackOwner(
                    routes: [route],
                    completionRegistration: {
                        _, observe in
                        callbacks.append(observe)
                        let token =
                            ManualUITestAXSuppressionReadbackToken()
                        tokens.append(token)
                        return token
                    },
                    readback: { _ in
                        self.axSuppressionApplicationReadback()
                    },
                    publisher: {
                        published.append($0)
                    }
                )

            owner.start()
            let staleCallback = callbacks[0]
            owner.cancel()
            owner.start()

            staleCallback(
                axSuppressionCompletion(
                    suppressionGeneration: 100
                )
            )
            callbacks[1](
                axSuppressionCompletion(
                    suppressionGeneration: 2,
                    bundleIdentifier:
                        "com.example.wrong"
                )
            )
            callbacks[1](
                axSuppressionCompletion(
                    suppressionGeneration: 2
                )
            )
            callbacks[1](
                axSuppressionCompletion(
                    suppressionGeneration: 2
                )
            )
            callbacks[1](
                axSuppressionCompletion(
                    suppressionGeneration: 1
                )
            )

            XCTAssertEqual(
                published.map {
                    $0.completion
                        .suppressionGeneration
                },
                [2]
            )
            owner.cancel()
            XCTAssertTrue(tokens.allSatisfy(\.isCancelled))
        }
    }

    @MainActor
    private func axSuppressionReadbackRoute(
        suffix: String = "route"
    ) -> FlowTabUITestAXSuppressionReadbackRoute {
        FlowTabUITestAXSuppressionReadbackRoute(
            completionNotificationName:
                .init("test.suppression.\(suffix)"),
            verificationNotificationName:
                .init("test.external.\(suffix)"),
            bundleIdentifier:
                "com.example.fixture.chrome",
            expectedWindowCount: 4
        )
    }

    @MainActor
    private func axSuppressionCompletion(
        suppressionGeneration: UInt64 = 2,
        bundleIdentifier: String =
            "com.example.fixture.chrome"
    ) -> FlowTabUITestAXSuppressionCompletion {
        FlowTabUITestAXSuppressionCompletion(
            suppressionGeneration: suppressionGeneration,
            acknowledgementGeneration: 1,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: pid_t(4_567),
            windowCount: 4,
            sourceGeneration: "source-1",
            childWindowCount: 0,
            windowsAttributeCount: 0
        )
    }

    @MainActor
    private func axSuppressionApplicationReadback(
        childCount: Int = 0,
        windowCount: Int = 0
    ) -> FlowTabUITestAXSuppressionApplicationReadback {
        FlowTabUITestAXSuppressionApplicationReadback(
            exactProcessIsRunning: true,
            children: FlowTabUITestAXAttributeReadback(
                errorCode: AXError.success.rawValue,
                elementCount: childCount
            ),
            windows: FlowTabUITestAXAttributeReadback(
                errorCode: AXError.success.rawValue,
                elementCount: windowCount
            )
        )
    }
}
