import XCTest
@testable import FlowTab

private enum FlowTabUITestInitialSearchActivationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabTests {
    @MainActor
    func testInitialSearchActivationUsesSatisfiedPresentationReadback() {
        let scheduler = ManualInitialPresentationScheduler()
        var activationCount = 0
        let owner =
            FlowTabUITestInitialSearchActivationObservationOwner(
                notificationObject: NSObject(),
                scheduler: scheduler,
                readback: {
                    FlowTabUITestInitialSearchActivationSnapshot(
                        panelIsPresented: true,
                        sessionItemIDs: ["app-a"],
                        searchIsActive: true,
                        searchActivationIsPending: false
                    )
                },
                activateSearch: {
                    activationCount += 1
                }
            )
        owner.start()
        var resolution:
            FlowTabUITestInitialSearchActivationEvidence?

        owner.awaitActivation(
            expectedItemIDs: ["app-a"],
            watchdogInterval:
                FlowTabUITestInitialSearchActivationTestPolicy
                    .watchdog,
            onResolved: { resolution = $0 },
            onWatchdog: { _ in
                XCTFail("Satisfied initial Search readback expired")
            }
        )

        XCTAssertEqual(
            resolution?.source,
            .presentationReadback
        )
        XCTAssertEqual(activationCount, 0)
        XCTAssertFalse(owner.isObserving)
        XCTAssertFalse(owner.hasPendingWatchdog)
        XCTAssertTrue(scheduler.tokens.isEmpty)
    }

    @MainActor
    func testInitialSearchActivationConsumesCommittedIndexEvent() {
        let center = NotificationCenter()
        let notificationName = Notification.Name(
            "FlowTab.InitialSearchActivation.Committed"
        )
        let notificationObject = NSObject()
        let scheduler = ManualInitialPresentationScheduler()
        var committedIndexIsReady = false
        var snapshot =
            FlowTabUITestInitialSearchActivationSnapshot(
                panelIsPresented: true,
                sessionItemIDs: ["app-a", "app-b"],
                searchIsActive: false,
                searchActivationIsPending: true
            )
        var activationCount = 0
        let owner =
            FlowTabUITestInitialSearchActivationObservationOwner(
                notificationCenter: center,
                notificationName: notificationName,
                notificationObject: notificationObject,
                scheduler: scheduler,
                readback: { snapshot },
                activateSearch: {
                    activationCount += 1
                    if committedIndexIsReady {
                        snapshot =
                            FlowTabUITestInitialSearchActivationSnapshot(
                                panelIsPresented: true,
                                sessionItemIDs:
                                    ["app-a", "app-b"],
                                searchIsActive: true,
                                searchActivationIsPending:
                                    false
                            )
                    }
                }
            )
        owner.start()
        var resolution:
            FlowTabUITestInitialSearchActivationEvidence?
        owner.awaitActivation(
            expectedItemIDs: ["app-a", "app-b"],
            watchdogInterval:
                FlowTabUITestInitialSearchActivationTestPolicy
                    .watchdog,
            onResolved: { resolution = $0 },
            onWatchdog: { _ in
                XCTFail("Committed-index activation expired")
            }
        )
        XCTAssertNil(resolution)
        XCTAssertEqual(activationCount, 1)

        committedIndexIsReady = true
        center.post(
            name: notificationName,
            object: notificationObject
        )

        XCTAssertEqual(
            resolution?.source,
            .committedSearchIndexDidUpdate
        )
        XCTAssertEqual(
            resolution?.committedIndexGeneration,
            1
        )
        XCTAssertEqual(activationCount, 2)
        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testInitialSearchActivationDoesNotMissPrePresentationEvent() {
        let center = NotificationCenter()
        let notificationName = Notification.Name(
            "FlowTab.InitialSearchActivation.PrePresentation"
        )
        let notificationObject = NSObject()
        let scheduler = ManualInitialPresentationScheduler()
        var snapshot =
            FlowTabUITestInitialSearchActivationSnapshot(
                panelIsPresented: false,
                sessionItemIDs: [],
                searchIsActive: false,
                searchActivationIsPending: false
            )
        var committedIndexIsReady = false
        let owner =
            FlowTabUITestInitialSearchActivationObservationOwner(
                notificationCenter: center,
                notificationName: notificationName,
                notificationObject: notificationObject,
                scheduler: scheduler,
                readback: { snapshot },
                activateSearch: {
                    if committedIndexIsReady {
                        snapshot =
                            FlowTabUITestInitialSearchActivationSnapshot(
                                panelIsPresented: true,
                                sessionItemIDs: ["app-a"],
                                searchIsActive: true,
                                searchActivationIsPending:
                                    false
                            )
                    }
                }
            )
        owner.start {
            committedIndexIsReady = true
            center.post(
                name: notificationName,
                object: notificationObject
            )
        }
        XCTAssertEqual(
            owner.lastEvidence?.committedIndexGeneration,
            1
        )
        snapshot =
            FlowTabUITestInitialSearchActivationSnapshot(
                panelIsPresented: true,
                sessionItemIDs: ["app-a"],
                searchIsActive: false,
                searchActivationIsPending: false
            )
        var resolution:
            FlowTabUITestInitialSearchActivationEvidence?
        owner.awaitActivation(
            expectedItemIDs: ["app-a"],
            watchdogInterval:
                FlowTabUITestInitialSearchActivationTestPolicy
                    .watchdog,
            onResolved: { resolution = $0 },
            onWatchdog: { _ in
                XCTFail("Pre-presentation event was lost")
            }
        )

        XCTAssertEqual(
            resolution?.source,
            .activationReadback
        )
        XCTAssertEqual(
            resolution?.committedIndexGeneration,
            1
        )
    }

    @MainActor
    func testInitialSearchActivationRejectsStaleEventsUnderPressure() {
        let scheduler = ManualInitialPresentationScheduler()
        var snapshot =
            FlowTabUITestInitialSearchActivationSnapshot(
                panelIsPresented: true,
                sessionItemIDs: ["app-a"],
                searchIsActive: false,
                searchActivationIsPending: true
            )
        var activationCount = 0
        let owner =
            FlowTabUITestInitialSearchActivationObservationOwner(
                notificationObject: NSObject(),
                scheduler: scheduler,
                readback: { snapshot },
                activateSearch: {
                    activationCount += 1
                }
            )

        for _ in 0..<FlowTabUITestInitialSearchActivationTestPolicy
            .pressureIterations
        {
            let staleGeneration = owner.start()
            owner.awaitActivation(
                expectedItemIDs: ["app-a"],
                watchdogInterval:
                    FlowTabUITestInitialSearchActivationTestPolicy
                        .watchdog,
                onResolved: { _ in
                    XCTFail("Cancelled generation resolved")
                },
                onWatchdog: { _ in
                    XCTFail("Cancelled generation expired")
                }
            )
            let staleToken = scheduler.tokens.last!
            owner.cancel()
            XCTAssertTrue(staleToken.isCancelled)

            let currentGeneration = owner.start()
            var resolution:
                FlowTabUITestInitialSearchActivationEvidence?
            owner.awaitActivation(
                expectedItemIDs: ["app-a"],
                watchdogInterval:
                    FlowTabUITestInitialSearchActivationTestPolicy
                        .watchdog,
                onResolved: { resolution = $0 },
                onWatchdog: { _ in
                    XCTFail("Current generation expired")
                }
            )
            let activationBaseline = activationCount
            XCTAssertFalse(
                owner.observeCommittedSearchIndexUpdate(
                    generation: staleGeneration
                )
            )
            XCTAssertEqual(
                activationCount,
                activationBaseline
            )
            snapshot =
                FlowTabUITestInitialSearchActivationSnapshot(
                    panelIsPresented: true,
                    sessionItemIDs: ["app-a"],
                    searchIsActive: true,
                    searchActivationIsPending: false
                )
            XCTAssertTrue(
                owner.observeCommittedSearchIndexUpdate(
                    generation: currentGeneration
                )
            )
            XCTAssertFalse(
                owner.observeCommittedSearchIndexUpdate(
                    generation: currentGeneration
                )
            )
            XCTAssertEqual(
                resolution?.observationGeneration,
                currentGeneration
            )
            snapshot =
                FlowTabUITestInitialSearchActivationSnapshot(
                    panelIsPresented: true,
                    sessionItemIDs: ["app-a"],
                    searchIsActive: false,
                    searchActivationIsPending: true
                )
        }
    }

    @MainActor
    func testInitialSearchActivationWatchdogReportsFinalEvidence() {
        let scheduler = ManualInitialPresentationScheduler()
        let owner =
            FlowTabUITestInitialSearchActivationObservationOwner(
                notificationObject: NSObject(),
                scheduler: scheduler,
                readback: {
                    FlowTabUITestInitialSearchActivationSnapshot(
                        panelIsPresented: true,
                        sessionItemIDs: ["wrong-app"],
                        searchIsActive: true,
                        searchActivationIsPending: false
                    )
                },
                activateSearch: {}
            )
        owner.start()
        var failure:
            FlowTabUITestInitialSearchActivationWatchdogFailure?
        owner.awaitActivation(
            expectedItemIDs: ["app-a"],
            watchdogInterval:
                FlowTabUITestInitialSearchActivationTestPolicy
                    .watchdog,
            onResolved: { _ in
                XCTFail("Mismatched session resolved")
            },
            onWatchdog: { failure = $0 }
        )

        scheduler.fire(scheduler.tokens[0])

        XCTAssertEqual(
            failure?.finalEvidence.source,
            .watchdogReadback
        )
        XCTAssertTrue(
            failure?.logFields.contains(
                "expected=[app-a]"
            ) == true
        )
        XCTAssertTrue(
            failure?.logFields.contains(
                "sessionItems=[wrong-app]"
            ) == true
        )
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testInitialSearchActivationWatchdogAcceptsSatisfiedReadback() {
        let scheduler = ManualInitialPresentationScheduler()
        var searchIsActive = false
        var activationCount = 0
        let owner =
            FlowTabUITestInitialSearchActivationObservationOwner(
                notificationObject: NSObject(),
                scheduler: scheduler,
                readback: {
                    FlowTabUITestInitialSearchActivationSnapshot(
                        panelIsPresented: true,
                        sessionItemIDs: ["app-a"],
                        searchIsActive: searchIsActive,
                        searchActivationIsPending:
                            !searchIsActive
                    )
                },
                activateSearch: {
                    activationCount += 1
                }
            )
        owner.start()
        var resolution:
            FlowTabUITestInitialSearchActivationEvidence?
        owner.awaitActivation(
            expectedItemIDs: ["app-a"],
            watchdogInterval:
                FlowTabUITestInitialSearchActivationTestPolicy
                    .watchdog,
            onResolved: { resolution = $0 },
            onWatchdog: { _ in
                XCTFail("Final satisfied readback expired")
            }
        )
        searchIsActive = true

        scheduler.fire(scheduler.tokens[0])

        XCTAssertEqual(
            resolution?.source,
            .watchdogReadback
        )
        XCTAssertEqual(activationCount, 1)
    }
}
