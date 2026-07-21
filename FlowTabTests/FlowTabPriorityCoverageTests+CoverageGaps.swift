import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testLiveSwitcherModelWindowLayerNavigationCommitsSessionWindowTarget() {
        let model = LiveSwitcherModel(
            runtimeProjectionService: RecordingRuntimeProjectionService(
                appSwitcherApps: commitScenarioApps()
            )
        )

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
        let previousExpiration = defaults.object(forKey: AppPreferenceKeys.diagnosticSessionExpiration)
        let previousLevel = defaults.object(forKey: AppPreferenceKeys.runtimeLogLevel)
        defer {
            restoreUserDefaultsValue(
                previousExpiration,
                forKey: AppPreferenceKeys.diagnosticSessionExpiration,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousLevel,
                forKey: AppPreferenceKeys.runtimeLogLevel,
                userDefaults: defaults
            )
            RuntimeDiagnostics.shared.clear()
        }

        RuntimeDiagnosticSessionStore.stop(userDefaults: defaults)
        defaults.set(RuntimeLogLevel.debug.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        RuntimeDiagnostics.shared.clear()
        _ = await RuntimeDiagnostics.shared.makeReadSnapshot()

        let category = "UnitTestIntegration\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        RuntimeLog.info(.inputTrace, "noisy-info")
        RuntimeLog.warning(.inputTrace, "noisy-warning")
        RuntimeLog.info(category, "normal-info")
        let snapshot = await RuntimeDiagnostics.shared.makeReadSnapshot()

        RuntimeLog.error(category, "after-snapshot-error")

        let warningLines = await RuntimeDiagnostics.shared.readRecentLines(
            limit: 20,
            minimumLevel: .warning
        )
        XCTAssertTrue(warningLines.contains { $0.contains("[WARN] [InputTrace]") })
        XCTAssertTrue(warningLines.contains { $0.contains("[ERROR] [\(category)]") })
        XCTAssertFalse(warningLines.contains { $0.contains("[INFO] [\(category)]") })
        XCTAssertFalse(warningLines.contains { $0.contains("[INFO] [InputTrace]") })

        let deltaLines = await RuntimeDiagnostics.shared.readRecentLines(
            limit: 20,
            minimumLevel: .info,
            since: snapshot
        )
        let scopedDeltaLines = deltaLines.filter { $0.contains("[\(category)]") }
        XCTAssertEqual(scopedDeltaLines.count, 1)
        XCTAssertTrue(scopedDeltaLines[0].contains("[ERROR]"))

        RuntimeDiagnostics.shared.clear()
        let clearedLines = await RuntimeDiagnostics.shared.readRecentLines(limit: 20, minimumLevel: .debug)
        XCTAssertFalse(clearedLines.contains { $0.contains("[\(category)]") })
    }
}
