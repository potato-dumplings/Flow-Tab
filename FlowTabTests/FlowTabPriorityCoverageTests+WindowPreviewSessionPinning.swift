import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testLiveSwitcherModelStandardWindowPreviewRequestsVisiblePageBeforeDeferredPreheat() async {
        let model = LiveSwitcherModel()
        model.backgroundFullSnapshotRefreshEnabled = false
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
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
        model.fastAppSnapshotProviderOverride = {
            RuntimeSnapshot(apps: [app], contextsByID: [appID: context])
        }

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
    func testLiveSwitcherModelPinnedVisiblePreviewSurvivesCacheEvictionUntilSessionEnds() {
        let model = LiveSwitcherModel()
        model.backgroundFullSnapshotRefreshEnabled = false
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
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
        model.fastAppSnapshotProviderOverride = {
            RuntimeSnapshot(apps: [app], contextsByID: [appID: context])
        }

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

        let restartedSnapshot = model.windowPreviewSnapshotForTesting(visibleRange: visibleRange)
        XCTAssertEqual(restartedSnapshot.count, visibleRange.count)
        XCTAssertTrue(restartedSnapshot.allSatisfy { !$0.hasImage })
        XCTAssertEqual(captureCallCount, visibleRange.count * 2)
    }

    @MainActor
    func testLiveSwitcherModelVisiblePageCanRecaptureDeferredPreviewAfterCacheEviction() async {
        let model = LiveSwitcherModel()
        model.backgroundFullSnapshotRefreshEnabled = false
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
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
        model.fastAppSnapshotProviderOverride = {
            RuntimeSnapshot(apps: [app], contextsByID: [appID: context])
        }

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
}
