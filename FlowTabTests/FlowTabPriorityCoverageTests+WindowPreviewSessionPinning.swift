import AppKit
import Combine
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testLiveSwitcherModelStandardWindowPreviewRequestsVisiblePageBeforeDeferredPreheat() async {
        let currentApp = NSRunningApplication.current
        let appID = "com.flowtab.tests.preview-preheat"
        let windows = (0..<20).map { index in
            WindowCandidate(
                id: String(format: "preview-window-%02d", index),
                title: String(format: "Preview Window %02d", index),
                isMinimized: false,
                lastActiveAt: TimeInterval(1_000 - index)
            )
        }
        let app = AppSwitchCandidate(
            id: appID,
            displayName: currentApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 1_000,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let (model, runtimeProjectionService) = makeAppSwitcherProjectionModel(app: app, context: context)
        model.runtimeProjectionMaintenanceEnabled = false

        let allCapturesFinished = expectation(description: "deferred previews captured after visible page")
        var capturedTitles: [String] = []
        model.previewCaptureOverride = { _, _, title, _ in
            capturedTitles.append(title ?? "")
            if capturedTitles.count == windows.count {
                allCapturesFinished.fulfill()
            }
            return (
                image: self.makeColorImage(color: .systemBlue),
                resolvedWindowID: CGWindowID(capturedTitles.count),
                titleBarStyle: nil
            )
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.autoEnterWindowLayerIfPossible())
        XCTAssertEqual(runtimeProjectionService.snapshotRequestCount(), 0)
        XCTAssertEqual(runtimeProjectionService.lightweightSnapshotRequestCount(), 0)
        XCTAssertTrue(model.previewCaptureAttemptedKeys.isEmpty)

        let visibleRange = 0..<10
        let firstPageItems = model.windowPreviewItems(visibleRange: visibleRange)

        XCTAssertEqual(firstPageItems.map(\.id), windows[visibleRange].map(\.id))
        XCTAssertTrue(firstPageItems.allSatisfy { $0.image != nil })
        XCTAssertEqual(capturedTitles, windows[visibleRange].map(\.title))

        await fulfillment(of: [allCapturesFinished], timeout: 1.0)
        XCTAssertEqual(capturedTitles, windows.map(\.title))
    }

    @MainActor
    func testLiveSwitcherModelLargeWindowPreviewBatchStaysBoundedToVisiblePageAndProviderPolicy() async {
        let currentApp = NSRunningApplication.current
        let appID = "com.flowtab.tests.large-preview"
        let windows = (0..<1_000).map { index in
            WindowCandidate(
                id: String(format: "large-preview-window-%04d", index),
                title: String(format: "Large Preview Window %04d", index),
                isMinimized: false,
                lastActiveAt: TimeInterval(10_000 - index)
            )
        }
        let app = AppSwitchCandidate(
            id: appID,
            displayName: currentApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 10_000,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let (model, runtimeProjectionService) = makeAppSwitcherProjectionModel(app: app, context: context)
        model.runtimeProjectionMaintenanceEnabled = false

        let visibleBatchStarted = expectation(description: "large visible preview batch started")
        let batchStateLock = NSLock()
        var batchRequestCounts: [Int] = []
        model.previewCaptureBatchOutcomeOverride = { requests in
            batchStateLock.lock()
            batchRequestCounts.append(requests.count)
            batchStateLock.unlock()
            visibleBatchStarted.fulfill()
            return Array(repeating: .failure(.transientSystemError), count: requests.count)
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.autoEnterWindowLayerIfPossible())
        XCTAssertEqual(runtimeProjectionService.snapshotRequestCount(), 0)
        XCTAssertEqual(runtimeProjectionService.lightweightSnapshotRequestCount(), 0)

        let visibleRange = 240..<256
        let initialSnapshot = model.windowPreviewSnapshotForTesting(visibleRange: visibleRange)
        XCTAssertTrue(initialSnapshot.isEmpty)

        await fulfillment(of: [visibleBatchStarted], timeout: 1.0)
        batchStateLock.lock()
        XCTAssertEqual(batchRequestCounts, [visibleRange.count])
        batchStateLock.unlock()
        XCTAssertEqual(
            RuntimeWindowPreviewProvider.captureWorkerCountForTesting(requestCount: windows.count),
            RuntimeWindowPreviewProvider.captureConcurrencyPolicyForTesting().maxConcurrentCaptures
        )
    }

    @MainActor
    func testLiveSwitcherModelPinnedVisiblePreviewSurvivesCacheEvictionUntilSessionEnds() {
        let currentApp = NSRunningApplication.current
        let appID = "com.flowtab.tests.preview-session-pinning"
        let windows = (0..<12).map { index in
            WindowCandidate(
                id: String(format: "pinned-preview-window-%02d", index),
                title: String(format: "Pinned Preview Window %02d", index),
                isMinimized: false,
                lastActiveAt: TimeInterval(1_000 - index)
            )
        }
        let app = AppSwitchCandidate(
            id: appID,
            displayName: currentApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 1_000,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let (model, runtimeProjectionService) = makeAppSwitcherProjectionModel(app: app, context: context)
        model.runtimeProjectionMaintenanceEnabled = false

        enum PreviewPhase {
            case available
            case unavailable
        }

        var previewPhase: PreviewPhase = .available
        var captureCallCount = 0
        model.previewCaptureOverride = { _, _, _, _ in
            captureCallCount += 1
            guard previewPhase == .available else { return nil }
            return (
                image: self.makeColorImage(color: .systemGreen),
                resolvedWindowID: CGWindowID(captureCallCount),
                titleBarStyle: .light
            )
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.autoEnterWindowLayerIfPossible())
        XCTAssertEqual(runtimeProjectionService.snapshotRequestCount(), 0)
        XCTAssertEqual(runtimeProjectionService.lightweightSnapshotRequestCount(), 0)

        let visibleRange = 0..<6
        let initialSnapshot = model.windowPreviewSnapshotForTesting(visibleRange: visibleRange)
        XCTAssertEqual(initialSnapshot.count, visibleRange.count)
        XCTAssertTrue(initialSnapshot.allSatisfy(\.hasImage))
        XCTAssertEqual(captureCallCount, visibleRange.count)

        model.previewImageCache.removeAll()

        let afterCacheEviction = model.windowPreviewSnapshotForTesting(visibleRange: visibleRange)
        XCTAssertEqual(afterCacheEviction.count, visibleRange.count)
        XCTAssertTrue(afterCacheEviction.allSatisfy(\.hasImage))
        XCTAssertEqual(captureCallCount, visibleRange.count)

        model.cancelSelection()
        previewPhase = .unavailable

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.autoEnterWindowLayerIfPossible())
        XCTAssertEqual(runtimeProjectionService.snapshotRequestCount(), 0)
        XCTAssertEqual(runtimeProjectionService.lightweightSnapshotRequestCount(), 0)

        let restartedSnapshot = model.windowPreviewSnapshotForTesting(visibleRange: visibleRange)
        XCTAssertEqual(restartedSnapshot.count, visibleRange.count)
        XCTAssertTrue(restartedSnapshot.allSatisfy { !$0.hasImage })
        XCTAssertEqual(captureCallCount, visibleRange.count * 2)
    }

    @MainActor
    func testLiveSwitcherModelVisiblePageCanRecaptureDeferredPreviewAfterCacheEviction() async {
        let currentApp = NSRunningApplication.current
        let appID = "com.flowtab.tests.preview-deferred-recapture"
        let windows = (0..<12).map { index in
            WindowCandidate(
                id: String(format: "deferred-preview-window-%02d", index),
                title: String(format: "Deferred Preview Window %02d", index),
                isMinimized: false,
                lastActiveAt: TimeInterval(1_000 - index)
            )
        }
        let app = AppSwitchCandidate(
            id: appID,
            displayName: currentApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 1_000,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let (model, runtimeProjectionService) = makeAppSwitcherProjectionModel(app: app, context: context)
        model.runtimeProjectionMaintenanceEnabled = false

        let deferredCapturesFinished = expectation(description: "deferred previews captured")
        var captureCallCount = 0
        model.previewCaptureOverride = { _, _, _, _ in
            captureCallCount += 1
            if captureCallCount == windows.count {
                deferredCapturesFinished.fulfill()
            }
            return (
                image: self.makeColorImage(color: .systemOrange),
                resolvedWindowID: CGWindowID(captureCallCount),
                titleBarStyle: nil
            )
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.autoEnterWindowLayerIfPossible())
        XCTAssertEqual(runtimeProjectionService.snapshotRequestCount(), 0)
        XCTAssertEqual(runtimeProjectionService.lightweightSnapshotRequestCount(), 0)

        let firstVisibleRange = 0..<6
        let firstPage = model.windowPreviewSnapshotForTesting(visibleRange: firstVisibleRange)
        XCTAssertTrue(firstPage.allSatisfy(\.hasImage))
        XCTAssertEqual(captureCallCount, firstVisibleRange.count)

        await fulfillment(of: [deferredCapturesFinished], timeout: 1.0)
        XCTAssertEqual(captureCallCount, windows.count)

        model.previewImageCache.removeAll()

        let secondVisibleRange = 6..<12
        let secondPage = model.windowPreviewSnapshotForTesting(visibleRange: secondVisibleRange)
        XCTAssertTrue(secondPage.allSatisfy(\.hasImage))
        XCTAssertEqual(captureCallCount, windows.count + secondVisibleRange.count)
    }

    @MainActor
    func testLiveSwitcherModelRuntimeVisiblePreviewWaitsForBatchBeforeShowingPage() async {
        let currentApp = NSRunningApplication.current
        let appID = "com.flowtab.tests.preview-visible-batch"
        let windows = (0..<6).map { index in
            WindowCandidate(
                id: String(format: "batched-preview-window-%02d", index),
                title: String(format: "Batched Preview Window %02d", index),
                isMinimized: false,
                lastActiveAt: TimeInterval(1_000 - index)
            )
        }
        let app = AppSwitchCandidate(
            id: appID,
            displayName: currentApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 1_000,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let (model, runtimeProjectionService) = makeAppSwitcherProjectionModel(app: app, context: context)
        model.runtimeProjectionMaintenanceEnabled = false

        let batchStarted = expectation(description: "visible preview batch started")
        let batchReleased = DispatchSemaphore(value: 0)
        let batchStateLock = NSLock()
        var batchCallCount = 0
        var batchRequestTitles: [String] = []
        model.previewCaptureBatchOverride = { requests in
            batchStateLock.lock()
            batchCallCount += 1
            batchRequestTitles = requests.map { $0.preferredTitle ?? "" }
            batchStateLock.unlock()
            batchStarted.fulfill()
            batchReleased.wait()
            return requests.enumerated().map { index, _ in
                RuntimeWindowPreviewProvider.CaptureResult(
                    image: self.makeColorImage(color: .systemPurple),
                    resolvedWindowID: CGWindowID(index + 1),
                    titleBarStyle: nil
                )
            }
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.autoEnterWindowLayerIfPossible())
        XCTAssertEqual(runtimeProjectionService.snapshotRequestCount(), 0)
        XCTAssertEqual(runtimeProjectionService.lightweightSnapshotRequestCount(), 0)

        let visibleRange = 0..<6
        let initialSnapshot = model.windowPreviewSnapshotForTesting(visibleRange: visibleRange)
        XCTAssertTrue(initialSnapshot.isEmpty)

        await fulfillment(of: [batchStarted], timeout: 1.0)
        batchStateLock.lock()
        XCTAssertEqual(batchCallCount, 1)
        XCTAssertEqual(batchRequestTitles, windows.map(\.title))
        batchStateLock.unlock()

        let batchPublished = expectation(description: "visible preview batch published")
        var publishCount = 0
        var cancellables: Set<AnyCancellable> = []
        model.objectWillChange.sink {
            publishCount += 1
            if publishCount == 1 {
                batchPublished.fulfill()
            }
        }.store(in: &cancellables)

        batchReleased.signal()
        await fulfillment(of: [batchPublished], timeout: 1.0)
        XCTAssertEqual(publishCount, 1)

        let completedSnapshot = model.windowPreviewSnapshotForTesting(visibleRange: visibleRange)
        XCTAssertEqual(completedSnapshot.count, visibleRange.count)
        XCTAssertTrue(completedSnapshot.allSatisfy(\.hasImage))
        batchStateLock.lock()
        XCTAssertEqual(batchCallCount, 1)
        batchStateLock.unlock()
        XCTAssertEqual(cancellables.count, 1)
    }

    @MainActor
    func testLiveSwitcherModelRuntimeVisiblePreviewShowsFallbackAfterBatchFailure() async {
        let currentApp = NSRunningApplication.current
        let appID = "com.flowtab.tests.preview-visible-batch-failure"
        let windows = (0..<4).map { index in
            WindowCandidate(
                id: String(format: "failed-batched-preview-window-%02d", index),
                title: String(format: "Failed Batched Preview Window %02d", index),
                isMinimized: false,
                lastActiveAt: TimeInterval(1_000 - index)
            )
        }
        let app = AppSwitchCandidate(
            id: appID,
            displayName: currentApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 1_000,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let (model, runtimeProjectionService) = makeAppSwitcherProjectionModel(app: app, context: context)
        model.runtimeProjectionMaintenanceEnabled = false

        let batchStarted = expectation(description: "failed visible preview batch started")
        let batchReleased = DispatchSemaphore(value: 0)
        var batchCallCount = 0
        model.previewCaptureBatchOverride = { requests in
            batchCallCount += 1
            batchStarted.fulfill()
            batchReleased.wait()
            return Array(repeating: nil, count: requests.count)
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.autoEnterWindowLayerIfPossible())
        XCTAssertEqual(runtimeProjectionService.snapshotRequestCount(), 0)
        XCTAssertEqual(runtimeProjectionService.lightweightSnapshotRequestCount(), 0)

        let visibleRange = 0..<4
        let initialSnapshot = model.windowPreviewSnapshotForTesting(visibleRange: visibleRange)
        XCTAssertTrue(initialSnapshot.isEmpty)
        await fulfillment(of: [batchStarted], timeout: 1.0)

        let batchPublished = expectation(description: "failed visible preview batch published")
        var publishCount = 0
        var cancellables: Set<AnyCancellable> = []
        model.objectWillChange.sink {
            publishCount += 1
            if publishCount == 1 {
                batchPublished.fulfill()
            }
        }.store(in: &cancellables)

        batchReleased.signal()
        await fulfillment(of: [batchPublished], timeout: 1.0)
        XCTAssertEqual(publishCount, 1)

        let completedSnapshot = model.windowPreviewSnapshotForTesting(visibleRange: visibleRange)
        XCTAssertEqual(completedSnapshot.count, visibleRange.count)
        XCTAssertTrue(completedSnapshot.allSatisfy { !$0.hasImage })
        XCTAssertEqual(batchCallCount, 1)
        XCTAssertEqual(cancellables.count, 1)
    }

    @MainActor
    func testLiveSwitcherModelPreviewBatchFailureUsesProviderReasonForRetryState() async {
        let currentApp = NSRunningApplication.current
        let appID = "com.flowtab.tests.preview-provider-failure"
        let windows = (0..<3).map { index in
            WindowCandidate(
                id: String(format: "provider-failed-preview-window-%02d", index),
                title: String(format: "Provider Failed Preview Window %02d", index),
                isMinimized: false,
                lastActiveAt: TimeInterval(1_000 - index)
            )
        }
        let app = AppSwitchCandidate(
            id: appID,
            displayName: currentApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 1_000,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let (model, runtimeProjectionService) = makeAppSwitcherProjectionModel(app: app, context: context)
        model.runtimeProjectionMaintenanceEnabled = false

        var batchCallCount = 0
        model.previewCaptureBatchOutcomeOverride = { requests in
            batchCallCount += 1
            return Array(repeating: .failure(.permissionDenied), count: requests.count)
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.autoEnterWindowLayerIfPossible())
        XCTAssertEqual(runtimeProjectionService.snapshotRequestCount(), 0)
        XCTAssertEqual(runtimeProjectionService.lightweightSnapshotRequestCount(), 0)

        let visibleRange = 0..<3
        let batchPublished = expectation(description: "provider failure preview batch published")
        var publishCount = 0
        var cancellables: Set<AnyCancellable> = []
        model.objectWillChange.sink {
            publishCount += 1
            if publishCount == 1 {
                batchPublished.fulfill()
            }
        }.store(in: &cancellables)

        let initialSnapshot = model.windowPreviewSnapshotForTesting(visibleRange: visibleRange)
        XCTAssertTrue(initialSnapshot.isEmpty)

        await fulfillment(of: [batchPublished], timeout: 1.0)

        let completedSnapshot = model.windowPreviewSnapshotForTesting(visibleRange: visibleRange)
        XCTAssertEqual(completedSnapshot.count, visibleRange.count)
        XCTAssertTrue(completedSnapshot.allSatisfy { !$0.hasImage })
        XCTAssertEqual(batchCallCount, 1)

        let failedStates = model.previewCaptureStatesForTesting().values.compactMap { state -> (PreviewCaptureFailureReason, UInt64?)? in
            guard case let .failed(reason, retryAfterGeneration) = state else { return nil }
            return (reason, retryAfterGeneration)
        }
        XCTAssertEqual(failedStates.count, windows.count)
        XCTAssertTrue(failedStates.allSatisfy { $0.0 == .permissionDenied })
        XCTAssertTrue(failedStates.allSatisfy { $0.1 == nil })

        _ = model.windowPreviewSnapshotForTesting(visibleRange: visibleRange)
        XCTAssertEqual(batchCallCount, 1)
        XCTAssertEqual(cancellables.count, 1)
    }
}
