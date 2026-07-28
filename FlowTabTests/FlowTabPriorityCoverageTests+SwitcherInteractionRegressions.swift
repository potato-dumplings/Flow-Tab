import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testInAppHotkeyFirstPhysicalPressAdvancesToNextWindow() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "first-press-current", title: "Current", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "first-press-next", title: "Next", isMinimized: false, lastActiveAt: 20),
        ]
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: makeCurrentAppWindowProjectionService(
                    appID: appID,
                    runningApp: currentApp,
                    windows: windows
                )
            )
        )
        controller.panelVisibilityOverride = false
        controller.hideNonPanelWindowsOverride = {}
        let hotkeyInput = ManualHotkeyInputSource()
        hotkeyInput.register(on: controller, for: .inAppWindowSwitcher)

        hotkeyInput.emit(
            phase: .pressed,
            to: controller,
            for: .inAppWindowSwitcher
        )

        XCTAssertEqual(controller.modelForTesting.session?.selectedWindow?.id, "first-press-next")
        controller.inAppPrimaryModifierPressedOverride = false
        controller.inAppMainKeyPressedOverride = false
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelRemainsPresentedDuringCommittedWindowActivation() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "activation-current", title: "Current", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "activation-target", title: "Target", isMinimized: false, lastActiveAt: 20),
        ]
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: makeCurrentAppWindowProjectionService(
                    appID: appID,
                    runningApp: currentApp,
                    windows: windows
                )
            )
        )
        var panelWasPresentedDuringActivation = false
        controller.modelForTesting.activationOverride = { _, _ in
            panelWasPresentedDuringActivation = controller.isPanelPresented
        }

        XCTAssertTrue(controller.beginInAppWindowHotkeySessionForTesting())
        controller.finishSelection()

        XCTAssertTrue(panelWasPresentedDuringActivation)
        XCTAssertFalse(controller.isPanelPresented)
    }

    @MainActor
    func testWindowOnlyPanelUsesResponsiveContentBounds() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = (0..<8).map { index in
            WindowCandidate(
                id: "responsive-window-\(index)",
                title: "Window \(index)",
                isMinimized: false,
                lastActiveAt: TimeInterval(100 - index)
            )
        }
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: makeCurrentAppWindowProjectionService(
                    appID: appID,
                    runningApp: currentApp,
                    windows: windows
                )
            )
        )

        XCTAssertTrue(controller.beginInAppWindowHotkeySessionForTesting())
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_728, height: 1_117)
        controller.updatePanelSizeForTesting(visibleFrame: visibleFrame)

        let size = controller.panelContentSizeForTesting
        XCTAssertEqual(size.width, visibleFrame.width * 0.82, accuracy: 1)
        XCTAssertEqual(size.height, visibleFrame.height * 0.75, accuracy: 1)
        XCTAssertGreaterThanOrEqual(size.width, 640)
        XCTAssertGreaterThanOrEqual(size.height, 360)
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testInAppWindowSessionPrewarmsPreviewsBeforeFirstPanelFrame() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "prewarm-current", title: "Current", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "prewarm-next", title: "Next", isMinimized: false, lastActiveAt: 20),
        ]
        let model = LiveSwitcherModel(
            runtimeProjectionService: makeCurrentAppWindowProjectionService(
                appID: appID,
                runningApp: currentApp,
                windows: windows
            )
        )
        var capturedTitles: [String] = []
        model.previewCaptureOverride = { _, _, title, _ in
            capturedTitles.append(title ?? "")
            return (
                image: self.makeColorImage(color: .systemBlue),
                resolvedWindowID: CGWindowID(capturedTitles.count),
                titleBarStyle: nil
            )
        }
        let controller = SwitcherPanelController(model: model)

        XCTAssertTrue(controller.beginInAppWindowHotkeySessionForTesting())

        XCTAssertEqual(Set(capturedTitles), Set(windows.map(\.title)))
        XCTAssertEqual(capturedTitles.count, windows.count)
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testInAppWindowPanelRevealsAfterAsyncPreviewBatchCompletes() async {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "async-current", title: "Current", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "async-next", title: "Next", isMinimized: false, lastActiveAt: 20),
        ]
        let model = LiveSwitcherModel(
            runtimeProjectionService: makeCurrentAppWindowProjectionService(
                appID: appID,
                runningApp: currentApp,
                windows: windows
            )
        )
        let capturedImage = makeColorImage(color: .systemPurple)
        model.previewCaptureBatchOverride = { requests in
            Thread.sleep(forTimeInterval: 0.08)
            return requests.enumerated().map { index, _ in
                RuntimeWindowPreviewProvider.CaptureResult(
                    image: capturedImage,
                    resolvedWindowID: CGWindowID(index + 1),
                    titleBarStyle: nil
                )
            }
        }
        let controller = SwitcherPanelController(model: model)
        controller.setModifierReleaseConfirmationSuppressedForTesting(true)
        controller.appIsActiveOverride = true
        controller.hideNonPanelWindowsOverride = {}

        XCTAssertTrue(controller.presentInAppWindowHotkeySessionForTesting())
        XCTAssertEqual(controller.panel.alphaValue, 0, accuracy: 0.001)
        let didReveal = await waitUntil(
            "window-only panel reveals after preview batch",
            pollIntervalNanoseconds: 5_000_000,
            predicate: { controller.panel.alphaValue == 1 }
        )
        XCTAssertTrue(didReveal)
        XCTAssertTrue(
            model.windowPreviewSnapshotForTesting().allSatisfy(\.hasImage)
        )
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testProjectionRefreshPreservesVisibleAppOrderDuringDelayedWindowLayerEntry() {
        let currentApp = NSRunningApplication.current
        let appIDs = [
            "com.flowtab.tests.order.mail",
            "com.flowtab.tests.order.browser",
            "com.flowtab.tests.order.notes",
        ]
        let initialApps = appIDs.enumerated().map { index, appID in
            AppSwitchCandidate(
                id: appID,
                displayName: ["Mail", "Browser", "Notes"][index],
                groupID: "order-\(index)",
                lastActiveAt: TimeInterval(300 - index),
                windows: [
                    WindowCandidate(
                        id: "order-window-\(index)",
                        title: "Window \(index)",
                        isMinimized: false,
                        lastActiveAt: TimeInterval(300 - index)
                    )
                ]
            )
        }
        let initialContexts = Dictionary(
            uniqueKeysWithValues: initialApps.map { app in
                (
                    app.id,
                    makeRuntimeAppContext(
                        appID: app.id,
                        runningApp: currentApp,
                        windows: app.windows
                    )
                )
            }
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherApps: initialApps,
            contextsByID: initialContexts
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        let visibleOrder = model.session?.apps.map(\.id)
        let selectedAppID = model.session?.selectedApp.id
        let refreshedApps = initialApps.reversed().map { app in
            AppSwitchCandidate(
                id: app.id,
                displayName: "\(app.displayName) Updated",
                groupID: app.groupID,
                lastActiveAt: app.lastActiveAt + 1_000,
                windows: app.windows
            )
        }
        runtimeProjectionService.installAppSwitcherProjection(
            apps: refreshedApps,
            contextsByID: initialContexts,
            generatedAt: 20
        )

        XCTAssertTrue(model.handleAppSwitcherProjectionDidUpdate())
        XCTAssertEqual(model.session?.apps.map(\.id), visibleOrder)
        XCTAssertEqual(model.session?.selectedApp.id, selectedAppID)
        XCTAssertTrue(model.session?.apps.allSatisfy { $0.displayName.hasSuffix(" Updated") } == true)
    }

    @MainActor
    func testDelayedWindowLayerEntryPrewarmsBoundedVisiblePage() {
        let currentApp = NSRunningApplication.current
        let appID = "com.flowtab.tests.auto-enter-prewarm"
        let windows = (0..<20).map { index in
            WindowCandidate(
                id: "auto-enter-window-\(index)",
                title: "Auto Enter Window \(index)",
                isMinimized: false,
                lastActiveAt: TimeInterval(1_000 - index)
            )
        }
        let app = AppSwitchCandidate(
            id: appID,
            displayName: "Auto Enter",
            groupID: "auto-enter",
            lastActiveAt: 1_000,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let model = LiveSwitcherModel(
            runtimeProjectionService: RecordingRuntimeProjectionService(
                appSwitcherApps: [app],
                contextsByID: [appID: context]
            )
        )
        var captureCallCount = 0
        model.previewCaptureOverride = { _, _, _, _ in
            captureCallCount += 1
            return (
                image: self.makeColorImage(color: .systemIndigo),
                resolvedWindowID: CGWindowID(captureCallCount),
                titleBarStyle: nil
            )
        }
        let controller = SwitcherPanelController(model: model)
        controller.windowLayerPresentationDelayOverride = 10

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.scheduleDelayedWindowLayerEntryForTesting()

        XCTAssertEqual(model.session?.mode, .appCycle)
        XCTAssertGreaterThan(captureCallCount, 0)
        XCTAssertLessThanOrEqual(captureCallCount, SwitcherWindowPreviewPaging.maximumVisibleSlots)
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testDelayedWindowLayerEntryIgnoresStaleTimerGeneration() {
        let currentApp = NSRunningApplication.current
        let appID = "com.flowtab.tests.auto-enter-generation"
        let windows = [
            WindowCandidate(id: "generation-1", title: "One", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "generation-2", title: "Two", isMinimized: false, lastActiveAt: 10),
        ]
        let app = AppSwitchCandidate(
            id: appID,
            displayName: "Timer Generation",
            groupID: "timer-generation",
            lastActiveAt: 20,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let model = LiveSwitcherModel(
            runtimeProjectionService: RecordingRuntimeProjectionService(
                appSwitcherApps: [app],
                contextsByID: [appID: context]
            )
        )
        model.previewCaptureOverride = { _, _, _, _ in nil }
        let controller = SwitcherPanelController(model: model)
        controller.windowLayerPresentationDelayOverride = 10

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.scheduleDelayedWindowLayerEntryForTesting()
        let staleGeneration = controller.delayedWindowLayerTimerGeneration

        controller.scheduleDelayedWindowLayerEntryForTesting()
        let currentGeneration = controller.delayedWindowLayerTimerGeneration
        XCTAssertGreaterThan(currentGeneration, staleGeneration)

        controller.enterDelayedWindowLayerIfReady(
            reason: "testing_stale_timer",
            generation: staleGeneration
        )

        XCTAssertEqual(model.session?.mode, .appCycle)
        XCTAssertTrue(controller.delayedWindowLayerTimer?.isValid == true)
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testProjectionRefreshKeepsVisiblePreviewImagesInCurrentSession() {
        let currentApp = NSRunningApplication.current
        let appID = "com.flowtab.tests.preview-refresh-continuity"
        let windows = (0..<4).map { index in
            WindowCandidate(
                id: "refresh-preview-window-\(index)",
                title: "Refresh Preview Window \(index)",
                isMinimized: false,
                lastActiveAt: TimeInterval(1_000 - index)
            )
        }
        let app = AppSwitchCandidate(
            id: appID,
            displayName: "Preview Refresh",
            groupID: "preview-refresh",
            lastActiveAt: 1_000,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let service = RecordingRuntimeProjectionService(
            appSwitcherApps: [app],
            contextsByID: [appID: context]
        )
        let model = LiveSwitcherModel(runtimeProjectionService: service)
        var capturesAreAvailable = true
        var captureCallCount = 0
        model.previewCaptureOverride = { _, _, _, _ in
            captureCallCount += 1
            guard capturesAreAvailable else { return nil }
            return (
                image: self.makeColorImage(color: .systemTeal),
                resolvedWindowID: CGWindowID(captureCallCount),
                titleBarStyle: nil
            )
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.autoEnterWindowLayerIfPossible())
        let visibleRange = 0..<windows.count
        XCTAssertTrue(
            model.windowPreviewSnapshotForTesting(visibleRange: visibleRange).allSatisfy(\.hasImage)
        )
        XCTAssertEqual(captureCallCount, windows.count)

        service.installAppSwitcherProjection(
            apps: [app],
            contextsByID: [appID: context],
            generatedAt: 20
        )
        capturesAreAvailable = false

        XCTAssertTrue(model.handleAppSwitcherProjectionDidUpdate())
        let refreshed = model.windowPreviewSnapshotForTesting(visibleRange: visibleRange)

        XCTAssertEqual(refreshed.count, visibleRange.count)
        XCTAssertTrue(refreshed.allSatisfy(\.hasImage))
        XCTAssertEqual(captureCallCount, windows.count)
    }

    @MainActor
    func testRuntimeActivatorDoesNotVerifyCGRouteWhileTargetRemainsOffscreen() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let targetCGWindowID: CGWindowID = 378_401
        let targetAXWindow = AXUIElementCreateApplication(currentApp.processIdentifier)
        let previousCGWindowIDOverride = AXWindowInspector.cgWindowIDOverrideForTesting
        AXWindowInspector.cgWindowIDOverrideForTesting = { window in
            if CFEqual(window, targetAXWindow) {
                return targetCGWindowID
            }
            return previousCGWindowIDOverride?(window)
        }
        defer {
            AXWindowInspector.cgWindowIDOverrideForTesting = previousCGWindowIDOverride
        }

        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryPolicy = .disabled
        activator.focusCGWindowOverride = { _, windowID in
            XCTAssertEqual(windowID, targetCGWindowID)
            return true
        }
        activator.focusedAXWindowOverride = { _ in targetAXWindow }
        activator.currentCGWindowsOverride = { _ in
            [
                RuntimeCGWindowEntry(
                    id: targetCGWindowID,
                    title: "Offscreen Target",
                    bounds: CGRect(x: 0, y: 40, width: 960, height: 640),
                    isOnscreen: false,
                    alpha: 1,
                    storeType: 1
                ),
                RuntimeCGWindowEntry(
                    id: 378_402,
                    title: "Visible Other",
                    bounds: CGRect(x: 40, y: 80, width: 800, height: 600),
                    isOnscreen: true,
                    alpha: 1,
                    storeType: 1
                ),
            ]
        }
        var verifications: [RuntimeWindowFocusVerification] = []
        activator.windowFocusVerifiedHandler = { verifications.append($0) }
        var mismatches: [WindowBindingReadbackDiagnostic] = []
        activator.windowFocusReadbackMismatchHandler = { mismatches.append($0) }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Offscreen Target",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    spaceIDs: [1],
                    bindingConfidenceOverride: .sticky,
                    bindingAllowedActionsOverride: [.useForCGActivationFallback]
                ),
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertTrue(verifications.isEmpty)
        XCTAssertTrue(
            mismatches.contains { $0.route == "cg" && $0.reason == .targetCGNotVisible }
        )
    }
}
