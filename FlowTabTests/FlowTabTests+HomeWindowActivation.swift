import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabTests {
    @MainActor
    func testHomeWindowActivationRequestUsesSwitcherPreferencesForMinimizedWindowFallback() {
        let appID = "com.example.mail"
        let snapshot = makeHomeActivationSnapshot(
            appID: appID,
            windows: [
                WindowCandidate(
                    id: "mail-archive",
                    title: "Archive",
                    isMinimized: true,
                    lastActiveAt: 300
                )
            ]
        )
        var preferences = SwitcherPreferences.default
        preferences.autoRestoreMinimizedWindowOnSwitch = false

        let request = HomeWindowActivationController.makeActivationRequest(
            snapshot: snapshot,
            appID: appID,
            windowID: "mail-archive",
            preferences: preferences
        )

        XCTAssertEqual(request?.target, .app(appID: appID))
        let contextKeys = Set<String>(request?.contextsByID.keys.map { $0 } ?? [])
        XCTAssertEqual(contextKeys, [appID])
    }

    @MainActor
    func testHomeWindowActivationRequestBuildsRestoringWindowTargetWhenPreferenceAllowsIt() {
        let appID = "com.example.mail"
        let snapshot = makeHomeActivationSnapshot(
            appID: appID,
            windows: [
                WindowCandidate(
                    id: "mail-archive",
                    title: "Archive",
                    isMinimized: true,
                    lastActiveAt: 300
                )
            ]
        )
        var preferences = SwitcherPreferences.default
        preferences.autoRestoreMinimizedWindowOnSwitch = true

        let request = HomeWindowActivationController.makeActivationRequest(
            snapshot: snapshot,
            appID: appID,
            windowID: "mail-archive",
            preferences: preferences
        )

        XCTAssertEqual(
            request?.target,
            .window(appID: appID, windowID: "mail-archive", restoreIfMinimized: true)
        )
    }

    @MainActor
    func testHomeWindowActivationControllerActivatesSelectedHomeWindowWithSnapshotContext() {
        withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-mock-runtime"]) {
            var capturedTarget: ActivationTarget?
            var capturedContextsByID: [String: RuntimeAppContext] = [:]
            let controller = HomeWindowActivationController(
                snapshotService: RuntimeSnapshotService(
                    label: "FlowTabTests.HomeActivation.RuntimeSnapshotService",
                    snapshotProvider: RuntimeSnapshotProvider()
                ),
                preferencesProvider: { .default },
                activationHandler: { target, contextsByID in
                    capturedTarget = target
                    capturedContextsByID = contextsByID
                }
            )

            controller.activateWindow(
                appID: "com.flowtab.mock.mail",
                windowID: "mock-mail-draft"
            )

            XCTAssertEqual(
                capturedTarget,
                .window(
                    appID: "com.flowtab.mock.mail",
                    windowID: "mock-mail-draft",
                    restoreIfMinimized: false
                )
            )
            XCTAssertEqual(
                capturedContextsByID["com.flowtab.mock.mail"]?.windowsByID["mock-mail-draft"]?.title,
                "Draft"
            )
            XCTAssertNil(capturedContextsByID["com.flowtab.mock.browser"])
        }
    }

    @MainActor
    func testHomeWindowActivationControllerUsesProvidedHomeSnapshot() {
        let appID = "com.example.cached"
        let snapshot = makeHomeActivationSnapshot(
            appID: appID,
            windows: [
                WindowCandidate(
                    id: "cached-mail",
                    title: "Cached Mail",
                    isMinimized: false,
                    lastActiveAt: 400
                )
            ]
        )
        var capturedTarget: ActivationTarget?

        let controller = HomeWindowActivationController(
            preferencesProvider: { .default },
            activationHandler: { target, _ in
                capturedTarget = target
            }
        )

        controller.activateWindow(
            appID: appID,
            windowID: "cached-mail",
            snapshot: snapshot
        )

        XCTAssertEqual(
            capturedTarget,
            .window(appID: appID, windowID: "cached-mail", restoreIfMinimized: false)
        )
    }

    func testHomeRuntimeSnapshotServiceAppliesWindowRecencyToHomeCandidates() async {
        await withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-mock-runtime"]) {
            let tracker = RuntimeWindowRecencyTracker()
            let provider = RuntimeSnapshotProvider()
            let appID = "com.flowtab.mock.mail"
            guard let baselineSnapshot = provider.homeAppSnapshot(for: appID) else {
                XCTFail("Expected mock Home snapshot for \(appID)")
                return
            }
            guard let draftWindow = baselineSnapshot.context.windowsByID["mock-mail-draft"] else {
                XCTFail("Expected mock mail draft context")
                return
            }
            tracker.record(
                appID: appID,
                windowID: "mock-mail-draft",
                ownerPID: draftWindow.ownerPID == 0
                    ? baselineSnapshot.context.runningApp.processIdentifier
                    : draftWindow.ownerPID,
                cgWindowID: draftWindow.cgWindowID,
                title: draftWindow.title,
                frame: draftWindow.frame,
                allowedActions: WindowBindingConfidence.exact.allowedActions
            )
            let service = HomeRuntimeSnapshotService(
                snapshotProvider: provider,
                windowRecencyTracker: tracker
            )

            let orderedSnapshot = await service.homeAppSnapshot(for: appID)

            XCTAssertEqual(
                orderedSnapshot?.candidate.windows.map(\.id),
                ["mock-mail-draft", "mock-mail-inbox"]
            )
        }
    }

    func testHomeRuntimeProjectionReaderUsesRuntimeProjectionsWithoutSnapshotBridge() {
        let appID = "com.example.home-projection"
        let snapshot = makeHomeActivationSnapshot(
            appID: appID,
            windows: [
                WindowCandidate(
                    id: "home-projected-1",
                    title: "Home Projected One",
                    isMinimized: false,
                    lastActiveAt: 400
                )
            ]
        )
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 20,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let snapshotService = RecordingRuntimeSnapshotService(
            homeSummaryProjection: RuntimeHomeSummaryProjection(
                summaries: [snapshot.summary],
                freshness: freshness
            ),
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    snapshot: snapshot,
                    freshness: freshness
                )
            ]
        )

        XCTAssertEqual(
            HomeRuntimeProjectionReader.appSummaries(from: snapshotService)?.map(\.appID),
            [appID]
        )
        XCTAssertEqual(
            HomeRuntimeProjectionReader.lightweightAppSummaries(from: snapshotService)?.map(\.appID),
            [appID]
        )
        XCTAssertEqual(
            HomeRuntimeProjectionReader.appSummary(for: appID, from: snapshotService)?.windowCount,
            1
        )
        XCTAssertEqual(
            HomeRuntimeProjectionReader.appSnapshot(
                for: appID,
                from: snapshotService
            )?.candidate.windows.map(\.id),
            ["home-projected-1"]
        )
        XCTAssertEqual(snapshotService.lightweightSnapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.homeSummariesRequestCount(), 0)
        XCTAssertEqual(snapshotService.homeSummaryRequestCount(), 0)
        XCTAssertEqual(snapshotService.recordedHomeAppIDs(), [])
    }

    func testHomeInitialAppSummaryReaderDoesNotUseLightweightSnapshotFallback() {
        let appID = "com.example.home-initial-projection"
        let projectionApp = AppSwitchCandidate(
            id: appID,
            displayName: "Initial Projection",
            groupID: "initial",
            lastActiveAt: 300,
            windows: [
                WindowCandidate(id: "initial-window", title: "Initial", isMinimized: false, lastActiveAt: 300)
            ]
        )
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 21,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let projectionService = RecordingRuntimeSnapshotService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [projectionApp],
                contextsByID: [:],
                freshness: freshness
            )
        )

        XCTAssertEqual(
            HomeInitialAppSummaryReader.lightweightAppSummaries(from: projectionService).map(\.appID),
            [appID]
        )
        XCTAssertEqual(projectionService.lightweightSnapshotRequestCount(), 0)

        let missingProjectionService = RecordingRuntimeSnapshotService()

        XCTAssertEqual(
            HomeInitialAppSummaryReader.lightweightAppSummaries(from: missingProjectionService),
            []
        )
        XCTAssertEqual(missingProjectionService.lightweightSnapshotRequestCount(), 0)
    }

    func testHomeAppVisibilityPresentationKeepsHiddenAppsLast() {
        let summaries = [
            makeHomeAppSummary(appID: "com.example.mail", displayName: "Mail", rank: 0),
            makeHomeAppSummary(appID: "com.example.browser", displayName: "Browser", rank: 1),
            makeHomeAppSummary(appID: "com.example.notes", displayName: "Notes", rank: 2)
        ]
        let presentation = HomeAppVisibilityPresentation(hiddenAppIDs: ["com.example.mail"])

        XCTAssertEqual(
            presentation.orderedAppSummaries(summaries).map(\.appID),
            ["com.example.browser", "com.example.notes", "com.example.mail"]
        )
        XCTAssertTrue(presentation.isHidden(appID: "com.example.mail"))
        XCTAssertFalse(presentation.isHidden(appID: "com.example.browser"))
    }

    func testHomeInitialLoadingPolicyCommitsSelectedAppSummaryOnly() {
        let loadingAppIDs: Set<String> = [
            "com.flowtab.mock.mail",
            "com.flowtab.mock.browser"
        ]

        XCTAssertTrue(
            HomeInitialAppSummaryUpdatePolicy.shouldCommitSingleAppSummary(
                appID: "com.flowtab.mock.mail",
                selectedAppID: "com.flowtab.mock.mail",
                loadingWindowCountAppIDs: loadingAppIDs
            )
        )
        XCTAssertFalse(
            HomeInitialAppSummaryUpdatePolicy.shouldCommitSingleAppSummary(
                appID: "com.flowtab.mock.browser",
                selectedAppID: "com.flowtab.mock.mail",
                loadingWindowCountAppIDs: loadingAppIDs
            )
        )
        XCTAssertTrue(
            HomeInitialAppSummaryUpdatePolicy.shouldCommitSingleAppSummary(
                appID: "com.flowtab.mock.browser",
                selectedAppID: "com.flowtab.mock.mail",
                loadingWindowCountAppIDs: []
            )
        )
    }

    func testHomeOverviewStatsCountsVisibilityAndReadyWindows() {
        let summaries = [
            makeHomeAppSummary(appID: "com.example.mail", displayName: "Mail", rank: 0, windowCount: 2),
            makeHomeAppSummary(appID: "com.example.browser", displayName: "Browser", rank: 1, windowCount: 4),
            makeHomeAppSummary(appID: "com.example.notes", displayName: "Notes", rank: 2, windowCount: 1)
        ]

        let stats = HomeOverviewStats.make(
            appSummaries: summaries,
            hiddenAppIDs: ["com.example.mail"],
            loadingWindowCountAppIDs: []
        )

        XCTAssertEqual(stats.totalApps, 3)
        XCTAssertEqual(stats.visibleApps, 2)
        XCTAssertEqual(stats.hiddenApps, 1)
        XCTAssertEqual(stats.totalWindows, .ready(7))
    }

    func testHomeOverviewStatsKeepsWindowTotalLoadingDuringInitialCountRefresh() {
        let summaries = [
            makeHomeAppSummary(appID: "com.example.mail", displayName: "Mail", rank: 0, windowCount: 0),
            makeHomeAppSummary(appID: "com.example.browser", displayName: "Browser", rank: 1, windowCount: 0)
        ]

        let stats = HomeOverviewStats.make(
            appSummaries: summaries,
            hiddenAppIDs: [],
            loadingWindowCountAppIDs: ["com.example.mail", "com.example.browser"]
        )

        XCTAssertEqual(stats.totalApps, 2)
        XCTAssertEqual(stats.visibleApps, 2)
        XCTAssertEqual(stats.hiddenApps, 0)
        XCTAssertEqual(stats.totalWindows, .loading)
    }

    private func makeHomeActivationSnapshot(
        appID: String,
        windows: [WindowCandidate]
    ) -> RuntimeHomeAppSnapshot {
        let runningApp = NSRunningApplication.current
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: "Mail Fixture",
            groupID: "mail",
            lastActiveAt: 300,
            windows: windows
        )
        let windowsByID = Dictionary(
            uniqueKeysWithValues: windows.map { window in
                (
                    window.id,
                    RuntimeWindowContext(
                        id: window.id,
                        title: window.title,
                        isMinimized: window.isMinimized,
                        ownerPID: runningApp.processIdentifier
                    )
                )
            }
        )
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            windowsByID: windowsByID
        )
        let summary = RuntimeHomeAppSummary(
            appID: appID,
            displayName: "Mail Fixture",
            groupID: "mail",
            lastActiveAt: 300,
            windowCount: windows.count,
            pid: runningApp.processIdentifier
        )
        return RuntimeHomeAppSnapshot(summary: summary, candidate: candidate, context: context)
    }

    private func makeHomeAppSummary(
        appID: String,
        displayName: String,
        rank: Int,
        windowCount: Int = 1
    ) -> RuntimeHomeAppSummary {
        RuntimeHomeAppSummary(
            appID: appID,
            displayName: displayName,
            groupID: "fixture",
            lastActiveAt: TimeInterval(300 - rank),
            windowCount: windowCount,
            pid: pid_t(12_000 + rank)
        )
    }
}
