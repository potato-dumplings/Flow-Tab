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
        rank: Int
    ) -> RuntimeHomeAppSummary {
        RuntimeHomeAppSummary(
            appID: appID,
            displayName: displayName,
            groupID: "fixture",
            lastActiveAt: TimeInterval(300 - rank),
            windowCount: 1,
            pid: pid_t(12_000 + rank)
        )
    }
}
