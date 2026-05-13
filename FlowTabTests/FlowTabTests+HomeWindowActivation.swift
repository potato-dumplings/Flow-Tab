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
            tracker.record(
                appID: appID,
                windowID: "mock-mail-draft",
                context: baselineSnapshot.context
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
}
