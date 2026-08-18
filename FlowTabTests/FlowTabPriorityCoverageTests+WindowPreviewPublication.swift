import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testLiveSwitcherModelUsesPreviewProviderResolverForTerminalPreview() async {
        let currentApp = NSRunningApplication.current
        let appID = "com.apple.Terminal"
        let windows = [
            WindowCandidate(
                id: AXWindowInspector.makeWindowID(
                    pid: currentApp.processIdentifier,
                    index: 0
                ),
                title: "Server",
                isMinimized: false,
                lastActiveAt: 30
            ),
            WindowCandidate(
                id: AXWindowInspector.makeWindowID(
                    pid: currentApp.processIdentifier,
                    index: 1
                ),
                title: "Shell",
                isMinimized: false,
                lastActiveAt: 20
            )
        ]
        let app = AppSwitchCandidate(
            id: appID,
            displayName: "Terminal",
            groupID: "terminal",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let (model, runtimeProjectionService) =
            makeAppSwitcherProjectionModel(
                app: app,
                context: context
            )
        let specialProvider =
            FakeSpecialWindowPreviewProvider(
                supportedAppID: appID,
                result: .success(
                    image: makeColorImage(
                        color: .systemGreen
                    ),
                    resolvedWindowID: nil,
                    titleBarStyle: .dark,
                    source: .special(appID: appID)
                )
            )
        let genericProvider =
            FakeGenericWindowPreviewProvider(
                result: .failure(
                    .transientSystemError
                )
            )
        model.previewProviderResolver =
            WindowPreviewProviderResolver(
                specialProviders: [specialProvider],
                genericProvider: genericProvider
            )

        XCTAssertTrue(
            model.startSession(
                triggerDirection: .forward
            )
        )
        XCTAssertTrue(
            model.autoEnterWindowLayerIfPossible()
        )
        assertPreviewProviderSessionStartedFromAppSwitcherProjection(
            runtimeProjectionService
        )

        let visibleRange = 0..<2
        let expectedCaptureGeneration =
            model.previewCaptureGeneration
        XCTAssertTrue(
            model
                .previewCaptureStatesForTesting()
                .isEmpty
        )
        XCTAssertEqual(specialProvider.callCount, 0)
        XCTAssertEqual(genericProvider.callCount, 0)
        let previewBatchPublished = expectation(
            description:
                "unmetCondition=terminalPreviewBatchPublishesBothExactImages"
        )
        previewBatchPublished.assertForOverFulfill = true
        var observedCallbackCount = 0
        var matchingPublicationCount = 0
        var lastObservedWindowIDs: [String] = []
        var lastObservedImageFlags: [Bool] = []
        var lastObservedCaptureStates: [String] = []
        model.onWindowOnlyPreviewPreparationChanged = {
            XCTAssertTrue(Thread.isMainThread)
            observedCallbackCount += 1
            let snapshot =
                model.windowPreviewSnapshotForTesting(
                    visibleRange: visibleRange
                )
            let captureStates =
                model
                    .previewCaptureStatesForTesting()
            lastObservedWindowIDs = snapshot.map(\.id)
            lastObservedImageFlags = snapshot.map(\.hasImage)
            lastObservedCaptureStates =
                captureStates
                    .values
                    .map { String(describing: $0) }
                    .sorted()
            guard
                snapshot.map(\.id) == windows.map(\.id),
                snapshot.allSatisfy(\.hasImage),
                captureStates.count == visibleRange.count,
                captureStates.values.allSatisfy({ state in
                    guard
                        case let .succeeded(
                            _,
                            generation
                        ) = state
                    else {
                        return false
                    }
                    return generation
                        == expectedCaptureGeneration
                })
            else {
                return
            }
            matchingPublicationCount += 1
            previewBatchPublished.fulfill()
        }
        defer {
            model.onWindowOnlyPreviewPreparationChanged =
                nil
            model.cancelSelection()
        }

        _ = model.windowPreviewSnapshotForTesting(
            visibleRange: visibleRange
        )
        await fulfillment(
            of: [previewBatchPublished],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .windowPreviewEventDelivery
        )

        let completedSnapshot =
            model.windowPreviewSnapshotForTesting(
                visibleRange: visibleRange
            )
        XCTAssertEqual(
            observedCallbackCount,
            1,
            "unmetCondition=singlePreviewPublication finalWindowIDs=\(lastObservedWindowIDs) finalImageFlags=\(lastObservedImageFlags) finalCaptureStates=\(lastObservedCaptureStates)"
        )
        XCTAssertEqual(matchingPublicationCount, 1)
        XCTAssertEqual(
            completedSnapshot.map(\.id),
            windows.map(\.id)
        )
        XCTAssertTrue(
            completedSnapshot.allSatisfy(\.hasImage)
        )
        XCTAssertEqual(specialProvider.callCount, 2)
        XCTAssertEqual(genericProvider.callCount, 0)
    }

    @MainActor
    func testLiveSwitcherModelUsesFallbackWhenTerminalProviderFails() async {
        let currentApp = NSRunningApplication.current
        let appID = "com.apple.Terminal"
        let windows = [
            WindowCandidate(
                id: AXWindowInspector.makeWindowID(
                    pid: currentApp.processIdentifier,
                    index: 0
                ),
                title: "Server",
                isMinimized: false,
                lastActiveAt: 30
            ),
            WindowCandidate(
                id: AXWindowInspector.makeWindowID(
                    pid: currentApp.processIdentifier,
                    index: 1
                ),
                title: "Shell",
                isMinimized: false,
                lastActiveAt: 20
            )
        ]
        let app = AppSwitchCandidate(
            id: appID,
            displayName: "Terminal",
            groupID: "terminal",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let (model, runtimeProjectionService) =
            makeAppSwitcherProjectionModel(
                app: app,
                context: context
            )
        let specialProvider =
            FakeSpecialWindowPreviewProvider(
                supportedAppID: appID,
                result: .failure(
                    .specialProviderUnavailable
                )
            )
        let genericProvider =
            FakeGenericWindowPreviewProvider(
                result: .success(
                    image: makeColorImage(
                        color: .systemRed
                    ),
                    resolvedWindowID: 24_002,
                    titleBarStyle: nil,
                    source: .genericScreenshot
                )
            )
        model.previewProviderResolver =
            WindowPreviewProviderResolver(
                specialProviders: [specialProvider],
                genericProvider: genericProvider
            )

        XCTAssertTrue(
            model.startSession(
                triggerDirection: .forward
            )
        )
        XCTAssertTrue(
            model.autoEnterWindowLayerIfPossible()
        )
        assertPreviewProviderSessionStartedFromAppSwitcherProjection(
            runtimeProjectionService
        )

        let visibleRange = 0..<1
        let expectedRetryGeneration =
            model.previewCaptureGeneration + 1
        XCTAssertTrue(
            model
                .previewCaptureStatesForTesting()
                .isEmpty
        )
        XCTAssertEqual(specialProvider.callCount, 0)
        XCTAssertEqual(genericProvider.callCount, 0)
        let previewFailurePublished = expectation(
            description:
                "unmetCondition=terminalPreviewBatchPublishesExactProviderFailure"
        )
        previewFailurePublished
            .assertForOverFulfill = true
        var observedCallbackCount = 0
        var matchingPublicationCount = 0
        var lastObservedWindowIDs: [String] = []
        var lastObservedImageFlags: [Bool] = []
        var lastObservedCaptureStates: [String] = []
        model.onWindowOnlyPreviewPreparationChanged = {
            XCTAssertTrue(Thread.isMainThread)
            observedCallbackCount += 1
            let snapshot =
                model.windowPreviewSnapshotForTesting(
                    visibleRange: visibleRange
                )
            let captureStates =
                model
                    .previewCaptureStatesForTesting()
            lastObservedWindowIDs = snapshot.map(\.id)
            lastObservedImageFlags = snapshot.map(\.hasImage)
            lastObservedCaptureStates =
                captureStates
                    .values
                    .map { String(describing: $0) }
                    .sorted()
            guard
                snapshot.map(\.id)
                    == Array(windows.prefix(visibleRange.count))
                        .map(\.id),
                snapshot.allSatisfy({ !$0.hasImage }),
                specialProvider.callCount == 1,
                genericProvider.callCount == 0,
                captureStates.count == visibleRange.count,
                case let .failed(
                    reason,
                    retryAfterGeneration
                )? = captureStates.values.first,
                reason == .specialProviderUnavailable,
                retryAfterGeneration
                    == expectedRetryGeneration
            else {
                return
            }
            matchingPublicationCount += 1
            previewFailurePublished.fulfill()
        }
        defer {
            model.onWindowOnlyPreviewPreparationChanged =
                nil
            model.cancelSelection()
        }

        _ = model.windowPreviewSnapshotForTesting(
            visibleRange: visibleRange
        )
        await fulfillment(
            of: [previewFailurePublished],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .windowPreviewEventDelivery
        )

        let completedSnapshot =
            model.windowPreviewSnapshotForTesting(
                visibleRange: visibleRange
            )
        XCTAssertEqual(
            observedCallbackCount,
            1,
            "unmetCondition=singlePreviewFailurePublication finalWindowIDs=\(lastObservedWindowIDs) finalImageFlags=\(lastObservedImageFlags) finalCaptureStates=\(lastObservedCaptureStates)"
        )
        XCTAssertEqual(matchingPublicationCount, 1)
        XCTAssertEqual(completedSnapshot.count, 1)
        XCTAssertFalse(completedSnapshot[0].hasImage)
        XCTAssertEqual(specialProvider.callCount, 1)
        XCTAssertEqual(genericProvider.callCount, 0)
        guard
            case let .failed(
                reason,
                retryAfterGeneration?
            ) =
                model
                    .previewCaptureStatesForTesting()
                    .values.first
        else {
            return XCTFail(
                "Expected terminal provider failure state"
            )
        }
        XCTAssertEqual(
            reason,
            .specialProviderUnavailable
        )
        XCTAssertEqual(
            retryAfterGeneration,
            expectedRetryGeneration
        )
    }
}
