import Foundation
import XCTest

extension FlowTabUITests {
    func testInitialPresentationResolutionReadbackResolvesFromInitialState()
        throws
    {
        let route =
            FlowTabUITestInitialPresentationResolutionRoute()
        try route.prepareReadback()
        defer { route.removeReadback() }
        try writeInitialPresentationResolutionReadback(
            matchingInitialPresentationResolutionReadback(),
            to: route.readbackURL
        )
        let owner =
            FlowTabUITestInitialPresentationResolutionObservationOwner(
                route: route,
                expectation:
                    disabledSearchInitialPresentationExpectation(),
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                }
            )
        owner.start()
        defer { owner.cancel() }

        let resolution = owner.waitForResolution(
            timeout:
                FlowTabUITestInitialPresentationResolutionPolicy
                    .immediateReadback
        )

        XCTAssertEqual(
            resolution,
            matchingInitialPresentationResolutionReadback()
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=initialReadback"
            )
        )
    }

    func testInitialPresentationResolutionReadbackUsesLaterExactEvidence()
        throws
    {
        let route =
            FlowTabUITestInitialPresentationResolutionRoute()
        try route.prepareReadback()
        defer { route.removeReadback() }
        try writeInitialPresentationResolutionReadback(
            matchingInitialPresentationResolutionReadback(
                baselineMode: "search",
                searchFeatureEnabled: true
            ),
            to: route.readbackURL
        )
        var requestReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var registrationWasCancelled = false
        let owner =
            FlowTabUITestInitialPresentationResolutionObservationOwner(
                route: route,
                expectation:
                    disabledSearchInitialPresentationExpectation(),
                observationRegistration: { callback in
                    requestReadback = callback
                    return FlowTabUITestObservationCancellation {
                        registrationWasCancelled = true
                    }
                }
            )
        owner.start()

        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "baselineMode=search"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "searchEnabled=true"
            )
        )
        try writeInitialPresentationResolutionReadback(
            matchingInitialPresentationResolutionReadback(),
            to: route.readbackURL
        )
        requestReadback?(.scheduledReadback)
        requestReadback?(.notificationReadback)
        let resolution = owner.waitForResolution(
            timeout:
                FlowTabUITestInitialPresentationResolutionPolicy
                    .immediateReadback
        )

        XCTAssertEqual(
            resolution?.searchFeatureEnabled,
            false
        )
        XCTAssertTrue(registrationWasCancelled)
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=scheduledReadback"
            )
        )
    }

    func testInitialPresentationResolutionExpectationRequiresExcludedItemsAbsentFromCompleteProjection() {
        let expectation =
            FlowTabUITestInitialPresentationResolutionExpectation(
                requiredItemIDs: ["com.flowtab.mock.mail"],
                excludedItemIDs: [
                    "com.flowtab.mock.minimized-notes"
                ],
                searchFeatureEnabled: false,
                searchIsActive: false,
                searchActivationIsPending: false
            )

        XCTAssertFalse(
            expectation.isSatisfied(
                by: matchingInitialPresentationResolutionReadback(
                    candidateItemIDs: [
                        "com.flowtab.mock.mail",
                        "com.flowtab.mock.minimized-notes"
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: matchingInitialPresentationResolutionReadback(
                    candidateProjectionIsComplete: false
                )
            )
        )
        XCTAssertTrue(
            expectation.isSatisfied(
                by: matchingInitialPresentationResolutionReadback()
            )
        )
    }

    func testInitialPresentationResolutionReadbackCancellationAndWatchdogDiagnostics()
        throws
    {
        XCTAssertEqual(
            FlowTabUITestInitialPresentationResolutionPolicy
                .immediateReadback,
            0
        )
        XCTAssertGreaterThan(
            FlowTabUITestInitialPresentationResolutionPolicy
                .readbackCadence,
            0
        )
        XCTAssertGreaterThan(
            FlowTabUITestInitialPresentationResolutionPolicy
                .watchdog,
            0
        )
        let route =
            FlowTabUITestInitialPresentationResolutionRoute()
        try route.prepareReadback()
        defer { route.removeReadback() }
        var cancelledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var registrationWasCancelled = false
        let cancelledOwner =
            FlowTabUITestInitialPresentationResolutionObservationOwner(
                route: route,
                expectation:
                    disabledSearchInitialPresentationExpectation(),
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        registrationWasCancelled = true
                    }
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        try writeInitialPresentationResolutionReadback(
            matchingInitialPresentationResolutionReadback(),
            to: route.readbackURL
        )
        cancelledReadback?(.notificationReadback)

        XCTAssertTrue(registrationWasCancelled)
        XCTAssertNil(
            cancelledOwner.waitForResolution(
                timeout:
                    FlowTabUITestInitialPresentationResolutionPolicy
                        .immediateReadback
            )
        )

        route.removeReadback()
        let watchdogOwner =
            FlowTabUITestInitialPresentationResolutionObservationOwner(
                route: route,
                expectation:
                    disabledSearchInitialPresentationExpectation(),
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                }
            )
        watchdogOwner.start()
        defer { watchdogOwner.cancel() }

        XCTAssertNil(
            watchdogOwner.waitForResolution(
                timeout:
                    FlowTabUITestInitialPresentationResolutionPolicy
                        .immediateReadback
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "fileExists=false"
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "waitResult="
            )
        )
    }

    private func disabledSearchInitialPresentationExpectation()
        -> FlowTabUITestInitialPresentationResolutionExpectation
    {
        FlowTabUITestInitialPresentationResolutionExpectation(
            requiredItemIDs: ["com.flowtab.mock.mail"],
            excludedItemIDs: [],
            searchFeatureEnabled: false,
            searchIsActive: false,
            searchActivationIsPending: false
        )
    }

    private func matchingInitialPresentationResolutionReadback(
        baselineMode: String = "global",
        searchFeatureEnabled: Bool = false,
        candidateProjectionIsComplete: Bool = true,
        candidateItemIDs: [String] = [
            "com.flowtab.mock.mail",
            "com.flowtab.mock.browser"
        ]
    ) -> FlowTabUITestInitialPresentationResolutionReadback {
        let candidateGeneration =
            FlowTabUITestInitialPresentationResolutionReadback
                .Generation(
                    appLifecycle: 2,
                    cg: 3,
                    space: 4,
                    axDirty: 5,
                    projection: 6
                )
        return FlowTabUITestInitialPresentationResolutionReadback(
            schemaVersion: 1,
            observationGeneration: 7,
            source: "initialReadback",
            resolution: "presented",
            baselineMode: baselineMode,
            baselineSourceGeneration: candidateGeneration,
            candidateMode: "global",
            candidateProjectionIsPresent: true,
            candidateProjectionIsComplete:
                candidateProjectionIsComplete,
            candidateSourceGeneration: candidateGeneration,
            candidateProcessIdentifier: nil,
            candidateItemIDs: candidateItemIDs,
            didPresent: true,
            sessionItemIDs: candidateItemIDs,
            attemptSearchIsActiveOrPending: false,
            postPresentationMode: "global",
            postPresentationSourceGeneration:
                candidateGeneration,
            postPresentationProcessIdentifier: nil,
            postPresentationItemIDs: candidateItemIDs,
            panelIsPresented: true,
            sessionMode: "appCycle",
            searchFeatureEnabled: searchFeatureEnabled,
            searchIsActive: false,
            searchActivationIsPending: false
        )
    }

    private func writeInitialPresentationResolutionReadback(
        _ readback:
            FlowTabUITestInitialPresentationResolutionReadback,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(readback).write(
            to: url,
            options: .atomic
        )
    }
}
