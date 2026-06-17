import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    func testRuntimeWindowTopologyClassifierUsesNamedPolicyThresholds() {
        let policy = RuntimeWindowTopologyPolicy.default

        XCTAssertEqual(RuntimeWindowTopologyClassifier.policy, policy)
        XCTAssertEqual(RuntimeWindowTopologyClassifier.desktopSpaceID, 1)
        XCTAssertEqual(policy.fullscreenMinimumWidth, 900)
        XCTAssertEqual(policy.fullscreenMinimumHeight, 600)
        XCTAssertEqual(policy.fullscreenOriginTolerance, 90)
        XCTAssertEqual(policy.fullscreenTopInsetLimit, 180)
        XCTAssertEqual(policy.frameMatchOriginTolerance, 24)
        XCTAssertEqual(policy.frameMatchSizeTolerance, 40)
    }

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

    func testRuntimeWindowTopologyClassifierBuildsSpaceEvidenceConfidence() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)

        let observed = RuntimeWindowTopologyClassifier.spaceEvidence(
            cgWindowID: 240_001,
            spaceIDs: [1, 1],
            bounds: CGRect(x: 100, y: 100, width: 800, height: 500),
            source: "cg"
        )
        XCTAssertEqual(observed.spaceIDs, Set([1]))
        XCTAssertEqual(observed.confidence, .observed)
        XCTAssertFalse(observed.canConfirmExactBinding)
        XCTAssertTrue(observed.allowsPublicAXRecovery)

        let topology = RuntimeWindowTopologyClassifier.spaceEvidence(
            cgWindowID: 240_002,
            spaceIDs: [11_679],
            bounds: CGRect(x: 160, y: 140, width: 960, height: 680),
            source: "cg"
        )
        XCTAssertEqual(topology.confidence, .inferredFromTopology)
        XCTAssertFalse(topology.canConfirmExactBinding)
        XCTAssertTrue(topology.allowsPublicAXRecovery)

        let fullscreen = RuntimeWindowTopologyClassifier.spaceEvidence(
            cgWindowID: 240_003,
            spaceIDs: [11_679],
            bounds: fullscreenBounds,
            source: "cg"
        )
        XCTAssertEqual(fullscreen.confidence, .inferredFromFullscreenGeometry)
        XCTAssertFalse(fullscreen.canConfirmExactBinding)
        XCTAssertTrue(fullscreen.allowsPublicAXRecovery)

        let stale = RuntimeWindowTopologyClassifier.spaceEvidence(
            cgWindowID: 240_004,
            spaceIDs: [],
            bounds: nil,
            source: "cached"
        )
        XCTAssertEqual(stale.confidence, .stale)
        XCTAssertFalse(stale.canConfirmExactBinding)
        XCTAssertFalse(stale.allowsPublicAXRecovery)
    }

    func testRuntimeSnapshotProviderWindowEntriesCarrySpaceEvidence() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let provider = RuntimeSnapshotProvider()

        let entries = provider.resolvedStableWindowEntries(
            axWindows: [],
            cgWindows: [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: 240_003,
                    title: "Fullscreen Window",
                    bounds: fullscreenBounds,
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [11_679]
                )
            ],
            pid: 18_405,
            appName: "Space Evidence Fixture"
        )

        XCTAssertEqual(entries.first?.spaceEvidence?.cgWindowID, 240_003)
        XCTAssertEqual(entries.first?.spaceEvidence?.spaceIDs, Set([11_679]))
        XCTAssertEqual(entries.first?.spaceEvidence?.confidence, .inferredFromFullscreenGeometry)
        XCTAssertFalse(entries.first?.spaceEvidence?.canConfirmExactBinding ?? true)

        let context = RuntimeWindowContext(
            id: "cg:18405:240003",
            title: "Fullscreen Window",
            isMinimized: false,
            ownerPID: 18_405,
            cgWindowID: 240_003,
            spaceIDs: entries.first?.spaceIDs ?? [],
            frame: fullscreenBounds,
            spaceEvidence: entries.first?.spaceEvidence
        )
        XCTAssertEqual(context.spaceEvidence?.confidence, .inferredFromFullscreenGeometry)
    }

    func testRuntimeSnapshotProviderStaleSpaceEvidenceDisablesPublicAXRecovery() {
        let provider = RuntimeSnapshotProvider()
        let pid: pid_t = 18_405
        let frame = CGRect(x: 100, y: 100, width: 900, height: 620)
        let entries = provider.resolvedStableWindowEntries(
            axWindows: [
                RuntimeSnapshotProvider.AXWindowEntry(
                    index: 0,
                    id: "ax:18405:0",
                    title: "Stale Space",
                    sourceTitle: "Stale Space",
                    isMinimized: false,
                    window: AXUIElementCreateApplication(pid),
                    frame: frame
                )
            ],
            cgWindows: [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: 240_004,
                    title: "Stale Space",
                    bounds: frame,
                    isOnscreen: true,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: []
                )
            ],
            pid: pid,
            appName: "Space Evidence Fixture"
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.spaceEvidence?.confidence, .stale)
        XCTAssertFalse(entries.first?.allowsPublicAXRecovery ?? true)
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

        let entriesByCGWindowID = Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            entry.cgWindowID.map { ($0, entry) }
        })

        XCTAssertEqual(Set(entriesByCGWindowID.keys), [243_747, 240_101])
        XCTAssertEqual(entriesByCGWindowID[243_747]?.title, "Shared Doc")
        XCTAssertEqual(entriesByCGWindowID[243_747]?.spaceIDs, [11_679])
        XCTAssertTrue(entriesByCGWindowID[243_747]?.hasActivationHandle == true)
        XCTAssertEqual(
            entriesByCGWindowID[243_747]?.lastConfirmationSource,
            .fullscreenContentFallbackBinding
        )
        XCTAssertEqual(entriesByCGWindowID[240_101]?.title, "Shared Doc")
        XCTAssertEqual(entriesByCGWindowID[240_101]?.spaceIDs, [1])
        XCTAssertFalse(entriesByCGWindowID[240_101]?.hasActivationHandle == true)
        XCTAssertNil(entriesByCGWindowID[240_101]?.lastConfirmationSource)
    }

    @MainActor
    func testLiveSwitcherModelGlobalAndFocusedSessionsUseSameSpaceTopologyRuntimeTruth() {
        let restoreCurrentAppVisibility = enableCurrentAppInSwitcherForTesting()
        defer { restoreCurrentAppVisibility() }

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
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: currentApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 100,
            windows: windows
        )
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: contexts
        )
        let focusedSnapshot = RuntimeHomeAppSnapshot(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: candidate.displayName,
                groupID: candidate.groupID,
                lastActiveAt: candidate.lastActiveAt,
                windowCount: windows.count,
                pid: pid
            ),
            candidate: candidate,
            context: context
        )
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 10,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let snapshotService = RecordingRuntimeSnapshotService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [candidate],
                contextsByID: [appID: context],
                freshness: freshness
            ),
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    currentAppWindowPayload: RuntimeCurrentAppWindowPayload(
                        homeAppSnapshot: focusedSnapshot
                    ),
                    freshness: freshness
                )
            ]
        )
        let model = LiveSwitcherModel(snapshotService: snapshotService)
        model.frontmostApplicationOverride = { currentApp }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.lightweightSnapshotRequestCount(), 0)
        let globalWindowIDs = model.session?.apps.first(where: { $0.id == appID })?.windows.map(\.id) ?? []
        model.cancelSelection()
        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))
        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.lightweightSnapshotRequestCount(), 0)
        let focusedWindowIDs = model.session?.apps.first?.windows.map(\.id) ?? []
        let expectedWindowIDs: Set<String> = ["cg:\(pid):243747", "cg:\(pid):240101"]

        XCTAssertEqual(Set(globalWindowIDs), expectedWindowIDs)
        XCTAssertEqual(Set(focusedWindowIDs), expectedWindowIDs)
        XCTAssertEqual(globalWindowIDs.count, expectedWindowIDs.count)
        XCTAssertEqual(focusedWindowIDs.count, expectedWindowIDs.count)
        XCTAssertFalse(focusedWindowIDs.contains("cg:\(pid):240001"))
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

        let entriesByCGWindowID = Dictionary(
            uniqueKeysWithValues: entries.compactMap { entry -> (CGWindowID, RuntimeSnapshotProvider.SupplementalMergeEntryForTesting)? in
                guard let cgWindowID = entry.cgWindowID else { return nil }
                return (cgWindowID, entry)
            }
        )

        XCTAssertEqual(Set(entriesByCGWindowID.keys), [243_747, 240_101])
        XCTAssertEqual(entriesByCGWindowID[243_747]?.lastConfirmationSource, .fullscreenContentRebinding)
        XCTAssertEqual(entriesByCGWindowID[240_101]?.lastConfirmationSource, .desktopSiblingBinding)
        XCTAssertEqual(entriesByCGWindowID[243_747]?.spaceIDs, [11_679])
        XCTAssertEqual(entriesByCGWindowID[240_101]?.spaceIDs, [1])
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

    func testRuntimeAXRemoteWindowResolverBuildsNamedRemoteTokenLayout() {
        let pid = pid_t(0x0102_0304)
        let elementID = UInt64(0x0102_0304_0506_0708)
        let token = RuntimeAXRemoteWindowResolverForTesting.remoteToken(
            pid: pid,
            elementID: elementID
        )

        XCTAssertEqual(token.count, 20)
        XCTAssertEqual(
            Array(token[0..<4]),
            withUnsafeBytes(of: pid) { Array($0) }
        )
        XCTAssertEqual(
            Array(token[4..<8]),
            withUnsafeBytes(of: Int32(0)) { Array($0) }
        )
        XCTAssertEqual(
            Array(token[8..<12]),
            withUnsafeBytes(of: Int32(0x636f636f)) { Array($0) }
        )
        XCTAssertEqual(
            Array(token[12..<20]),
            withUnsafeBytes(of: elementID) { Array($0) }
        )
    }

    func testRuntimeAXRemoteWindowResolverUsesNamedScanPolicies() {
        let interactive = RuntimeAXRemoteWindowResolverForTesting.scanPolicy(for: .interactive)
        let hotPath = RuntimeAXRemoteWindowResolverForTesting.scanPolicy(for: .hotPath)
        let background = RuntimeAXRemoteWindowResolverForTesting.scanPolicy(for: .background)

        XCTAssertEqual(interactive.useCase, .interactive)
        XCTAssertEqual(interactive.maximumElementID, 750)
        XCTAssertEqual(interactive.timeoutSeconds, 0.080, accuracy: 0.000_001)

        XCTAssertEqual(hotPath.useCase, .hotPath)
        XCTAssertEqual(hotPath.maximumElementID, 1_000)
        XCTAssertEqual(hotPath.timeoutSeconds, 0.100, accuracy: 0.000_001)

        XCTAssertEqual(background.useCase, .background)
        XCTAssertEqual(background.maximumElementID, 2_000)
        XCTAssertEqual(background.timeoutSeconds, 0.250, accuracy: 0.000_001)
        XCTAssertLessThan(interactive.timeoutSeconds, background.timeoutSeconds)

        XCTAssertEqual(
            RuntimeAXRemoteWindowResolverForTesting.scanCompleteness(
                scannedCount: 24,
                timedOut: true,
                policy: background
            ),
            .partialTimedOut(scanned: 24, maximum: 2_000)
        )
    }

    func testRuntimeAXRemoteWindowResolverReportsCompleteScanSeparatelyFromTimeout() {
        XCTAssertEqual(
            RuntimeAXRemoteWindowResolverForTesting.scanCompleteness(
                scannedCount: 1_000,
                timedOut: false
            ),
            .complete(scanned: 1_000)
        )
    }

    func testRuntimeAXRemoteWindowResolverReportsPartialTimedOutScan() {
        XCTAssertEqual(
            RuntimeAXRemoteWindowResolverForTesting.scanCompleteness(
                scannedCount: 24,
                timedOut: true
            ),
            .partialTimedOut(scanned: 24, maximum: 1_000)
        )
    }

    func testRuntimeAXRemoteWindowResolverClassifiesResolveFailures() {
        let rejectedToken = RuntimeAXRemoteWindowResolverForTesting.remoteAXResolveResult(
            element: nil,
            elementID: 42
        )

        guard case let .rejected(elementID, tokenReason) = rejectedToken else {
            return XCTFail("Expected missing remote token to be rejected")
        }
        XCTAssertEqual(elementID, 42)
        XCTAssertEqual(tokenReason, .tokenUnavailable)

        let currentPID = NSRunningApplication.current.processIdentifier
        let mismatchedElement = AXUIElementCreateApplication(currentPID)
        let rejectedOwnerPID = RuntimeAXRemoteWindowResolverForTesting.remoteAXResolveResult(
            element: mismatchedElement,
            elementID: 43,
            expectedPID: currentPID + 1
        )
        guard case let .rejected(ownerElementID, ownerReason) = rejectedOwnerPID else {
            return XCTFail("Expected owner pid mismatch to be rejected")
        }
        XCTAssertEqual(ownerElementID, 43)
        XCTAssertEqual(
            ownerReason,
            .ownerPIDMismatch(expected: currentPID + 1, actual: currentPID)
        )

        XCTAssertEqual(
            RuntimeAXRemoteWindowResolverForTesting.resolveFailureReason(
                forSubrole: nil
            ),
            .missingSubrole
        )
        XCTAssertEqual(
            RuntimeAXRemoteWindowResolverForTesting.resolveFailureReason(
                forSubrole: "AXUnknown"
            ),
            .unsupportedSubrole("AXUnknown")
        )
        XCTAssertNil(
            RuntimeAXRemoteWindowResolverForTesting.resolveFailureReason(
                forSubrole: "AXStandardWindow"
            )
        )
        XCTAssertNil(
            RuntimeAXRemoteWindowResolverForTesting.resolveFailureReason(
                forSubrole: "AXDialog"
            )
        )
    }

    func testAXWindowInspectorFetchResultCarriesRemoteScanCompleteness() {
        let currentApp = NSRunningApplication.current
        let remoteWindow = AXUIElementCreateApplication(currentApp.processIdentifier)
        let expectedCompleteness: RuntimeAXRemoteWindowResolver.RemoteScanCompleteness = .partialTimedOut(
            scanned: 24,
            maximum: 1_000
        )
        let previousTrustedOverride = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousRemoteScanOverride = AXWindowInspector.remoteWindowScanResultOverrideForTesting
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AXWindowInspector.remoteWindowScanResultOverrideForTesting = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            return RuntimeAXRemoteWindowResolver.WindowScanResult(
                windows: [remoteWindow],
                completeness: expectedCompleteness
            )
        }
        defer {
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousTrustedOverride
            AXWindowInspector.remoteWindowScanResultOverrideForTesting = previousRemoteScanOverride
        }

        let result = AXWindowInspector.windowsFetchResult(
            for: currentApp,
            includeRemoteWindows: true
        )

        XCTAssertEqual(result.remoteScanCompleteness, expectedCompleteness)
        XCTAssertTrue(result.windows.contains(where: { CFEqual($0, remoteWindow) }))
        XCTAssertTrue(
            result.logDetails.contains("remoteScan=partialTimedOut scanned=24 maximum=1000")
        )
    }

    @MainActor
    func testAXWindowInspectorResolvesRemoteWindowsWithoutWaitingForMainThreadWhenRequestedFromBackground() {
        XCTAssertTrue(Thread.isMainThread)
        let previousTrustedOverride = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousRemoteOverride = AXWindowInspector.remoteWindowsResolverOverrideForTesting
        let previousRemoteScanOverride = AXWindowInspector.remoteWindowScanResultOverrideForTesting
        let lock = NSLock()
        var resolverThreadIsMain: Bool?
        let currentApp = NSRunningApplication.current
        let workerStarted = DispatchSemaphore(value: 0)
        let resolverInvoked = DispatchSemaphore(value: 0)
        let fetchCompleted = DispatchSemaphore(value: 0)
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AXWindowInspector.remoteWindowScanResultOverrideForTesting = nil
        AXWindowInspector.remoteWindowsResolverOverrideForTesting = { _ in
            lock.lock()
            resolverThreadIsMain = Thread.isMainThread
            lock.unlock()
            resolverInvoked.signal()
            return []
        }
        defer {
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousTrustedOverride
            AXWindowInspector.remoteWindowScanResultOverrideForTesting = previousRemoteScanOverride
            AXWindowInspector.remoteWindowsResolverOverrideForTesting = previousRemoteOverride
        }

        DispatchQueue(label: "FlowTabTests.AXBackgroundRemoteResolution").async {
            workerStarted.signal()
            _ = AXWindowInspector.windowsFetchResult(
                for: currentApp,
                includeRemoteWindows: true
            )
            fetchCompleted.signal()
        }

        XCTAssertEqual(workerStarted.wait(timeout: .now() + 1), .success)
        Thread.sleep(forTimeInterval: 0.25)
        let resolverResult = resolverInvoked.wait(timeout: .now())
        XCTAssertEqual(
            resolverResult,
            .success,
            "Remote AX scanning must not synchronously wait for the main thread while the main thread is busy."
        )
        if resolverResult == .success {
            XCTAssertEqual(fetchCompleted.wait(timeout: .now() + 1), .success)
        }

        lock.lock()
        let resolverRanOnMain = resolverThreadIsMain
        lock.unlock()
        XCTAssertEqual(resolverRanOnMain, false)
    }
}
