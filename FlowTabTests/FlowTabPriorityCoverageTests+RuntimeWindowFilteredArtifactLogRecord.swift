import AppKit
import CoreGraphics
import FlowTabCore
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testFilteredArtifactLogRecordsBindCountsToExactProcessIdentifiers() {
        let records =
            RuntimeWindowFilteredArtifactLogRecord.records(
                appName: "Chrome Fixture",
                kind: .fullscreenHostArtifacts,
                stage: "presentation",
                droppedEntries: [
                    filteredArtifactEntry(
                        processIdentifier: 4_322,
                        windowNumber: 202
                    ),
                    filteredArtifactEntry(
                        processIdentifier: 4_321,
                        windowNumber: 101
                    ),
                    filteredArtifactEntry(
                        processIdentifier: 4_321,
                        windowNumber: 102
                    )
                ]
            )

        XCTAssertEqual(
            records,
            [
                RuntimeWindowFilteredArtifactLogRecord(
                    appName: "Chrome Fixture",
                    processIdentifier: 4_321,
                    kind: .fullscreenHostArtifacts,
                    stage: "presentation",
                    droppedCount: 2
                ),
                RuntimeWindowFilteredArtifactLogRecord(
                    appName: "Chrome Fixture",
                    processIdentifier: 4_322,
                    kind: .fullscreenHostArtifacts,
                    stage: "presentation",
                    droppedCount: 1
                )
            ]
        )
        XCTAssertEqual(
            records.map(\.logMessage),
            [
                "Chrome Fixture filtered-fullscreen-host-artifacts "
                    + "stage=presentation dropped=2 pid=4321",
                "Chrome Fixture filtered-fullscreen-host-artifacts "
                    + "stage=presentation dropped=1 pid=4322"
            ]
        )
    }

    func testFilteredArtifactLogRecordsRequirePositiveProcessIdentity() {
        XCTAssertTrue(
            RuntimeWindowFilteredArtifactLogRecord.records(
                appName: "Chrome Fixture",
                kind: .cgOnlyCoveredByActivation,
                stage:
                    "read-model-current-app-normalization",
                droppedEntries: [
                    filteredArtifactEntry(
                        processIdentifier: 0,
                        windowNumber: 101
                    )
                ]
            )
            .isEmpty
        )
    }

    func testRepeatedFullscreenTitleFilterKeepsExactCurrentDesktopWindowsWithoutSiblingTopology() {
        let processIdentifier: pid_t = 6_520
        let frame = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let firstWindowID = CGWindowID(107_289)
        let secondWindowID = CGWindowID(84_479)
        let entries = [firstWindowID, secondWindowID].enumerated().map {
            index,
            windowID in
            RuntimeWindowListEntry(
                windowID: "cg:\(processIdentifier):\(windowID)",
                title: "Shared Window Title",
                isMinimized: false,
                ownerPID: processIdentifier,
                cgWindowID: windowID,
                activationHandleID: "ax:\(processIdentifier):\(index)",
                frame: frame.offsetBy(dx: CGFloat(index), dy: CGFloat(index)),
                spaceIDs: [1],
                isOnscreen: true,
                lastConfirmationSource: .privateExactBridge
            )
        }
        let knownCGWindowsByID = Dictionary(
            uniqueKeysWithValues: entries.compactMap { entry in
                entry.cgWindowID.map { windowID in
                    (
                        windowID,
                        RuntimeCGWindowEntry(
                            id: windowID,
                            title: entry.title,
                            bounds: entry.frame,
                            isOnscreen: true,
                            alpha: 1,
                            storeType: 1,
                            spaceIDs: [1]
                        )
                    )
                }
            }
        )

        let filtered = RuntimeWindowPresentationFilter
            .filterRepeatedFullscreenPresentationTitles(
                entries,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: "Multi Window App",
                hasFullscreenTopology: false,
                stage: "unit"
            )

        XCTAssertEqual(filtered.map(\.windowID), entries.map(\.windowID))
    }

    func testResolvedWindowEntriesKeepAppNameFallbackWindowAcrossExactBridgeRefreshes() throws {
        let processIdentifier: pid_t = 6_520
        let appName = "Multi Window App"
        let frame = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let fallbackWindowID = CGWindowID(84_479)
        let titledWindowID = CGWindowID(107_289)
        let fallbackAXWindowID = "ax:\(processIdentifier):0"
        let titledAXWindowID = "ax:\(processIdentifier):1"
        let axWindows: [RuntimeAXWindowEntry] = [
            .init(
                id: fallbackAXWindowID,
                index: 0,
                title: appName,
                bounds: frame
            ),
            .init(
                id: titledAXWindowID,
                index: 1,
                title: "Project Beta",
                bounds: frame
            )
        ]
        let cgWindows: [RuntimeCGWindowEntry] = [
            .init(
                id: fallbackWindowID,
                title: nil,
                bounds: frame,
                isOnscreen: true,
                spaceIDs: [1]
            ),
            .init(
                id: titledWindowID,
                title: nil,
                bounds: frame,
                isOnscreen: true,
                spaceIDs: [1]
            )
        ]

        let refreshes = RuntimeWindowMappingTestSupport
            .resolveWindowEntriesAcrossRefreshes(
                axWindows: axWindows,
                cgWindows: cgWindows,
                exactBridgeMatches: [
                    fallbackAXWindowID: fallbackWindowID,
                    titledAXWindowID: titledWindowID
                ],
                refreshCount: 2,
                pid: processIdentifier,
                appName: appName
            )
        let firstRefresh = try XCTUnwrap(refreshes.first)
        let secondRefresh = try XCTUnwrap(refreshes.last)

        XCTAssertEqual(Set(firstRefresh.compactMap(\.cgWindowID)), [fallbackWindowID, titledWindowID])
        XCTAssertEqual(Set(secondRefresh.compactMap(\.cgWindowID)), [fallbackWindowID, titledWindowID])
        XCTAssertEqual(
            secondRefresh.first { $0.cgWindowID == fallbackWindowID }?.lastConfirmationSource,
            .privateExactBridge
        )
    }

    func testReadModelKeepsOnscreenExactAppNameFallbackWindow() throws {
        let runningApp = NSRunningApplication.current
        let processIdentifier = runningApp.processIdentifier
        let appID = "com.flowtab.fixture.app-name-fallback"
        let appName = "Chrome Fixture"
        let frame = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let windowFacts: [(id: String, title: String, cgWindowID: CGWindowID)] = [
            ("fixture-alpha", appName, 207_032),
            ("fixture-beta", "Project Beta", 207_033)
        ]
        let windows = windowFacts.enumerated().map { index, fact in
            WindowCandidate(
                id: fact.id,
                title: fact.title,
                isMinimized: false,
                lastActiveAt: TimeInterval(20 - index)
            )
        }
        let contextsByWindowID = Dictionary(
            uniqueKeysWithValues: windowFacts.enumerated().map { index, fact in
                (
                    fact.id,
                    RuntimeWindowContext(
                        id: fact.id,
                        title: fact.title,
                        isMinimized: false,
                        ownerPID: processIdentifier,
                        cgWindowID: fact.cgWindowID,
                        spaceIDs: [1],
                        activationHandleID: "ax:\(processIdentifier):\(index)",
                        frame: frame,
                        isOnscreen: true,
                        lastConfirmationSource: .privateExactBridge
                    )
                )
            }
        )
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: appName,
            groupID: "fixture",
            lastActiveAt: 20,
            windows: windows
        )
        let store = RuntimeReadModelStore()

        store.commitMainTableAppSwitcherProjectionPayload(
            RuntimeAppSwitcherProjectionPayload(
                apps: [candidate],
                contextsByID: [
                    appID: RuntimeAppContext(
                        appID: appID,
                        runningApp: runningApp,
                        ownerPID: processIdentifier,
                        windowsByID: contextsByWindowID
                    )
                ],
                hasCompleteWindowCoverage: true
            ),
            generatedAt: 20
        )

        let projection = try XCTUnwrap(store.readAppSwitcherProjection())
        XCTAssertEqual(projection.apps.first?.windows.map(\.id), windowFacts.map(\.id))
        XCTAssertEqual(projection.apps.first?.windows.count, 2)
        XCTAssertEqual(
            projection.contextsByID[appID]?.windowsByID.values.filter(\.isOnscreen).count,
            2
        )
    }

    func testStickyBindingVerificationConfirmsCurrentPrivateExactBridge() {
        let fixture = stickyBindingVerificationFixture()

        withStickyBindingBridgeResult(fixture.record.cgWindowID) {
            switch RuntimeAXWindowRecovery.verifyStickyBinding(
                record: fixture.record,
                reusedAXWindow: fixture.axWindow,
                validCGWindowIDs: [fixture.record.cgWindowID]
            ) {
            case .exactPrivateBridge:
                break
            case .unavailable, .conflict:
                XCTFail("Expected the current private bridge to preserve exact identity")
            }
        }
    }

    func testStickyBindingVerificationFallsBackWhenPrivateBridgeIsUnavailableOrOutsideCurrentCGSet() {
        let fixture = stickyBindingVerificationFixture()
        let bridgeResults: [CGWindowID?] = [nil, 999_001]

        for bridgeResult in bridgeResults {
            withStickyBindingBridgeResult(bridgeResult) {
                switch RuntimeAXWindowRecovery.verifyStickyBinding(
                    record: fixture.record,
                    reusedAXWindow: fixture.axWindow,
                    validCGWindowIDs: [fixture.record.cgWindowID]
                ) {
                case .unavailable:
                    break
                case .exactPrivateBridge, .conflict:
                    XCTFail("Expected unavailable evidence for bridge result \(String(describing: bridgeResult))")
                }
            }
        }

        var state = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: [fixture.record.cgWindowID: fixture.record]
        )
        withStickyBindingBridgeResult(nil) {
            _ = state.applyReusableStickyBindings(
                axWindows: [fixture.axWindow],
                validCGWindowIDs: [fixture.record.cgWindowID],
                knownCGWindowsByID: [:],
                appName: "Multi Window App",
                observedAt: 20
            )
        }
        XCTAssertEqual(
            state.windowRecordsByCGWindowID[fixture.record.cgWindowID]?.lastConfirmationSource,
            .stickyBinding
        )
    }

    func testStickyBindingVerificationReportsConflictingCurrentPrivateExactBridge() {
        let fixture = stickyBindingVerificationFixture()
        let conflictingCGWindowID = CGWindowID(999_002)

        withStickyBindingBridgeResult(conflictingCGWindowID) {
            switch RuntimeAXWindowRecovery.verifyStickyBinding(
                record: fixture.record,
                reusedAXWindow: fixture.axWindow,
                validCGWindowIDs: [fixture.record.cgWindowID, conflictingCGWindowID]
            ) {
            case let .conflict(diagnostic):
                XCTAssertEqual(
                    diagnostic,
                    WindowBindingDiagnostic(
                        stableWindowID: fixture.record.stableWindowID,
                        axWindowID: fixture.axWindow.id,
                        cgWindowID: conflictingCGWindowID,
                        confidence: .ambiguous,
                        source: .privateExactBridge,
                        reason: .privateExactBridgeConflictsWithStickyBinding,
                        candidateCount: 2,
                        allowedActions: [.quarantineOnly]
                    )
                )
            case .exactPrivateBridge, .unavailable:
                XCTFail("Expected a conflicting valid private bridge diagnostic")
            }
        }
    }

    private func filteredArtifactEntry(
        processIdentifier: pid_t,
        windowNumber: CGWindowID
    ) -> RuntimeWindowListEntry {
        RuntimeWindowListEntry(
            windowID:
                "cg:\(processIdentifier):\(windowNumber)",
            title: "Artifact",
            isMinimized: false,
            ownerPID: processIdentifier,
            cgWindowID: windowNumber
        )
    }

    private func stickyBindingVerificationFixture() -> (
        record: RuntimeWindowRecord,
        axWindow: RuntimeAXWindowEntry
    ) {
        let processIdentifier: pid_t = 6_520
        let cgWindowID = CGWindowID(84_479)
        let axWindow = RuntimeAXWindowEntry(
            id: "ax:\(processIdentifier):0",
            index: 0,
            title: "Multi Window App",
            bounds: CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        )
        var record = RuntimeWindowRecord(
            cgWindowID: cgWindowID,
            stableWindowID: RuntimeWindowListEntry.cgStableWindowID(
                pid: processIdentifier,
                cgWindowID: cgWindowID
            ),
            firstSeenAt: 10
        )
        record.lastKnownDisplayTitle = axWindow.title
        record.lastKnownCGFrame = axWindow.frame
        record.lastExactAXWindowID = axWindow.id
        return (record, axWindow)
    }

    private func withStickyBindingBridgeResult(
        _ cgWindowID: CGWindowID?,
        perform: () -> Void
    ) {
        let previousOverride = AXWindowInspector.cgWindowIDOverrideForTesting
        AXWindowInspector.cgWindowIDOverrideForTesting = { _ in cgWindowID }
        defer { AXWindowInspector.cgWindowIDOverrideForTesting = previousOverride }
        perform()
    }
}
