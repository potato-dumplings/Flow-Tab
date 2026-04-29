import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testLiveSwitcherModelWindowLayerNavigationCommitsSessionWindowTarget() {
        let model = LiveSwitcherModel()
        model.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.commitScenarioApps(), contextsByID: [:])
        }

        var activatedTarget: ActivationTarget?
        model.activationOverride = { target, _ in
            activatedTarget = target
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertEqual(model.selectedApp?.id, "com.example.code")

        model.handle(.tabBackward)
        XCTAssertEqual(model.selectedApp?.id, "com.example.mail")
        XCTAssertEqual(model.session?.mode, .appCycle)

        model.handle(.downArrow)
        XCTAssertEqual(model.session?.mode, .windowCycle(appID: "com.example.mail"))
        XCTAssertEqual(model.session?.selectedWindow?.id, "mail-new")

        model.handle(.tabForward)
        XCTAssertEqual(model.session?.selectedWindow?.id, "mail-old")

        model.commitSelection()

        XCTAssertEqual(
            activatedTarget,
            .window(appID: "com.example.mail", windowID: "mail-old", restoreIfMinimized: false)
        )
        XCTAssertNil(model.session)
    }

    func testRuntimeLogIntegrationFiltersDeltasAndClearsEntries() async {
        let defaults = UserDefaults.standard
        let previousVerbose = defaults.object(forKey: AppPreferenceKeys.enableVerboseDiagnostics)
        let previousLevel = defaults.object(forKey: AppPreferenceKeys.runtimeLogLevel)
        defer {
            restoreUserDefaultsValue(
                previousVerbose,
                forKey: AppPreferenceKeys.enableVerboseDiagnostics,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousLevel,
                forKey: AppPreferenceKeys.runtimeLogLevel,
                userDefaults: defaults
            )
            RuntimeDiagnostics.shared.clear()
        }

        defaults.set(false, forKey: AppPreferenceKeys.enableVerboseDiagnostics)
        defaults.set(RuntimeLogLevel.debug.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        RuntimeDiagnostics.shared.clear()
        _ = await RuntimeDiagnostics.shared.makeReadSnapshot()

        let marker = "RuntimeLogIntegration-\(UUID().uuidString)"
        RuntimeLog.info("InputTrace", "\(marker)-noisy-info")
        RuntimeLog.warning("InputTrace", "\(marker)-noisy-warning")
        RuntimeLog.info("UnitTest", "\(marker)-normal-info")
        let snapshot = await RuntimeDiagnostics.shared.makeReadSnapshot()

        RuntimeLog.error("UnitTest", "\(marker)-after-snapshot-error")

        let warningLines = await RuntimeDiagnostics.shared.readRecentLines(
            limit: 20,
            minimumLevel: .warning
        )
        let scopedWarningLines = warningLines.filter { $0.contains(marker) }
        XCTAssertTrue(scopedWarningLines.contains { $0.contains("\(marker)-noisy-warning") })
        XCTAssertTrue(scopedWarningLines.contains { $0.contains("\(marker)-after-snapshot-error") })
        XCTAssertFalse(scopedWarningLines.contains { $0.contains("\(marker)-normal-info") })
        XCTAssertFalse(scopedWarningLines.contains { $0.contains("\(marker)-noisy-info") })

        let deltaLines = await RuntimeDiagnostics.shared.readRecentLines(
            limit: 20,
            minimumLevel: .info,
            since: snapshot
        )
        let scopedDeltaLines = deltaLines.filter { $0.contains(marker) }
        XCTAssertEqual(scopedDeltaLines.count, 1)
        XCTAssertTrue(scopedDeltaLines[0].contains("\(marker)-after-snapshot-error"))

        RuntimeDiagnostics.shared.clear()
        let clearedLines = await RuntimeDiagnostics.shared.readRecentLines(limit: 20, minimumLevel: .debug)
        XCTAssertFalse(clearedLines.contains { $0.contains(marker) })
    }
}
