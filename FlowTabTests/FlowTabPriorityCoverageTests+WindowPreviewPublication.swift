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
        let previewBatchPublished = expectation(
            description:
                "terminal preview batch publishes both exact images"
        )
        previewBatchPublished.assertForOverFulfill = true
        var didObserveCompletedBatch = false
        model.onWindowOnlyPreviewPreparationChanged = {
            guard !didObserveCompletedBatch else { return }
            let snapshot =
                model.windowPreviewSnapshotForTesting(
                    visibleRange: visibleRange
                )
            guard
                snapshot.count == visibleRange.count,
                snapshot.allSatisfy(\.hasImage)
            else {
                return
            }
            didObserveCompletedBatch = true
            previewBatchPublished.fulfill()
        }
        defer {
            model.onWindowOnlyPreviewPreparationChanged =
                nil
        }

        _ = model.windowPreviewSnapshotForTesting(
            visibleRange: visibleRange
        )
        await fulfillment(
            of: [previewBatchPublished],
            timeout: 1
        )

        let completedSnapshot =
            model.windowPreviewSnapshotForTesting(
                visibleRange: visibleRange
            )
        XCTAssertEqual(
            completedSnapshot.count,
            visibleRange.count
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
        let previewFailurePublished = expectation(
            description:
                "terminal preview batch publishes exact provider failure"
        )
        previewFailurePublished
            .assertForOverFulfill = true
        var didObserveFailure = false
        model.onWindowOnlyPreviewPreparationChanged = {
            guard
                !didObserveFailure,
                specialProvider.callCount == 1,
                case let .failed(
                    reason,
                    retryAfterGeneration
                )? =
                    model
                        .previewCaptureStatesForTesting()
                        .values.first,
                reason == .specialProviderUnavailable,
                retryAfterGeneration
                    == expectedRetryGeneration
            else {
                return
            }
            didObserveFailure = true
            previewFailurePublished.fulfill()
        }
        defer {
            model.onWindowOnlyPreviewPreparationChanged =
                nil
        }

        _ = model.windowPreviewSnapshotForTesting(
            visibleRange: visibleRange
        )
        await fulfillment(
            of: [previewFailurePublished],
            timeout: 1
        )

        let completedSnapshot =
            model.windowPreviewSnapshotForTesting(
                visibleRange: visibleRange
            )
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
