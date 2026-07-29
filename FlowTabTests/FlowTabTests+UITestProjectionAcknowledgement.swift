import AppKit
import Foundation
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabTests {
    @MainActor
    func testProjectionAcknowledgementRoutesRequireCompleteValidTriples() {
        let argument =
            FlowTabTestLaunchOptions
                .projectionAcknowledgementRouteArgument
        withLaunchArgumentsForTesting([
            argument,
            "  test.projection.one  ",
            "  com.example.fixture  ",
            "2",
            argument,
            "test.projection.one",
            "com.example.duplicate",
            "3",
            argument,
            "",
            "com.example.empty-name",
            "1",
            argument,
            "test.projection.zero-count",
            "com.example.zero-count",
            "0",
            argument,
            "test.projection.incomplete"
        ]) {
            XCTAssertEqual(
                FlowTabTestLaunchOptions
                    .projectionAcknowledgementRoutes,
                [
                    FlowTabUITestProjectionAcknowledgementRoute(
                        notificationName:
                            Notification.Name(
                                "test.projection.one"
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
                "test.projection.disabled",
                "com.example.disabled",
                "1"
            ],
            environment: [:]
        ) {
            XCTAssertTrue(
                FlowTabTestLaunchOptions
                    .projectionAcknowledgementRoutes
                    .isEmpty
            )
        }
    }

    @MainActor
    func testProjectionAcknowledgementInstallsObserverBeforeInitialReadback() {
        let notificationCenter = NotificationCenter()
        let route = projectionAcknowledgementRoute()
        var snapshots = [
            projectionAcknowledgementSnapshot(
                processIdentifier: 41_001,
                sourceGeneration: "projection=1"
            )
        ]
        var owner:
            FlowTabUITestProjectionAcknowledgementOwner!
        var observerWasInstalledBeforeReadback = false
        var published:
            [FlowTabUITestProjectionAcknowledgementEvidence] = []
        owner = FlowTabUITestProjectionAcknowledgementOwner(
            routes: [route],
            notificationCenter: notificationCenter,
            snapshotProvider: {
                observerWasInstalledBeforeReadback =
                    owner.isObserving
                return snapshots
            },
            acknowledgementPublisher: {
                published.append($0)
            }
        )

        let generation = owner.start()

        XCTAssertTrue(observerWasInstalledBeforeReadback)
        XCTAssertTrue(owner.isObserving)
        XCTAssertEqual(generation, 1)
        XCTAssertEqual(
            published.map(\.source),
            [.initialReadback]
        )
        XCTAssertEqual(
            published.map(\.snapshot.processIdentifier),
            [41_001]
        )
        XCTAssertEqual(
            published.map(\.acknowledgementGeneration),
            [1]
        )
        snapshots = []
        owner.cancel()
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testProjectionAcknowledgementWaitsForExactCompleteEvidence() {
        let notificationCenter = NotificationCenter()
        let route = projectionAcknowledgementRoute()
        var snapshots = [
            projectionAcknowledgementSnapshot(
                bundleIdentifier: "com.example.other",
                processIdentifier: 41_002,
                sourceGeneration: "projection=1"
            ),
            projectionAcknowledgementSnapshot(
                processIdentifier: 41_002,
                windowCount: 1,
                sourceGeneration: "projection=1"
            ),
            projectionAcknowledgementSnapshot(
                processIdentifier: 41_002,
                sourceGeneration: "projection=1",
                isComplete: false
            )
        ]
        var published:
            [FlowTabUITestProjectionAcknowledgementEvidence] = []
        let owner =
            FlowTabUITestProjectionAcknowledgementOwner(
                routes: [route],
                notificationCenter: notificationCenter,
                snapshotProvider: { snapshots },
                acknowledgementPublisher: {
                    published.append($0)
                }
            )

        owner.start()
        XCTAssertTrue(published.isEmpty)

        snapshots = [
            projectionAcknowledgementSnapshot(
                processIdentifier: 41_002,
                sourceGeneration: "projection=2"
            )
        ]
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: nil
        )
        XCTAssertEqual(
            published.map(\.source),
            [.runtimeProjectionDidUpdate]
        )

        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: nil
        )
        XCTAssertEqual(published.count, 1)

        snapshots = [
            projectionAcknowledgementSnapshot(
                processIdentifier: 41_003,
                sourceGeneration: "projection=3"
            )
        ]
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: nil
        )
        XCTAssertEqual(
            published.map(\.snapshot.processIdentifier),
            [41_002, 41_003]
        )
        XCTAssertEqual(
            published.map(\.acknowledgementGeneration),
            [1, 2]
        )
        owner.cancel()
    }

    @MainActor
    func testProjectionAcknowledgementRejectsCancelledAndStaleObservations() {
        let notificationCenter = NotificationCenter()
        var snapshots:
            [FlowTabUITestProjectionAcknowledgementSnapshot] = []
        var published:
            [FlowTabUITestProjectionAcknowledgementEvidence] = []
        let owner =
            FlowTabUITestProjectionAcknowledgementOwner(
                routes: [projectionAcknowledgementRoute()],
                notificationCenter: notificationCenter,
                snapshotProvider: { snapshots },
                acknowledgementPublisher: {
                    published.append($0)
                }
            )
        let cancelledGeneration = owner.start()
        owner.cancel()
        snapshots = [
            projectionAcknowledgementSnapshot(
                processIdentifier: 41_004,
                sourceGeneration: "projection=4"
            )
        ]

        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: nil
        )
        XCTAssertFalse(
            owner.observeProjectionDidUpdate(
                observationGeneration:
                    cancelledGeneration
            )
        )
        XCTAssertTrue(published.isEmpty)

        let activeGeneration = owner.start()
        XCTAssertGreaterThan(
            activeGeneration,
            cancelledGeneration
        )
        XCTAssertFalse(
            owner.observeProjectionDidUpdate(
                observationGeneration:
                    cancelledGeneration
            )
        )
        XCTAssertEqual(published.count, 1)
        owner.cancel()
    }

    @MainActor
    func testProjectionAcknowledgementLifecyclePressureIsDeterministic() {
        var snapshots:
            [FlowTabUITestProjectionAcknowledgementSnapshot] = []
        var published:
            [FlowTabUITestProjectionAcknowledgementEvidence] = []
        let owner =
            FlowTabUITestProjectionAcknowledgementOwner(
                routes: [projectionAcknowledgementRoute()],
                notificationCenter: NotificationCenter(),
                snapshotProvider: { snapshots },
                acknowledgementPublisher: {
                    published.append($0)
                }
            )

        for cycle in 0..<500 {
            snapshots = []
            let generation = owner.start()
            if cycle.isMultiple(of: 2) {
                snapshots = [
                    projectionAcknowledgementSnapshot(
                        processIdentifier:
                            pid_t(42_000 + cycle),
                        sourceGeneration:
                            "projection=\(cycle)"
                    )
                ]
                XCTAssertTrue(
                    owner.observeProjectionDidUpdate(
                        observationGeneration: generation
                    )
                )
            }
            owner.cancel()
            XCTAssertFalse(owner.isObserving)
            XCTAssertFalse(
                owner.observeProjectionDidUpdate(
                    observationGeneration: generation
                )
            )
        }

        XCTAssertEqual(published.count, 250)
        XCTAssertEqual(
            published.map(\.acknowledgementGeneration),
            Array(1...250).map(UInt64.init)
        )
        XCTAssertEqual(
            published.map(\.observationGeneration),
            published.map(\.observationGeneration).sorted()
        )
    }

    private func projectionAcknowledgementRoute()
        -> FlowTabUITestProjectionAcknowledgementRoute
    {
        FlowTabUITestProjectionAcknowledgementRoute(
            notificationName:
                Notification.Name(
                    "test.projection.acknowledgement"
                ),
            bundleIdentifier: "com.example.fixture",
            expectedWindowCount: 2
        )
    }

    private func projectionAcknowledgementSnapshot(
        bundleIdentifier: String = "com.example.fixture",
        processIdentifier: pid_t,
        windowCount: Int = 2,
        sourceGeneration: String,
        isComplete: Bool = true
    ) -> FlowTabUITestProjectionAcknowledgementSnapshot {
        FlowTabUITestProjectionAcknowledgementSnapshot(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            windowCount: windowCount,
            sourceGeneration: sourceGeneration,
            isComplete: isComplete
        )
    }
}
