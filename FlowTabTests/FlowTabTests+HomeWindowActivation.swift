import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabTests {
    @MainActor
    func testHomeWindowActivationRequestUsesSwitcherPreferencesForMinimizedWindowFallback() {
        let appID = "com.example.mail"
        let detailProjection = makeHomeActivationDetailProjection(
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
            detailProjection: detailProjection,
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
        let detailProjection = makeHomeActivationDetailProjection(
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
            detailProjection: detailProjection,
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
    func testHomeWindowActivationControllerUsesRuntimeProjectionWithoutHomeSnapshotBridge() {
        let appID = "com.example.projected-home-activation"
        let detailProjection = makeHomeActivationDetailProjection(
            appID: appID,
            windows: [
                WindowCandidate(
                    id: "projected-draft",
                    title: "Projected Draft",
                    isMinimized: false,
                    lastActiveAt: 400
                )
            ]
        )
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 25,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    currentAppWindowPayload: RuntimeCurrentAppWindowPayload(
                        summary: detailProjection.summary,
                        candidate: detailProjection.candidate,
                        context: detailProjection.context,
                        appDirectoryEntries: [
                            RuntimeAppDirectoryEntry(app: detailProjection.context.runningApp)
                        ]
                    ),
                    freshness: freshness
                )
            ]
        )
        var capturedTarget: ActivationTarget?
        var capturedContextsByID: [String: RuntimeAppContext] = [:]
        let controller = HomeWindowActivationController(
            runtimeProjectionService: runtimeProjectionService,
            preferencesProvider: { .default },
            activationHandler: { target, contextsByID in
                capturedTarget = target
                capturedContextsByID = contextsByID
            }
        )

        controller.activateWindow(
            appID: appID,
            windowID: "projected-draft"
        )

        XCTAssertEqual(
            capturedTarget,
            .window(
                appID: appID,
                windowID: "projected-draft",
                restoreIfMinimized: false
            )
        )
        XCTAssertEqual(
            capturedContextsByID[appID]?.windowsByID["projected-draft"]?.title,
            "Projected Draft"
        )
        XCTAssertEqual(runtimeProjectionService.homeDetailProjectionReadCount(appID: appID), 1)
        XCTAssertEqual(runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID), 0)
        XCTAssertEqual(runtimeProjectionService.appWindowChangeSignalsRecorded().map(\.appID), [])
    }

    @MainActor
    func testHomeWindowActivationControllerSignalsRuntimeRepairWhenProjectionIsMissing() {
        let appID = "com.example.missing-home-activation-projection"
        let contaminatedDetailProjection = makeHomeActivationDetailProjection(
            appID: appID,
            windows: [
                WindowCandidate(
                    id: "contaminated-draft",
                    title: "Contaminated Draft",
                    isMinimized: false,
                    lastActiveAt: 400
                )
            ]
        )
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 26,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: RuntimeHomeSummaryProjection(
                summaries: [contaminatedDetailProjection.summary],
                freshness: freshness
            )
        )
        var capturedTarget: ActivationTarget?
        let controller = HomeWindowActivationController(
            runtimeProjectionService: runtimeProjectionService,
            preferencesProvider: { .default },
            activationHandler: { target, _ in
                capturedTarget = target
            }
        )

        controller.activateWindow(
            appID: appID,
            windowID: "contaminated-draft"
        )

        XCTAssertNil(capturedTarget)
        XCTAssertEqual(runtimeProjectionService.homeDetailProjectionReadCount(appID: appID), 1)
        XCTAssertEqual(runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID), 0)
        XCTAssertEqual(runtimeProjectionService.appSwitcherProjectionReadCount(), 0)
        XCTAssertEqual(runtimeProjectionService.homeSummaryProjectionReadCount(), 1)
        XCTAssertEqual(runtimeProjectionService.appWindowChangeSignalsRecorded().map(\.appID), [appID])
        XCTAssertEqual(
            runtimeProjectionService.appWindowChangeSignalsRecorded().map(\.pid),
            [contaminatedDetailProjection.summary.pid]
        )

        let appSwitcherOnlyService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [contaminatedDetailProjection.candidate],
                contextsByID: [appID: contaminatedDetailProjection.context],
                freshness: freshness
            )
        )
        let appSwitcherOnlyController = HomeWindowActivationController(
            runtimeProjectionService: appSwitcherOnlyService,
            preferencesProvider: { .default },
            activationHandler: { target, _ in
                capturedTarget = target
            }
        )

        appSwitcherOnlyController.activateWindow(
            appID: appID,
            windowID: "contaminated-draft"
        )

        XCTAssertEqual(appSwitcherOnlyService.homeDetailProjectionReadCount(appID: appID), 1)
        XCTAssertEqual(appSwitcherOnlyService.homeSummaryProjectionReadCount(), 1)
        XCTAssertEqual(appSwitcherOnlyService.appSwitcherProjectionReadCount(), 0)
        XCTAssertEqual(appSwitcherOnlyService.appWindowChangeSignalsRecorded().map(\.appID), [])
    }

    @MainActor
    func testHomeWindowActivationControllerUsesProvidedDetailProjection() {
        let appID = "com.example.cached"
        let detailProjection = makeHomeActivationDetailProjection(
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
            detailProjection: detailProjection
        )

        XCTAssertEqual(
            capturedTarget,
            .window(appID: appID, windowID: "cached-mail", restoreIfMinimized: false)
        )
    }

    func testRuntimeWindowRecencyTrackerAppliesToRuntimeProjectionRepairProviderCurrentAppPayload() async {
        await withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-mock-runtime"]) {
            let tracker = RuntimeWindowRecencyTracker()
            let appID = "com.flowtab.mock.mail"
            guard let currentAppPayload = FlowTabUITestRuntimeProjectionDataset
                .current()?
                .currentAppWindowPayloadsByAppID[appID]
            else {
                XCTFail("Expected mock current-app payload for \(appID)")
                return
            }
            guard let draftWindow = currentAppPayload.context.windowsByID["mock-mail-draft"] else {
                XCTFail("Expected mock mail draft context")
                return
            }
            tracker.record(
                appID: appID,
                windowID: "mock-mail-draft",
                ownerPID: draftWindow.ownerPID == 0
                    ? currentAppPayload.context.runningApp.processIdentifier
                    : draftWindow.ownerPID,
                cgWindowID: draftWindow.cgWindowID,
                title: draftWindow.title,
                frame: draftWindow.frame,
                allowedActions: WindowBindingConfidence.exact.allowedActions
            )

            let orderedPayload = tracker.currentAppWindowPayloadWithRecencyApplied(
                currentAppPayload
            )

            XCTAssertEqual(
                orderedPayload.candidate.windows.map(\.id),
                ["mock-mail-draft", "mock-mail-inbox"]
            )
        }
    }

    func testHomeRuntimeProjectionReaderUsesRuntimeProjectionsWithoutSnapshotBridge() {
        let appID = "com.example.home-projection"
        let detailProjection = makeHomeActivationDetailProjection(
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
            dirtyAppIDs: [appID],
            dirtyPIDs: [detailProjection.summary.pid],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: ["homeSummary:\(appID)"],
            isCompleteForScope: false
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: RuntimeHomeSummaryProjection(
                summaries: [detailProjection.summary],
                freshness: freshness
            ),
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    currentAppWindowPayload: RuntimeCurrentAppWindowPayload(
                        summary: detailProjection.summary,
                        candidate: detailProjection.candidate,
                        context: detailProjection.context,
                        appDirectoryEntries: [
                            RuntimeAppDirectoryEntry(app: detailProjection.context.runningApp)
                        ]
                    ),
                    freshness: freshness
                )
            ]
        )

        let summaryRead = HomeRuntimeProjectionReader.appSummaryProjection(from: runtimeProjectionService)
        XCTAssertEqual(summaryRead?.summaries.map(\.appID), [appID])
        XCTAssertEqual(summaryRead?.freshness, freshness)
        XCTAssertEqual(summaryRead?.isProjectionBacked, true)
        XCTAssertEqual(summaryRead?.freshness?.isCompleteForScope, false)
        let initialRead = HomeRuntimeProjectionReader.initialAppSummaryProjection(from: runtimeProjectionService)
        XCTAssertEqual(initialRead?.summaries.map(\.appID), [appID])
        XCTAssertEqual(initialRead?.freshness, freshness)
        XCTAssertEqual(initialRead?.isProjectionBacked, true)
        XCTAssertEqual(
            HomeRuntimeProjectionReader.appSummaries(from: runtimeProjectionService)?.map(\.appID),
            [appID]
        )
        XCTAssertEqual(
            HomeRuntimeProjectionReader.initialAppSummaries(from: runtimeProjectionService)?.map(\.appID),
            [appID]
        )
        XCTAssertEqual(
            HomeRuntimeProjectionReader.appSummary(for: appID, from: runtimeProjectionService)?.windowCount,
            1
        )
        XCTAssertEqual(
            HomeRuntimeProjectionReader.appDetailProjection(
                for: appID,
                from: runtimeProjectionService
            )?.candidate.windows.map(\.id),
            ["home-projected-1"]
        )
        XCTAssertEqual(runtimeProjectionService.homeSummaryProjectionReadCount(), 5)
        XCTAssertEqual(runtimeProjectionService.homeDetailProjectionReadCount(appID: appID), 1)
        XCTAssertEqual(runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID), 0)
        XCTAssertEqual(runtimeProjectionService.appSwitcherProjectionReadCount(), 0)
    }

    func testHomeNoSwitchableWindowProjectionStateUsesProjectionFreshness() {
        let appID = "com.example.home-no-windows"
        let detailProjection = makeHomeActivationDetailProjection(appID: appID, windows: [])
        let staleFreshness = RuntimeProjectionFreshness(
            generatedAt: 21,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [appID],
            dirtyPIDs: [detailProjection.summary.pid],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: ["appWindows:\(appID)"],
            isCompleteForScope: false
        )
        let cleanFreshness = RuntimeProjectionFreshness(
            generatedAt: 22,
            sourceGeneration: RuntimeReadModelGeneration(projection: 2),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let staleCurrentAppService = RecordingRuntimeProjectionService(
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    currentAppWindowPayload: RuntimeCurrentAppWindowPayload(
                        summary: detailProjection.summary,
                        candidate: detailProjection.candidate,
                        context: detailProjection.context,
                        appDirectoryEntries: [
                            RuntimeAppDirectoryEntry(app: detailProjection.context.runningApp)
                        ]
                    ),
                    freshness: staleFreshness
                )
            ]
        )
        let cleanHomeSummaryService = RecordingRuntimeProjectionService(
            homeSummaryProjection: RuntimeHomeSummaryProjection(
                summaries: [detailProjection.summary],
                freshness: cleanFreshness
            )
        )
        let appSwitcherOnlyService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [detailProjection.candidate],
                contextsByID: [appID: detailProjection.context],
                freshness: staleFreshness
            )
        )

        XCTAssertTrue(
            HomeRuntimeProjectionReader.shouldWaitForNoSwitchableWindowProjection(
                appID: appID,
                pid: detailProjection.summary.pid,
                from: staleCurrentAppService
            )
        )
        XCTAssertFalse(
            HomeRuntimeProjectionReader.shouldWaitForNoSwitchableWindowProjection(
                appID: appID,
                pid: detailProjection.summary.pid,
                from: cleanHomeSummaryService
            )
        )
        XCTAssertFalse(
            HomeRuntimeProjectionReader.shouldWaitForNoSwitchableWindowProjection(
                appID: appID,
                pid: detailProjection.summary.pid,
                from: appSwitcherOnlyService
            )
        )
        XCTAssertEqual(staleCurrentAppService.currentAppWindowProjectionReadCount(appID: appID), 1)
        XCTAssertEqual(staleCurrentAppService.homeSummaryProjectionReadCount(), 0)
        XCTAssertEqual(cleanHomeSummaryService.currentAppWindowProjectionReadCount(appID: appID), 1)
        XCTAssertEqual(cleanHomeSummaryService.homeSummaryProjectionReadCount(), 1)
        XCTAssertEqual(appSwitcherOnlyService.currentAppWindowProjectionReadCount(appID: appID), 1)
        XCTAssertEqual(appSwitcherOnlyService.homeSummaryProjectionReadCount(), 1)
        XCTAssertEqual(appSwitcherOnlyService.appSwitcherProjectionReadCount(), 0)
    }

    func testHomeInitialAppSummaryReaderDoesNotUseLightweightSnapshotFallback() {
        let appID = "com.example.home-initial-projection"
        let summary = makeHomeAppSummary(
            appID: appID,
            displayName: "Initial Projection",
            rank: 0,
            windowCount: 1
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
        let projectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: RuntimeHomeSummaryProjection(
                summaries: [summary],
                freshness: freshness
            )
        )

        let initialProjectionRead = HomeInitialAppSummaryReader.appSummaryProjection(from: projectionService)
        XCTAssertEqual(initialProjectionRead.summaries.map(\.appID), [appID])
        XCTAssertEqual(initialProjectionRead.freshness, freshness)
        XCTAssertEqual(initialProjectionRead.isProjectionBacked, true)
        XCTAssertEqual(
            HomeInitialAppSummaryReader.appSummaries(from: projectionService).map(\.appID),
            [appID]
        )
        XCTAssertEqual(projectionService.homeSummaryProjectionReadCount(), 2)
        XCTAssertEqual(projectionService.appSwitcherProjectionReadCount(), 0)

        let missingProjectionService = RecordingRuntimeProjectionService()

        let missingRead = HomeInitialAppSummaryReader.appSummaryProjection(from: missingProjectionService)
        XCTAssertEqual(missingRead.summaries, [])
        XCTAssertNil(missingRead.freshness)
        XCTAssertEqual(missingRead.isProjectionBacked, false)
        XCTAssertEqual(
            HomeInitialAppSummaryReader.appSummaries(from: missingProjectionService),
            []
        )
        XCTAssertEqual(missingProjectionService.homeSummaryProjectionReadCount(), 2)
        XCTAssertEqual(missingProjectionService.appSwitcherProjectionReadCount(), 0)
        XCTAssertEqual(missingProjectionService.appSwitcherMaintenanceRequestsRecorded(), [])
    }

    func testHomeRuntimeProjectionReaderDoesNotDeriveHomeDataFromAppSwitcherProjection() {
        let appID = "com.example.home-app-switcher-projection"
        let detailProjection = makeHomeActivationDetailProjection(
            appID: appID,
            windows: [
                WindowCandidate(
                    id: "projection-window",
                    title: "Projection Window",
                    isMinimized: false,
                    lastActiveAt: 410
                )
            ]
        )
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 22,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [detailProjection.candidate],
                contextsByID: [appID: detailProjection.context],
                freshness: freshness
            )
        )

        XCTAssertEqual(
            HomeRuntimeProjectionReader.appSummaries(from: runtimeProjectionService)?.map(\.appID),
            nil
        )
        XCTAssertEqual(
            HomeRuntimeProjectionReader.appSummary(for: appID, from: runtimeProjectionService)?.pid,
            nil
        )
        XCTAssertEqual(
            HomeRuntimeProjectionReader.appDetailProjection(
                for: appID,
                from: runtimeProjectionService
            )?.candidate.windows.map(\.id),
            nil
        )
        XCTAssertEqual(runtimeProjectionService.homeSummaryProjectionReadCount(), 2)
        XCTAssertEqual(runtimeProjectionService.homeDetailProjectionReadCount(appID: appID), 1)
        XCTAssertEqual(runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID), 0)
        XCTAssertEqual(runtimeProjectionService.appSwitcherProjectionReadCount(), 0)
    }

    func testHomeRuntimeRefreshReaderSignalsRuntimeRepairWhenProjectionIsMissingWithoutHomeFallback() {
        let appID = "com.example.home-refresh-missing"
        let cachedDetailProjection = makeHomeActivationDetailProjection(
            appID: appID,
            windows: [
                WindowCandidate(
                    id: "cached-window",
                    title: "Cached Window",
                    isMinimized: false,
                    lastActiveAt: 420
                )
            ]
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService()

        let summaryRead = HomeRuntimeRefreshReader.appSummaryProjection(
            from: runtimeProjectionService,
            current: [cachedDetailProjection.summary]
        )
        XCTAssertEqual(summaryRead.summaries.map(\.appID), [appID])
        XCTAssertNil(summaryRead.freshness)
        XCTAssertEqual(summaryRead.isProjectionBacked, false)
        XCTAssertEqual(
            HomeRuntimeRefreshReader.appSummaries(
                from: runtimeProjectionService,
                current: [cachedDetailProjection.summary]
            ).map(\.appID),
            [appID]
        )
        XCTAssertEqual(
            HomeRuntimeRefreshReader.appSummary(
                for: appID,
                from: runtimeProjectionService,
                current: [cachedDetailProjection.summary]
            )?.windowCount,
            1
        )
        XCTAssertEqual(
            HomeRuntimeRefreshReader.appDetailProjection(
                for: appID,
                from: runtimeProjectionService,
                current: cachedDetailProjection,
                currentSummary: cachedDetailProjection.summary
            )?.candidate.windows.map(\.id),
            ["cached-window"]
        )
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded(),
            [.homeProjectionMissing, .homeProjectionMissing]
        )
        XCTAssertEqual(runtimeProjectionService.appWindowChangeSignalsRecorded().map(\.appID), [appID, appID])
    }

    func testHomeRuntimeRefreshReaderPreservesVisibleOrderWhileUpdatingProjectionValues() {
        let currentSummaries = [
            makeHomeAppSummary(appID: "com.example.mail", displayName: "Mail", rank: 0),
            makeHomeAppSummary(appID: "com.example.browser", displayName: "Browser", rank: 1),
            makeHomeAppSummary(appID: "com.example.notes", displayName: "Notes", rank: 2),
        ]
        let refreshedSummaries = [
            makeHomeAppSummary(
                appID: "com.example.notes",
                displayName: "Notes Updated",
                rank: 0,
                windowCount: 3
            ),
            makeHomeAppSummary(
                appID: "com.example.calendar",
                displayName: "Calendar",
                rank: 1,
                windowCount: 2
            ),
            makeHomeAppSummary(
                appID: "com.example.mail",
                displayName: "Mail Updated",
                rank: 2,
                windowCount: 4
            ),
            makeHomeAppSummary(
                appID: "com.example.browser",
                displayName: "Browser Updated",
                rank: 3,
                windowCount: 5
            ),
        ]
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: RuntimeHomeSummaryProjection(
                summaries: refreshedSummaries,
                freshness: RuntimeProjectionFreshness(
                    generatedAt: 50,
                    sourceGeneration: RuntimeReadModelGeneration(projection: 2),
                    dirtyAppIDs: [],
                    dirtyPIDs: [],
                    dirtyCGWindowIDs: [],
                    pendingRepairScopes: [],
                    isCompleteForScope: true
                )
            )
        )

        let read = HomeRuntimeRefreshReader.appSummaryProjection(
            from: runtimeProjectionService,
            current: currentSummaries
        )

        XCTAssertEqual(
            read.summaries.map(\.appID),
            [
                "com.example.mail",
                "com.example.browser",
                "com.example.notes",
                "com.example.calendar",
            ]
        )
        XCTAssertEqual(read.summaries.map(\.displayName), [
            "Mail Updated",
            "Browser Updated",
            "Notes Updated",
            "Calendar",
        ])
        XCTAssertEqual(read.summaries.map(\.windowCount), [4, 5, 3, 2])
    }

    func testHomeRuntimeRefreshReaderRetriesIncompleteEmptyDetailProjection() {
        let appID = "com.example.home-refresh-incomplete-empty"
        let detailProjection = makeHomeActivationDetailProjection(
            appID: appID,
            windows: [],
            isCompleteForScope: false
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeDetailProjectionsByAppID: [appID: detailProjection]
        )

        XCTAssertEqual(
            HomeRuntimeRefreshReader.appDetailProjection(
                for: appID,
                from: runtimeProjectionService,
                current: nil,
                currentSummary: detailProjection.summary
            )?.candidate.windows,
            []
        )
        XCTAssertEqual(
            runtimeProjectionService.appWindowChangeSignalsRecorded().map(\.appID),
            [appID]
        )
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

    func testHomeRuntimeProjectionRefreshPolicyRequestsOnlyAfterProjectionStateIsLoaded() {
        XCTAssertFalse(
            HomeRuntimeProjectionRefreshPolicy.shouldRequestAppSummaryRefresh(
                appSummaryCount: 0,
                loadingWindowCountAppCount: 0
            )
        )
        XCTAssertFalse(
            HomeRuntimeProjectionRefreshPolicy.shouldRequestAppSummaryRefresh(
                appSummaryCount: 2,
                loadingWindowCountAppCount: 1
            )
        )
        XCTAssertTrue(
            HomeRuntimeProjectionRefreshPolicy.shouldRequestAppSummaryRefresh(
                appSummaryCount: 2,
                loadingWindowCountAppCount: 0
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

    private func makeHomeActivationDetailProjection(
        appID: String,
        windows: [WindowCandidate],
        isCompleteForScope: Bool = true
    ) -> RuntimeHomeAppDetailProjection {
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
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 300,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: isCompleteForScope
        )
        return RuntimeHomeAppDetailProjection(
            summary: summary,
            candidate: candidate,
            context: context,
            freshness: freshness
        )
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
