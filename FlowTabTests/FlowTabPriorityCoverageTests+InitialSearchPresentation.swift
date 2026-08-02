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
