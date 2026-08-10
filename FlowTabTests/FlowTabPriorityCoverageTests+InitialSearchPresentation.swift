import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testUITestSearchLaunchUsesControllerSearchSizingPath()
        async
    {
        await withTemporarySearchPreferences(
            enabled: true,
            defaultScope: .app
        ) {
            let previousLaunchArguments =
                FlowTabTestLaunchOptions
                    .argumentsOverrideForTesting
            let previousLaunchEnvironment =
                FlowTabTestLaunchOptions
                    .environmentOverrideForTesting
            FlowTabTestLaunchOptions
                .argumentsOverrideForTesting = [
                    "--flowtab-ui-open-switcher-search"
                ]
            FlowTabTestLaunchOptions
                .environmentOverrideForTesting = [
                    FlowTabTestLaunchOptions
                        .uiTestingEnvironmentKey:
                        FlowTabTestLaunchOptions
                            .uiTestingEnvironmentValue
                ]

            let apps = searchScenarioApps()
            let expectedAppIDs = apps.map(\.id)
            guard
                let expectedFirstAppID =
                    expectedAppIDs.first
            else {
                return XCTFail(
                    "Expected launch fixture apps"
                )
            }
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService:
                        RecordingRuntimeProjectionService(
                            appSwitcherApps: apps
                        )
                )
            )
            let model = controller.modelForTesting
            let expectedSearchHeight = {
                SwitcherPanelLayoutMetrics.Search.panelHeight(
                    visibleRowCount:
                        SwitcherPanelLayoutMetrics.Search
                            .visibleRowCount(
                                for: apps.count
                            ),
                    measurements:
                        model.searchLayoutMeasurements
                )
            }
            let presentationResolved = expectation(
                description:
                    "unmetCondition=initialSearchPresentationResolvedWithExactState"
            )
            presentationResolved.assertForOverFulfill =
                true
            var resolvedEvidence:
                FlowTabUITestInitialPresentationEvidence?
            var lastObservedEvidence:
                FlowTabUITestInitialPresentationEvidence?
            let observer =
                NotificationCenter.default.addObserver(
                    forName:
                        .flowTabUITestInitialPresentationDidResolve,
                    object: controller,
                    queue: .main
                ) { notification in
                    MainActor.assumeIsolated {
                        guard
                            let evidence =
                                FlowTabUITestInitialPresentationEvidence(
                                    notification: notification
                                )
                        else {
                            return
                        }
                        lastObservedEvidence = evidence
                        guard
                            evidence.observationGeneration > 0,
                            evidence.source == .initialReadback,
                            evidence.resolution == .presented,
                            evidence.baseline.mode == .global,
                            evidence.candidate.mode == .global,
                            evidence.candidate.itemIDs
                                == expectedAppIDs,
                            evidence.attempt?.didPresent
                                == true,
                            evidence.attempt?
                                .sessionItemIDs
                                == expectedAppIDs,
                            evidence.attempt?
                                .searchIsActiveOrPending
                                == true,
                            evidence.postPresentationReadback?
                                .itemIDs
                                == expectedAppIDs,
                            model.isSearchActive,
                            model.searchResultCount
                                == apps.count,
                            model.searchViewState
                                .selectedResult?.kind
                                == .app(
                                    appID:
                                        expectedFirstAppID
                                ),
                            abs(
                                controller
                                    .panelContentSizeForTesting
                                    .height
                                    - expectedSearchHeight()
                            ) <= 1,
                            !FlowTabUITestBootstrapper
                                .isObservingInitialPresentationForTesting
                        else {
                            return
                        }
                        resolvedEvidence = evidence
                        presentationResolved.fulfill()
                    }
                }
            defer {
                NotificationCenter.default
                    .removeObserver(observer)
                FlowTabUITestBootstrapper
                    .stopInitialUIPresentationObservation()
                controller.cancelSelectionForTesting()
                FlowTabTestLaunchOptions
                    .argumentsOverrideForTesting =
                        previousLaunchArguments
                FlowTabTestLaunchOptions
                    .environmentOverrideForTesting =
                        previousLaunchEnvironment
            }

            FlowTabUITestBootstrapper
                .presentInitialUIIfNeeded(
                    panelController: controller
                )

            await fulfillment(
                of: [presentationResolved],
                timeout:
                    FlowTabPriorityCoverageWatchdogPolicy
                        .initialSearchPresentationResolution
            )

            guard let resolvedEvidence else {
                return XCTFail(
                    "Initial Search presentation evidence did not satisfy the Oracle; last=\(lastObservedEvidence?.logFields ?? "none")"
                )
            }
            XCTAssertEqual(
                resolvedEvidence.resolution,
                .presented
            )
            XCTAssertEqual(
                resolvedEvidence.attempt?
                    .sessionItemIDs,
                expectedAppIDs
            )
            XCTAssertTrue(model.isSearchActive)
            XCTAssertEqual(
                model.searchResultCount,
                apps.count
            )
            XCTAssertEqual(
                model.searchViewState.selectedResult?.kind,
                .app(appID: expectedFirstAppID)
            )
            XCTAssertEqual(
                controller
                    .panelContentSizeForTesting
                    .height,
                expectedSearchHeight(),
                accuracy: 1
            )
            XCTAssertFalse(
                FlowTabUITestBootstrapper
                    .isObservingInitialPresentationForTesting
            )
        }
    }

    @MainActor
    func testUITestSearchLaunchResolvesAppCycleWhenPreferenceDisabled()
        async throws
    {
        try await withTemporarySearchPreferences(
            enabled: false,
            defaultScope: .app
        ) {
            let previousLaunchArguments =
                FlowTabTestLaunchOptions
                    .argumentsOverrideForTesting
            let previousLaunchEnvironment =
                FlowTabTestLaunchOptions
                    .environmentOverrideForTesting
            let resolutionRoute =
                FlowTabUITestInitialPresentationResolutionRoute(
                    notificationName: Notification.Name(
                        "test.initial-presentation.\(UUID().uuidString)"
                    ),
                    readbackURL:
                        FileManager.default.temporaryDirectory
                            .appendingPathComponent(
                                "flowtab-initial-presentation-\(UUID().uuidString).json",
                                isDirectory: false
                            )
                )
            try? FileManager.default.removeItem(
                at: resolutionRoute.readbackURL
            )
            FlowTabTestLaunchOptions
                .argumentsOverrideForTesting = [
                    "--flowtab-ui-open-switcher-search",
                    FlowTabTestLaunchOptions
                        .initialPresentationResolutionNotificationArgument,
                    resolutionRoute.notificationName.rawValue,
                    FlowTabTestLaunchOptions
                        .initialPresentationResolutionReadbackPathArgument,
                    resolutionRoute.readbackURL.path
                ]
            FlowTabTestLaunchOptions
                .environmentOverrideForTesting = [
                    FlowTabTestLaunchOptions
                        .uiTestingEnvironmentKey:
                        FlowTabTestLaunchOptions
                            .uiTestingEnvironmentValue
                ]

            let apps = searchScenarioApps()
            let expectedAppIDs = apps.map(\.id)
            let runtimeProjectionService =
                RecordingRuntimeProjectionService(
                    appSwitcherApps: apps
                )
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService:
                        runtimeProjectionService
                )
            )
            let model = controller.modelForTesting
            let presentationResolved = expectation(
                description:
                    "unmetCondition=disabledSearchLaunchResolvedAsExactAppCycle"
            )
            presentationResolved.assertForOverFulfill = true
            var resolvedEvidence:
                FlowTabUITestInitialPresentationEvidence?
            var lastObservedEvidence:
                FlowTabUITestInitialPresentationEvidence?
            let observer =
                NotificationCenter.default.addObserver(
                    forName:
                        .flowTabUITestInitialPresentationDidResolve,
                    object: controller,
                    queue: .main
                ) { notification in
                    MainActor.assumeIsolated {
                        guard let evidence =
                                FlowTabUITestInitialPresentationEvidence(
                                    notification: notification
                                )
                        else {
                            return
                        }
                        lastObservedEvidence = evidence
                        guard
                            evidence.observationGeneration > 0,
                            evidence.source == .initialReadback,
                            evidence.resolution == .presented,
                            evidence.baseline.mode == .global,
                            evidence.candidate.mode == .global,
                            evidence.candidate.itemIDs
                                == expectedAppIDs,
                            evidence.attempt?.didPresent
                                == true,
                            evidence.attempt?
                                .sessionItemIDs
                                == expectedAppIDs,
                            evidence.attempt?
                                .searchIsActiveOrPending
                                == false,
                            evidence.postPresentationReadback?
                                .itemIDs
                                == expectedAppIDs,
                            controller.isPanelPresented,
                            model.session?.apps.map(\.id)
                                == expectedAppIDs,
                            !model.isSearchActive,
                            !model
                                .pendingSearchActivationAfterFreshnessBarrier,
                            !FlowTabUITestBootstrapper
                                .isObservingInitialPresentationForTesting,
                            runtimeProjectionService
                                .searchIndexFreshnessBarrierRequestsRecorded()
                                .isEmpty
                        else {
                            return
                        }
                        resolvedEvidence = evidence
                        presentationResolved.fulfill()
                    }
                }
            defer {
                NotificationCenter.default
                    .removeObserver(observer)
                FlowTabUITestBootstrapper
                    .stopInitialUIPresentationObservation()
                controller.cancelSelectionForTesting()
                FlowTabTestLaunchOptions
                    .argumentsOverrideForTesting =
                        previousLaunchArguments
                FlowTabTestLaunchOptions
                    .environmentOverrideForTesting =
                        previousLaunchEnvironment
                try? FileManager.default.removeItem(
                    at: resolutionRoute.readbackURL
                )
            }

            XCTAssertEqual(
                FlowTabTestLaunchOptions
                    .initialPresentationResolutionRoute,
                resolutionRoute
            )

            FlowTabUITestBootstrapper
                .presentInitialUIIfNeeded(
                    panelController: controller
                )

            await fulfillment(
                of: [presentationResolved],
                timeout:
                    FlowTabPriorityCoverageWatchdogPolicy
                        .initialSearchPresentationResolution
            )

            guard let resolvedEvidence else {
                return XCTFail(
                    "Disabled Search launch evidence did not satisfy the Oracle; last=\(lastObservedEvidence?.logFields ?? "none")"
                )
            }
            XCTAssertEqual(
                resolvedEvidence.attempt?
                    .searchIsActiveOrPending,
                false
            )
            XCTAssertEqual(
                model.session?.mode,
                .appCycle
            )
            XCTAssertFalse(model.isSearchActive)
            XCTAssertFalse(
                FlowTabUITestBootstrapper
                    .isObservingInitialPresentationForTesting
            )
            XCTAssertTrue(
                runtimeProjectionService
                    .searchIndexFreshnessBarrierRequestsRecorded()
                    .isEmpty
            )
            let readback = try JSONDecoder().decode(
                FlowTabUITestInitialPresentationResolutionReadback
                    .self,
                from: Data(
                    contentsOf: resolutionRoute.readbackURL
                )
            )
            XCTAssertEqual(
                readback.schemaVersion,
                FlowTabUITestInitialPresentationResolutionReadback
                    .currentSchemaVersion
            )
            XCTAssertEqual(
                readback.observationGeneration,
                resolvedEvidence.observationGeneration
            )
            XCTAssertEqual(
                readback.candidateItemIDs,
                expectedAppIDs
            )
            XCTAssertEqual(
                readback.sessionItemIDs,
                expectedAppIDs
            )
            XCTAssertEqual(
                readback.postPresentationItemIDs,
                expectedAppIDs
            )
            XCTAssertTrue(readback.panelIsPresented)
            XCTAssertEqual(readback.sessionMode, "appCycle")
            XCTAssertFalse(readback.searchFeatureEnabled)
            XCTAssertFalse(readback.searchIsActive)
            XCTAssertFalse(
                readback.searchActivationIsPending
            )
        }
    }

    func testUITestInitialPresentationResolutionRouteRequiresAbsoluteReadbackPath() {
        let notificationArgument =
            FlowTabTestLaunchOptions
                .initialPresentationResolutionNotificationArgument
        let readbackArgument =
            FlowTabTestLaunchOptions
                .initialPresentationResolutionReadbackPathArgument
        let previousArguments =
            FlowTabTestLaunchOptions
                .argumentsOverrideForTesting
        let previousEnvironment =
            FlowTabTestLaunchOptions
                .environmentOverrideForTesting
        defer {
            FlowTabTestLaunchOptions
                .argumentsOverrideForTesting =
                    previousArguments
            FlowTabTestLaunchOptions
                .environmentOverrideForTesting =
                    previousEnvironment
        }
        FlowTabTestLaunchOptions
            .environmentOverrideForTesting = [
                FlowTabTestLaunchOptions.uiTestingEnvironmentKey:
                    FlowTabTestLaunchOptions
                        .uiTestingEnvironmentValue
            ]
        FlowTabTestLaunchOptions
            .argumentsOverrideForTesting = [
            "FlowTab",
            notificationArgument,
            "  test.initial-presentation  ",
            readbackArgument,
            "  /tmp/initial-presentation.json  "
        ]
        XCTAssertEqual(
            FlowTabTestLaunchOptions
                .initialPresentationResolutionRoute,
            FlowTabUITestInitialPresentationResolutionRoute(
                notificationName:
                    Notification.Name(
                        "test.initial-presentation"
                    ),
                readbackURL:
                    URL(
                        fileURLWithPath:
                            "/tmp/initial-presentation.json"
                    )
            )
        )
        FlowTabTestLaunchOptions
            .argumentsOverrideForTesting = [
            "FlowTab",
            notificationArgument,
            "test.initial-presentation",
            readbackArgument,
            "relative/initial-presentation.json"
        ]
        XCTAssertNil(
            FlowTabTestLaunchOptions
                .initialPresentationResolutionRoute
        )
        FlowTabTestLaunchOptions
            .argumentsOverrideForTesting = [
            "FlowTab",
            notificationArgument,
            "test.initial-presentation",
            readbackArgument,
            "/tmp/initial-presentation.json"
        ]
        FlowTabTestLaunchOptions
            .environmentOverrideForTesting = [:]
        XCTAssertNil(
            FlowTabTestLaunchOptions
                .initialPresentationResolutionRoute
        )
    }

    @MainActor
    func testUITestSearchLaunchWaitsForCommittedIndexEvidence()
        async
    {
        await withTemporarySearchPreferences(
            enabled: true,
            defaultScope: .app
        ) {
            let previousLaunchArguments =
                FlowTabTestLaunchOptions
                    .argumentsOverrideForTesting
            let previousLaunchEnvironment =
                FlowTabTestLaunchOptions
                    .environmentOverrideForTesting
            FlowTabTestLaunchOptions
                .argumentsOverrideForTesting = [
                    "--flowtab-ui-open-switcher-search"
                ]
            FlowTabTestLaunchOptions
                .environmentOverrideForTesting = [
                    FlowTabTestLaunchOptions
                        .uiTestingEnvironmentKey:
                        FlowTabTestLaunchOptions
                            .uiTestingEnvironmentValue
                ]

            let apps = searchScenarioApps()
            let expectedAppIDs = apps.map(\.id)
            let runtimeProjectionService =
                RecordingRuntimeProjectionService(
                    appSwitcherApps: apps,
                    committedSearchReadiness:
                        .missingCommittedIndex
                )
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService:
                        runtimeProjectionService
                )
            )
            var firstSearchReadinessRequestObservedBeforePresentation:
                Bool?
            runtimeProjectionService
                .setSearchIndexFreshnessBarrierRequestHandler {
                    _ in
                    MainActor.assumeIsolated {
                        guard firstSearchReadinessRequestObservedBeforePresentation
                                == nil
                        else {
                            return
                        }
                        firstSearchReadinessRequestObservedBeforePresentation =
                            FlowTabUITestBootstrapper
                                .isObservingInitialPresentationForTesting
                            && !controller.isPanelPresented
                    }
                }
            let model = controller.modelForTesting
            let presentationResolved = expectation(
                description:
                    "unmetCondition=initialSearchPresentationResolvedAfterCommittedIndex"
            )
            presentationResolved
                .assertForOverFulfill = true
            var resolvedEvidence:
                FlowTabUITestInitialPresentationEvidence?
            let observer =
                NotificationCenter.default.addObserver(
                    forName:
                        .flowTabUITestInitialPresentationDidResolve,
                    object: controller,
                    queue: .main
                ) { notification in
                    MainActor.assumeIsolated {
                        guard let evidence =
                                FlowTabUITestInitialPresentationEvidence(
                                    notification: notification
                                )
                        else {
                            return
                        }
                        resolvedEvidence = evidence
                        presentationResolved.fulfill()
                    }
                }
            defer {
                NotificationCenter.default
                    .removeObserver(observer)
                FlowTabUITestBootstrapper
                    .stopInitialUIPresentationObservation()
                controller.cancelSelectionForTesting()
                FlowTabTestLaunchOptions
                    .argumentsOverrideForTesting =
                        previousLaunchArguments
                FlowTabTestLaunchOptions
                    .environmentOverrideForTesting =
                        previousLaunchEnvironment
            }

            FlowTabUITestBootstrapper
                .presentInitialUIIfNeeded(
                    panelController: controller
                )

            XCTAssertTrue(controller.isPanelPresented)
            XCTAssertEqual(
                firstSearchReadinessRequestObservedBeforePresentation,
                true
            )
            XCTAssertEqual(
                runtimeProjectionService
                    .searchIndexFreshnessBarrierRequestsRecorded(),
                [
                    .searchFreshnessBarrier,
                    .searchFreshnessBarrier
                ]
            )
            XCTAssertEqual(
                model.session?.apps.map(\.id),
                expectedAppIDs
            )
            XCTAssertFalse(model.isSearchActive)
            XCTAssertNil(resolvedEvidence)
            XCTAssertTrue(
                FlowTabUITestBootstrapper
                    .isObservingInitialPresentationForTesting
            )

            runtimeProjectionService
                .installCommittedSearchIndex(for: apps)
            NotificationCenter.default.post(
                name:
                    .runtimeCommittedSearchIndexDidUpdate,
                object: runtimeProjectionService
            )

            await fulfillment(
                of: [presentationResolved],
                timeout:
                    FlowTabPriorityCoverageWatchdogPolicy
                        .initialSearchPresentationResolution
            )

            XCTAssertTrue(model.isSearchActive)
            XCTAssertEqual(
                resolvedEvidence?.candidate.itemIDs,
                expectedAppIDs
            )
            XCTAssertEqual(
                resolvedEvidence?.attempt?
                    .searchIsActiveOrPending,
                true
            )
            XCTAssertFalse(
                FlowTabUITestBootstrapper
                    .isObservingInitialPresentationForTesting
            )
        }
    }
}
