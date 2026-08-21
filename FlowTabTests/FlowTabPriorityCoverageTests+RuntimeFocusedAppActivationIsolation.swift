import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    func testUITestFrontmostProjectionOverrideRoutesFocusedReadsAndRefreshesToTarget() throws {
        let runningApp = NSRunningApplication.current
        let appID = "com.example.fixture.chrome"
        let baseService = makeCurrentAppWindowProjectionService(
            appID: appID,
            runningApp: runningApp,
            windows: [
                WindowCandidate(
                    id: "fixture-window",
                    title: "Fixture Window",
                    isMinimized: false,
                    lastActiveAt: 10
                )
            ]
        )
        let target = RuntimeUITestFrontmostAppTarget(
            appID: appID,
            pid: runningApp.processIdentifier,
            bundleIdentifier: "com.example.fixture.chrome"
        )
        let service = RuntimeUITestFrontmostProjectionService(
            baseService: baseService,
            targetProvider: { target }
        )

        let focusedRead = try XCTUnwrap(service.readFocusedCurrentAppWindowProjection())
        XCTAssertEqual(focusedRead.appID, appID)
        XCTAssertEqual(focusedRead.pid, runningApp.processIdentifier)
        XCTAssertEqual(
            focusedRead.projection?.currentAppWindowPayload.candidate.windows.map { $0.id },
            ["fixture-window"]
        )

        service.signalFocusedCurrentAppWindowsChanged()
        let selectedSignals = baseService.selectedCurrentAppWindowChangeSignalsRecorded()
        XCTAssertEqual(selectedSignals.count, 1)
        XCTAssertEqual(selectedSignals.first?.appID, appID)
        XCTAssertEqual(selectedSignals.first?.pid, runningApp.processIdentifier)

        service.signalAppActivated(
            appID: "com.example.unrelated",
            pid: 18_406,
            appDirectoryEntry: RuntimeAppDirectoryEntry(
                pid: 18_406,
                appID: "com.example.unrelated",
                bundleIdentifier: "com.example.unrelated",
                localizedName: "Unrelated",
                launchDate: nil,
                activationRank: 0
            )
        )
        XCTAssertTrue(baseService.appActivationSignalsRecorded().isEmpty)
        XCTAssertEqual(
            baseService.selectedCurrentAppWindowChangeSignalsRecorded().map(\.appID),
            [appID, appID]
        )
    }
}
