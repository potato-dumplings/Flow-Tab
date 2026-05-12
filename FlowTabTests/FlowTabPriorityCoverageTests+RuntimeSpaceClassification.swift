import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    func testRuntimeWindowTopologyClassifierNormalizesAndClassifiesSpaces() {
        XCTAssertEqual(RuntimeWindowTopologyClassifier.normalizedSpaceIDs([42, 1, 42, 0, -3]), [1, 42])
        XCTAssertEqual(RuntimeWindowTopologyClassifier.classify(spaceIDs: []), .unknown)
        XCTAssertEqual(RuntimeWindowTopologyClassifier.classify(spaceIDs: [1, 1]), .desktopOnly)
        XCTAssertEqual(RuntimeWindowTopologyClassifier.classify(spaceIDs: [11_679]), .offDesktop)
        XCTAssertEqual(RuntimeWindowTopologyClassifier.classify(spaceIDs: [1, 11_679]), .mixed)
    }

    func testRuntimeWindowTopologyClassifierDetectsFullscreenContentAndDesktopWrapper() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)

        XCTAssertTrue(
            RuntimeWindowTopologyClassifier.isLikelyOffDesktopFullscreenContent(
                bounds: fullscreenBounds,
                spaceIDs: [11_679]
            )
        )
        XCTAssertTrue(
            RuntimeWindowTopologyClassifier.isLikelyDesktopWrapper(
                bounds: fullscreenBounds,
                spaceIDs: [1],
                fullscreenContentBounds: [fullscreenBounds]
            )
        )
    }

    func testRuntimeSnapshotProviderSkipsRemoteAXScanWhenPublicAXAlreadyCoversRealCGWindows() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let desktopSiblingBounds = CGRect(x: 160, y: 140, width: 960, height: 680)

        let shouldScanRemoteAX = RuntimeSnapshotProvider.shouldIncludeRemoteAXWindowsForTesting(
            allCGWindows: [
                .init(
                    id: 240_101,
                    title: "Notes Inbox",
                    bounds: desktopSiblingBounds,
                    isOnscreen: false,
                    spaceIDs: [1]
                ),
                .init(
                    id: 240_001,
                    title: nil,
                    bounds: fullscreenBounds,
                    isOnscreen: true,
                    spaceIDs: [1]
                ),
                .init(
                    id: 243_747,
                    title: "Notes Focus",
                    bounds: fullscreenBounds,
                    isOnscreen: true,
                    spaceIDs: [11_679]
                )
            ],
            publicSwitchableWindowCount: 2
        )

        XCTAssertFalse(shouldScanRemoteAX)
    }

    func testRuntimeSnapshotProviderUsesRemoteAXScanWhenPublicAXMissesRealCGWindow() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let desktopSiblingBounds = CGRect(x: 160, y: 140, width: 960, height: 680)

        let shouldScanRemoteAX = RuntimeSnapshotProvider.shouldIncludeRemoteAXWindowsForTesting(
            allCGWindows: [
                .init(
                    id: 240_101,
                    title: "Notes Inbox",
                    bounds: desktopSiblingBounds,
                    isOnscreen: false,
                    spaceIDs: [1]
                ),
                .init(
                    id: 240_001,
                    title: nil,
                    bounds: fullscreenBounds,
                    isOnscreen: true,
                    spaceIDs: [1]
                ),
                .init(
                    id: 243_747,
                    title: "Notes Focus",
                    bounds: fullscreenBounds,
                    isOnscreen: true,
                    spaceIDs: [11_679]
                )
            ],
            publicSwitchableWindowCount: 1
        )

        XCTAssertTrue(shouldScanRemoteAX)
    }

    func testRuntimeSnapshotProviderRebindsFullscreenWrapperAXMatchToOffDesktopContent() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)

        let entries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [
                .init(
                    id: "ax:18405:0",
                    index: 0,
                    title: "Fullscreen Doc",
                    bounds: fullscreenBounds,
                    bridgedCGWindowID: 240_001
                )
            ],
            cgWindows: [
                .init(
                    id: 240_001,
                    title: "Fullscreen Doc",
                    bounds: fullscreenBounds,
                    isOnscreen: true,
                    spaceIDs: [1]
                ),
                .init(
                    id: 243_747,
                    title: "Fullscreen Doc",
                    bounds: fullscreenBounds,
                    isOnscreen: false,
                    spaceIDs: [11_679]
                )
            ],
            pid: 18_405,
            appName: "Google Chrome"
        )

        XCTAssertEqual(entries.map(\.cgWindowID), [243_747])
        XCTAssertEqual(entries.first?.spaceIDs, [11_679])
        XCTAssertEqual(entries.first?.lastConfirmationSource, .fullscreenContentRebinding)
    }

    func testRuntimeSnapshotProviderBindsAXOnlyFullscreenWrapperToOffDesktopContent() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)

        let entries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [
                .init(
                    id: "ax:18405:0",
                    index: 0,
                    title: nil,
                    bounds: fullscreenBounds
                )
            ],
            cgWindows: [
                .init(
                    id: 240_001,
                    title: "Shared Doc",
                    bounds: fullscreenBounds,
                    isOnscreen: true,
                    spaceIDs: [1]
                ),
                .init(
                    id: 243_747,
                    title: "Shared Doc",
                    bounds: fullscreenBounds,
                    isOnscreen: false,
                    spaceIDs: [11_679]
                )
            ],
            pid: 18_405,
            appName: "Google Chrome"
        )

        XCTAssertEqual(entries.map(\.cgWindowID), [243_747])
        XCTAssertEqual(entries.first?.title, "Shared Doc")
        XCTAssertEqual(entries.first?.spaceIDs, [11_679])
        XCTAssertTrue(entries.first?.hasActivationHandle == true)
        XCTAssertEqual(entries.first?.lastConfirmationSource, .fullscreenContentFallbackBinding)
    }

    func testRuntimeSnapshotProviderKeepsDesktopSiblingWhenAXOnlySeesFullscreenWrapper() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let desktopSiblingBounds = CGRect(x: 160, y: 140, width: 960, height: 680)

        let entries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [
                .init(
                    id: "ax:18405:0",
                    index: 0,
                    title: nil,
                    bounds: fullscreenBounds
                )
            ],
            cgWindows: [
                .init(
                    id: 240_001,
                    title: "Shared Doc",
                    bounds: fullscreenBounds,
                    isOnscreen: true,
                    spaceIDs: [1]
                ),
                .init(
                    id: 243_747,
                    title: "Shared Doc",
                    bounds: fullscreenBounds,
                    isOnscreen: false,
                    spaceIDs: [11_679]
                ),
                .init(
                    id: 240_101,
                    title: "Shared Doc",
                    bounds: desktopSiblingBounds,
                    isOnscreen: true,
                    spaceIDs: [1]
                )
            ],
            pid: 18_405,
            appName: "Google Chrome"
        )

        XCTAssertEqual(entries.map(\.cgWindowID), [243_747, 240_101])
        XCTAssertEqual(entries.map(\.title), ["Shared Doc", "Shared Doc"])
        XCTAssertEqual(entries.map(\.spaceIDs), [[11_679], [1]])
        XCTAssertEqual(entries.map(\.hasActivationHandle), [true, false])
        XCTAssertEqual(
            entries.map(\.lastConfirmationSource),
            [.fullscreenContentFallbackBinding, nil]
        )
    }

    @MainActor
    func testLiveSwitcherModelGlobalAndFocusedSessionsUseSameSpaceTopologyRuntimeTruth() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let desktopSiblingBounds = CGRect(x: 160, y: 140, width: 960, height: 680)
        let pid = currentApp.processIdentifier
        let entries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [
                .init(id: "ax:\(pid):0", index: 0, title: nil, bounds: fullscreenBounds)
            ],
            cgWindows: [
                .init(id: 240_001, title: "Shared Doc", bounds: fullscreenBounds, spaceIDs: [1]),
                .init(id: 243_747, title: "Shared Doc", bounds: fullscreenBounds, isOnscreen: false, spaceIDs: [11_679]),
                .init(id: 240_101, title: "Shared Doc", bounds: desktopSiblingBounds, spaceIDs: [1])
            ],
            pid: pid,
            appName: currentApp.localizedName ?? "FlowTab"
        )
        let windows = entries.enumerated().map { index, entry in
            WindowCandidate(
                id: entry.windowID,
                title: entry.title,
                isMinimized: false,
                lastActiveAt: Double(100 - index)
            )
        }
        let contexts: [String: RuntimeWindowContext] = Dictionary(uniqueKeysWithValues: zip(entries, windows).map { pair in
            let entry = pair.0
            let window = pair.1
            return (
                window.id,
                RuntimeWindowContext(
                    id: window.id,
                    title: window.title,
                    isMinimized: false,
                    ownerPID: pid,
                    cgWindowID: entry.cgWindowID,
                    spaceIDs: entry.spaceIDs,
                    activationHandleID: entry.hasActivationHandle ? "ax:\(pid):0" : nil,
                    frame: entry.frame,
                    allowsPublicAXRecovery: true,
                    lastConfirmationSource: entry.lastConfirmationSource
                )
            )
        })
        let snapshot = RuntimeSnapshot(
            apps: [
                AppSwitchCandidate(
                    id: appID,
                    displayName: currentApp.localizedName ?? "Current App",
                    groupID: "current",
                    lastActiveAt: 100,
                    windows: windows
                )
            ],
            contextsByID: [
                appID: RuntimeAppContext(
                    appID: appID,
                    runningApp: currentApp,
                    windowsByID: contexts
                )
            ]
        )
        let model = LiveSwitcherModel()
        model.frontmostApplicationOverride = { currentApp }
        model.snapshotProviderOverride = { snapshot }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        let globalWindowIDs = model.session?.apps.first(where: { $0.id == appID })?.windows.map(\.id)
        model.cancelSelection()
        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))
        let focusedWindowIDs = model.session?.apps.first?.windows.map(\.id)

        XCTAssertEqual(globalWindowIDs, focusedWindowIDs)
        XCTAssertEqual(focusedWindowIDs, ["cg:\(pid):243747", "cg:\(pid):240101"])
        XCTAssertFalse(focusedWindowIDs?.contains("cg:\(pid):240001") == true)
        XCTAssertEqual(model.session?.mode, .windowCycle(appID: appID))
    }

    func testRuntimeSnapshotProviderBindsDesktopSiblingAXHandleWhenFullscreenWrapperCGAlsoExists() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let desktopSiblingBounds = CGRect(x: 160, y: 140, width: 960, height: 680)

        let entries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [
                .init(
                    id: "ax:18405:0",
                    index: 0,
                    title: "Fullscreen Doc",
                    bounds: fullscreenBounds,
                    bridgedCGWindowID: 240_001
                ),
                .init(
                    id: "ax:18405:1",
                    index: 1,
                    title: nil,
                    bounds: desktopSiblingBounds
                )
            ],
            cgWindows: [
                .init(
                    id: 240_001,
                    title: "Fullscreen Doc",
                    bounds: fullscreenBounds,
                    isOnscreen: true,
                    spaceIDs: [1]
                ),
                .init(
                    id: 243_747,
                    title: "Fullscreen Doc",
                    bounds: fullscreenBounds,
                    isOnscreen: false,
                    spaceIDs: [11_679]
                ),
                .init(
                    id: 240_101,
                    title: nil,
                    bounds: desktopSiblingBounds,
                    isOnscreen: true,
                    spaceIDs: [1]
                )
            ],
            pid: 18_405,
            appName: "Google Chrome"
        )

        XCTAssertEqual(entries.map(\.cgWindowID), [243_747, 240_101])
        XCTAssertEqual(entries.map(\.lastConfirmationSource), [.fullscreenContentRebinding, .desktopSiblingBinding])
        XCTAssertEqual(entries.map(\.spaceIDs), [[11_679], [1]])
    }

    func testRuntimeSnapshotProviderBindsRemoteAXWindowToOffDesktopCGContent() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let desktopSiblingBounds = CGRect(x: 160, y: 140, width: 960, height: 680)

        let entries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [
                .init(
                    id: "ax:18405:0",
                    index: 0,
                    title: "Notes Inbox",
                    bounds: desktopSiblingBounds,
                    bridgedCGWindowID: 240_101
                ),
                .init(
                    id: "ax:18405:947",
                    index: 947,
                    title: "Notes Focus",
                    bounds: fullscreenBounds,
                    bridgedCGWindowID: 243_747
                )
            ],
            cgWindows: [
                .init(
                    id: 240_101,
                    title: "Notes Inbox",
                    bounds: desktopSiblingBounds,
                    isOnscreen: true,
                    spaceIDs: [1]
                ),
                .init(
                    id: 240_001,
                    title: "Notes Focus",
                    bounds: fullscreenBounds,
                    isOnscreen: true,
                    spaceIDs: [1]
                ),
                .init(
                    id: 243_747,
                    title: "Notes Focus",
                    bounds: fullscreenBounds,
                    isOnscreen: false,
                    spaceIDs: [11_679]
                )
            ],
            pid: 18_405,
            appName: "Notes Fixture"
        )

        XCTAssertEqual(entries.map(\.cgWindowID), [240_101, 243_747])
        XCTAssertEqual(entries.map(\.title), ["Notes Inbox", "Notes Focus"])
        XCTAssertEqual(entries.map(\.spaceIDs), [[1], [11_679]])
        XCTAssertEqual(entries.map(\.hasActivationHandle), [true, true])
        XCTAssertEqual(entries.map(\.lastConfirmationSource), [.publicExactMatch, .privateExactBridge])
    }

    func testRuntimeSnapshotProviderOrdersVisibleFullscreenSiblingBeforeHiddenDesktopSibling() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let desktopSiblingBounds = CGRect(x: 160, y: 140, width: 960, height: 680)

        let entries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [
                .init(
                    id: "ax:18405:0",
                    index: 0,
                    title: "Notes Inbox",
                    bounds: desktopSiblingBounds,
                    bridgedCGWindowID: 240_101
                ),
                .init(
                    id: "ax:18405:947",
                    index: 947,
                    title: "Notes Focus",
                    bounds: fullscreenBounds,
                    bridgedCGWindowID: 243_747
                )
            ],
            cgWindows: [
                .init(
                    id: 240_101,
                    title: "Notes Inbox",
                    bounds: desktopSiblingBounds,
                    isOnscreen: false,
                    spaceIDs: [1]
                ),
                .init(
                    id: 240_001,
                    title: "Notes Focus",
                    bounds: fullscreenBounds,
                    isOnscreen: false,
                    spaceIDs: [1]
                ),
                .init(
                    id: 243_747,
                    title: "Notes Focus",
                    bounds: fullscreenBounds,
                    isOnscreen: true,
                    spaceIDs: [11_679]
                )
            ],
            pid: 18_405,
            appName: "Notes Fixture"
        )

        XCTAssertEqual(entries.map(\.cgWindowID), [243_747, 240_101])
        XCTAssertEqual(entries.map(\.title), ["Notes Focus", "Notes Inbox"])
        XCTAssertEqual(entries.map(\.spaceIDs), [[11_679], [1]])
        XCTAssertEqual(entries.map(\.hasActivationHandle), [true, true])

        let windows = entries.enumerated().map { index, entry in
            WindowCandidate(
                id: entry.windowID,
                title: entry.title,
                isMinimized: false,
                lastActiveAt: Double(100 - index)
            )
        }
        var session = SwitcherSession(
            apps: [
                AppSwitchCandidate(
                    id: "com.example.fixture.notes",
                    displayName: "Notes Fixture",
                    groupID: "notes",
                    lastActiveAt: 100,
                    windows: windows
                )
            ]
        )

        XCTAssertTrue(session.enterWindowCycle(allowSingleWindow: false))
        XCTAssertEqual(session.selectedWindow?.title, "Notes Focus")
    }

    func testRuntimeAXRemoteWindowResolverDeduplicatesRemoteWindowsByCGWindowID() {
        let publicWindow = AXUIElementCreateApplication(18_405)
        let remoteDuplicate = AXUIElementCreateApplication(18_406)
        let remoteTarget = AXUIElementCreateApplication(18_407)
        let publicPointer = Unmanaged.passUnretained(publicWindow).toOpaque()
        let duplicatePointer = Unmanaged.passUnretained(remoteDuplicate).toOpaque()
        let targetPointer = Unmanaged.passUnretained(remoteTarget).toOpaque()
        let previousOverride = AXWindowInspector.cgWindowIDOverrideForTesting
        AXWindowInspector.cgWindowIDOverrideForTesting = { window in
            let pointer = Unmanaged.passUnretained(window).toOpaque()
            if pointer == publicPointer || pointer == duplicatePointer {
                return 240_101
            }
            if pointer == targetPointer {
                return 243_747
            }
            return nil
        }
        defer {
            AXWindowInspector.cgWindowIDOverrideForTesting = previousOverride
        }

        let merged = RuntimeAXRemoteWindowResolverForTesting.mergedWindows(
            publicWindows: [publicWindow],
            remoteWindows: [remoteDuplicate, remoteTarget]
        )

        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(CFEqual(merged[0], publicWindow))
        XCTAssertTrue(CFEqual(merged[1], remoteTarget))
    }

    func testAXWindowInspectorResolvesRemoteWindowsOnMainThreadWhenRequestedFromBackground() async {
        let previousTrustedOverride = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousRemoteOverride = AXWindowInspector.remoteWindowsResolverOverrideForTesting
        let lock = NSLock()
        var resolverThreadIsMain: Bool?
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AXWindowInspector.remoteWindowsResolverOverrideForTesting = { _ in
            lock.lock()
            resolverThreadIsMain = Thread.isMainThread
            lock.unlock()
            return []
        }
        defer {
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousTrustedOverride
            AXWindowInspector.remoteWindowsResolverOverrideForTesting = previousRemoteOverride
        }

        await withCheckedContinuation { continuation in
            DispatchQueue(label: "FlowTabTests.AXBackgroundRemoteResolution").async {
                _ = AXWindowInspector.windowsFetchResult(
                    for: NSRunningApplication.current,
                    includeRemoteWindows: true
                )
                continuation.resume()
            }
        }

        lock.lock()
        let resolvedOnMain = resolverThreadIsMain
        lock.unlock()
        XCTAssertEqual(resolvedOnMain, true)
    }
}
