import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testLiveSwitcherModelHandleApplicationTerminatedRefreshesSessionAndKeepsPreferredNextSelection() {
        let terminatedAppID = "com.example.code"
        let terminatedPID: pid_t = 42_300
        let initialApps = terminateScenarioApps()
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: initialApps)
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        assertAppSwitcherProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: 1
        )
        XCTAssertEqual(model.selectedApp?.id, terminatedAppID)

        var layoutRefreshCount = 0
        model.onSessionLayoutChanged = { layoutRefreshCount += 1 }
        defer {
            model.onSessionLayoutChanged = nil
            model.cancelSelection()
        }
        XCTAssertEqual(layoutRefreshCount, 0)

        XCTAssertTrue(
            model.handleApplicationTerminated(appID: terminatedAppID, pid: terminatedPID)
        )

        XCTAssertEqual(
            layoutRefreshCount,
            1,
            "unmetCondition=terminationLayoutPublished finalLayoutRefreshCount=\(layoutRefreshCount)"
        )
        let terminationSignals = runtimeProjectionService.appTerminationSignalsRecorded()
        XCTAssertEqual(terminationSignals.map(\.appID), [terminatedAppID])
        XCTAssertEqual(terminationSignals.map(\.pid), [terminatedPID])
        assertAppSwitcherProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: 2
        )
        XCTAssertEqual(model.appCount, 2)
        XCTAssertEqual(model.session?.apps.map(\.id), ["com.example.mail", "com.example.browser"])
        XCTAssertEqual(model.selectedApp?.id, "com.example.browser")
    }

    @MainActor
    func testLiveSwitcherModelHandleApplicationTerminatedIgnoresUntrackedApp() {
        let initialApps = terminateScenarioApps()
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: initialApps)
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        defer { model.cancelSelection() }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        assertAppSwitcherProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: 1
        )
        let selectedAppID = model.selectedApp?.id

        XCTAssertFalse(
            model.handleApplicationTerminated(appID: "com.example.unrelated", pid: 99_999)
        )

        XCTAssertTrue(runtimeProjectionService.appTerminationSignalsRecorded().isEmpty)
        assertAppSwitcherProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: 1
        )
        XCTAssertEqual(model.appCount, initialApps.count)
        XCTAssertEqual(model.selectedApp?.id, selectedAppID)
    }

    private func assertAppSwitcherProjectionRead(
        from runtimeProjectionService: RecordingRuntimeProjectionService,
        expectedReadCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherProjectionReadCount(),
            expectedReadCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded(),
            [.switcherSessionStarted],
            file: file,
            line: line
        )
    }
}
