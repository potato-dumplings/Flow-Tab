import AppKit
import Foundation
import XCTest
@testable import FlowTab
import FlowTabCore

private final class CurrentAppProjectionEvidenceRecorder:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storage:
        [FlowTabUITestCurrentAppProjectionEvidence] = []

    func record(
        _ evidence:
            FlowTabUITestCurrentAppProjectionEvidence
    ) {
        lock.lock()
        storage.append(evidence)
        lock.unlock()
    }

    var values:
        [FlowTabUITestCurrentAppProjectionEvidence]
    {
        lock.lock()
        let values = storage
        lock.unlock()
        return values
    }
}

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

    func testCurrentAppProjectionEvidenceRouteRequiresExactEnabledValues() {
        let argument = FlowTabTestLaunchOptions
            .currentAppProjectionEvidenceRouteArgument
        let readbackPath =
            "/private/tmp/test-current-app-projection.json"
        withLaunchArgumentsForTesting([
            "FlowTab",
            argument,
            "  test.current-app-projection  ",
            "  com.example.fixture  ",
            "  \(readbackPath)  "
        ]) {
            XCTAssertEqual(
                FlowTabTestLaunchOptions
                    .currentAppProjectionEvidenceRoute,
                FlowTabUITestCurrentAppProjectionEvidenceRoute(
                    notificationName:
                        Notification.Name(
                            "test.current-app-projection"
                        ),
                    readbackURL: URL(
                        fileURLWithPath: readbackPath
                    ),
                    bundleIdentifier: "com.example.fixture"
                )
            )
        }

        for invalidArguments in [
            ["FlowTab", argument, "test.incomplete"],
            [
                "FlowTab",
                argument,
                "test.relative",
                "com.example.fixture",
                "relative/readback.json"
            ]
        ] {
            withLaunchArgumentsForTesting(invalidArguments) {
                XCTAssertNil(
                    FlowTabTestLaunchOptions
                        .currentAppProjectionEvidenceRoute
                )
            }
        }
        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                argument,
                "test.disabled",
                "com.example.fixture",
                readbackPath
            ],
            environment: [:]
        ) {
            XCTAssertNil(
                FlowTabTestLaunchOptions
                    .currentAppProjectionEvidenceRoute
            )
        }
    }

    @MainActor
    func testCurrentAppProjectionEvidenceObservationPublishesExactSnapshots() {
        let route =
            FlowTabUITestCurrentAppProjectionEvidenceRoute(
                notificationName:
                    Notification.Name(
                        "test.current-app-projection"
                    ),
                readbackURL: URL(
                    fileURLWithPath:
                        "/private/tmp/test-current-app-projection.json"
                ),
                bundleIdentifier: "com.example.fixture"
            )
        let recorder = CurrentAppProjectionEvidenceRecorder()
        let publisher =
            FlowTabUITestCurrentAppProjectionEvidencePublisher(
                route: route,
                sink: recorder.record
            )
        let notificationCenter = NotificationCenter()
        let notificationObject = NSObject()
        let owner =
            FlowTabUITestCurrentAppProjectionEvidenceObservationOwner(
                route: route,
                notificationObject: notificationObject,
                evidencePublisher: publisher,
                notificationCenter: notificationCenter
            )
        owner.start()
        XCTAssertTrue(owner.isObserving)

        notificationCenter.post(
            name: .runtimeCurrentAppWindowProjectionDidUpdate,
            object: notificationObject,
            userInfo: [
                RuntimeProjectionNotificationUserInfoKey
                    .currentAppWindowProjectionUpdateEvidence:
                    currentAppProjectionUpdate(
                        appID: "com.example.other",
                        projectionGeneration: 1,
                        windowIDs: ["other-window"]
                    )
            ]
        )
        notificationCenter.post(
            name: .runtimeCurrentAppWindowProjectionDidUpdate,
            object: NSObject(),
            userInfo: [
                RuntimeProjectionNotificationUserInfoKey
                    .currentAppWindowProjectionUpdateEvidence:
                    currentAppProjectionUpdate(
                        projectionGeneration: 2,
                        windowIDs: ["wrong-object"]
                    )
            ]
        )
        for generation in 3...4 {
            notificationCenter.post(
                name:
                    .runtimeCurrentAppWindowProjectionDidUpdate,
                object: notificationObject,
                userInfo: [
                    RuntimeProjectionNotificationUserInfoKey
                        .currentAppWindowProjectionUpdateEvidence:
                        currentAppProjectionUpdate(
                            projectionGeneration:
                                UInt64(generation),
                            windowIDs:
                                generation == 3
                                    ? ["window-1", "window-2"]
                                    : ["window-1"]
                        )
                ]
            )
        }
        owner.cancel()
        notificationCenter.post(
            name: .runtimeCurrentAppWindowProjectionDidUpdate,
            object: notificationObject,
            userInfo: [
                RuntimeProjectionNotificationUserInfoKey
                    .currentAppWindowProjectionUpdateEvidence:
                    currentAppProjectionUpdate(
                        projectionGeneration: 5,
                        windowIDs: []
                    )
            ]
        )

        XCTAssertFalse(owner.isObserving)
        XCTAssertEqual(
            recorder.values.map(\.evidenceGeneration),
            [1, 2]
        )
        XCTAssertEqual(
            recorder.values.map(\.windowIDs),
            [
                ["window-1", "window-2"],
                ["window-1"]
            ]
        )
        XCTAssertEqual(
            recorder.values.map {
                $0.sourceGeneration.projection
            },
            [3, 4]
        )
        XCTAssertEqual(
            FlowTabUITestCurrentAppProjectionEvidenceTransport
                .userInfo(for: recorder.values[0])[
                    FlowTabUITestCurrentAppProjectionEvidenceUserInfoKey
                        .windowIDs
                ] as? [String],
            ["window-1", "window-2"]
        )
    }

    @MainActor
    func testCurrentAppProjectionEvidenceBootstrapPreservesServiceIdentity() {
        let previousHooks = AppDelegate.testHooks
        let baseService = RecordingRuntimeProjectionService()
        var hooks = previousHooks
        hooks.runtimeProjectionService = baseService
        AppDelegate.testHooks = hooks
        defer {
            withLaunchArgumentsForTesting(["FlowTab"]) {
                FlowTabUITestCurrentAppProjectionEvidenceBootstrap
                    .prepareIfNeeded(service: baseService)
            }
            AppDelegate.testHooks = previousHooks
        }

        withLaunchArgumentsForTesting([
            "FlowTab",
            FlowTabTestLaunchOptions
                .currentAppProjectionEvidenceRouteArgument,
            "test.current-app-projection.bootstrap",
            "com.example.fixture",
            "/private/tmp/test-current-app-projection-bootstrap.json"
        ]) {
            FlowTabUITestCurrentAppProjectionEvidenceBootstrap
                .prepareIfNeeded(service: baseService)
        }

        XCTAssertTrue(
            AppDelegate.testHooks.runtimeProjectionService
                as AnyObject
                === baseService as AnyObject
        )
        XCTAssertEqual(
            FlowTabUITestCurrentAppProjectionEvidenceBootstrap
                .installedRouteForTesting?
                .bundleIdentifier,
            "com.example.fixture"
        )
        XCTAssertTrue(
            FlowTabUITestCurrentAppProjectionEvidenceBootstrap
                .isObservingForTesting
        )

        withLaunchArgumentsForTesting(["FlowTab"]) {
            FlowTabUITestCurrentAppProjectionEvidenceBootstrap
                .prepareIfNeeded(service: baseService)
        }
        XCTAssertTrue(
            AppDelegate.testHooks.runtimeProjectionService
                as AnyObject
                === baseService as AnyObject
        )
        XCTAssertNil(
            FlowTabUITestCurrentAppProjectionEvidenceBootstrap
                .installedRouteForTesting
        )
        XCTAssertFalse(
            FlowTabUITestCurrentAppProjectionEvidenceBootstrap
                .isObservingForTesting
        )
    }

    func testCurrentAppProjectionEvidencePublisherPressureIsDeterministic() {
        let route =
            FlowTabUITestCurrentAppProjectionEvidenceRoute(
                notificationName:
                    Notification.Name(
                        "test.current-app-projection.pressure"
                    ),
                readbackURL: URL(
                    fileURLWithPath:
                        "/private/tmp/test-current-app-projection-pressure.json"
                ),
                bundleIdentifier: "com.example.fixture"
            )
        let recorder = CurrentAppProjectionEvidenceRecorder()
        let publisher =
            FlowTabUITestCurrentAppProjectionEvidencePublisher(
                route: route,
                sink: recorder.record
            )

        for generation in 1...2_000 {
            publisher.record(
                currentAppProjectionUpdate(
                    appID: "com.example.other",
                    projectionGeneration: UInt64(generation),
                    windowIDs: ["other-window"]
                )
            )
            publisher.record(
                currentAppProjectionUpdate(
                    processIdentifier:
                        pid_t(45_000 + generation),
                    projectionGeneration: UInt64(generation),
                    windowIDs: ["window-\(generation)"]
                )
            )
        }

        XCTAssertEqual(recorder.values.count, 2_000)
        XCTAssertEqual(
            recorder.values.map(\.evidenceGeneration),
            Array(1...2_000).map(UInt64.init)
        )
    }

    private func currentAppProjectionUpdate(
        appID: String = "com.example.fixture",
        processIdentifier: pid_t = 44_001,
        projectionGeneration: UInt64,
        windowIDs: [String]
    ) -> RuntimeCurrentAppWindowProjectionUpdateEvidence {
        RuntimeCurrentAppWindowProjectionUpdateEvidence(
            appID: appID,
            processIdentifier: processIdentifier,
            windowIDs: windowIDs,
            isCompleteForScope: true,
            sourceGeneration: RuntimeReadModelGeneration(
                appLifecycle: projectionGeneration,
                cg: projectionGeneration,
                space: projectionGeneration,
                axDirty: projectionGeneration,
                projection: projectionGeneration
            )
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
