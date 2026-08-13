import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testSwitcherPanelControllerCurrentAppProjectionCommitRefreshesFrozenWindowLayerPreview() {
        let initialWindows = [
            WindowCandidate(
                id: "open-layer-1",
                title: "Open Layer One",
                isMinimized: false,
                lastActiveAt: 30
            ),
            WindowCandidate(
                id: "open-layer-2",
                title: "Open Layer Two",
                isMinimized: false,
                lastActiveAt: 20
            )
        ]
        let fixture = makeManualWindowLayerProjectionRefreshFixture(
            appID: "com.example.open-layer-mutation",
            displayName: "Open Layer Mutation",
            initialWindows: initialWindows
        )

        XCTAssertTrue(
            fixture.controller.beginGlobalHotkeySessionForTesting()
        )
        fixture.controller.advance(.downArrow)
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .appCycle
        )
        XCTAssertTrue(
            fixture.controller.manualWindowLayerEntryObservationOwner
                .isObserving
        )

        XCTAssertTrue(
            fixture.publishCurrentProjection(
                windows: initialWindows,
                projectionGeneration: 2
            )
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .windowCycle(appID: fixture.appID)
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting
                .windowPreviewSnapshotForTesting().map(\.id),
            ["open-layer-1", "open-layer-2"]
        )

        XCTAssertTrue(
            fixture.publishCurrentProjection(
                windows: [initialWindows[0]],
                projectionGeneration: 3
            )
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?
                .selectedApp.windows.map(\.id),
            ["open-layer-1"]
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting
                .windowPreviewSnapshotForTesting().map(\.id),
            ["open-layer-1"]
        )
        fixture.controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerCurrentAppProjectionCommitKeepsWindowLayerWhenSelectedWindowIsRemoved() {
        let initialWindows = [
            WindowCandidate(
                id: "open-layer-remaining",
                title: "Open Layer Remaining",
                isMinimized: false,
                lastActiveAt: 30
            ),
            WindowCandidate(
                id: "open-layer-removed",
                title: "Open Layer Removed",
                isMinimized: false,
                lastActiveAt: 20
            )
        ]
        let fixture = makeManualWindowLayerProjectionRefreshFixture(
            appID: "com.example.open-layer-selected-removed",
            displayName: "Open Layer Selected Removed",
            initialWindows: initialWindows
        )

        XCTAssertTrue(
            fixture.controller.beginGlobalHotkeySessionForTesting()
        )
        fixture.controller.advance(.downArrow)
        XCTAssertTrue(
            fixture.publishCurrentProjection(
                windows: initialWindows,
                projectionGeneration: 2
            )
        )
        fixture.controller.advance(.rightArrow)
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .windowCycle(appID: fixture.appID)
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?
                .selectedWindow?.id,
            "open-layer-removed"
        )

        XCTAssertTrue(
            fixture.publishCurrentProjection(
                windows: [initialWindows[0]],
                projectionGeneration: 3
            )
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .windowCycle(appID: fixture.appID)
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?
                .selectedWindow?.id,
            "open-layer-remaining"
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting
                .windowPreviewSnapshotForTesting().map(\.id),
            ["open-layer-remaining"]
        )
        fixture.controller.cancelSelectionForTesting()
    }
}

private struct ManualWindowLayerProjectionRefreshFixture {
    let appID: String
    let displayName: String
    let runningApp: NSRunningApplication
    let runtimeService: RecordingRuntimeProjectionService
    let controller: SwitcherPanelController

    @MainActor
    func publishCurrentProjection(
        windows: [WindowCandidate],
        projectionGeneration: UInt64
    ) -> Bool {
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: "open-layer",
            lastActiveAt: 100,
            windows: windows
        )
        let projection = RuntimeCurrentAppWindowProjection(
            appID: appID,
            currentAppWindowPayload: RuntimeCurrentAppWindowPayload(
                summary: RuntimeHomeAppSummary(
                    appID: appID,
                    displayName: displayName,
                    groupID: "open-layer",
                    lastActiveAt: 100,
                    windowCount: windows.count,
                    pid: runningApp.processIdentifier
                ),
                candidate: candidate,
                context: makeManualWindowLayerRuntimeContext(
                    appID: appID,
                    runningApp: runningApp,
                    windows: windows
                ),
                appDirectoryEntries: [
                    RuntimeAppDirectoryEntry(app: runningApp)
                ]
            ),
            freshness: RuntimeProjectionFreshness(
                generatedAt: TimeInterval(projectionGeneration),
                sourceGeneration: RuntimeReadModelGeneration(
                    projection: projectionGeneration
                ),
                dirtyAppIDs: [],
                dirtyPIDs: [],
                dirtyCGWindowIDs: [],
                pendingRepairScopes: [],
                isCompleteForScope: true
            )
        )
        runtimeService.setCurrentAppWindowProjection(
            projection,
            appID: appID
        )
        return controller
            .handleCurrentAppWindowProjectionDidUpdateForTesting(
                appID: appID,
                evidence:
                    RuntimeCurrentAppWindowProjectionUpdateEvidence(
                        projection: projection
                    )
            )
    }
}

private extension FlowTabPriorityCoverageTests {
    @MainActor
    func makeManualWindowLayerProjectionRefreshFixture(
        appID: String,
        displayName: String,
        initialWindows: [WindowCandidate]
    ) -> ManualWindowLayerProjectionRefreshFixture {
        let runningApp = NSRunningApplication.current
        let initialCandidate = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: "open-layer",
            lastActiveAt: 100,
            windows: initialWindows
        )
        let runtimeService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [initialCandidate],
                contextsByID: [
                    appID: makeManualWindowLayerRuntimeContext(
                        appID: appID,
                        runningApp: runningApp,
                        windows: initialWindows
                    )
                ],
                freshness: RuntimeProjectionFreshness(
                    generatedAt: 1,
                    sourceGeneration: RuntimeReadModelGeneration(
                        projection: 1
                    ),
                    dirtyAppIDs: [],
                    dirtyPIDs: [],
                    dirtyCGWindowIDs: [],
                    pendingRepairScopes: [],
                    isCompleteForScope: true
                )
            )
        )
        return ManualWindowLayerProjectionRefreshFixture(
            appID: appID,
            displayName: displayName,
            runningApp: runningApp,
            runtimeService: runtimeService,
            controller: SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: runtimeService
                )
            )
        )
    }
}

private func makeManualWindowLayerRuntimeContext(
    appID: String,
    runningApp: NSRunningApplication,
    windows: [WindowCandidate]
) -> RuntimeAppContext {
    RuntimeAppContext(
        appID: appID,
        runningApp: runningApp,
        windowsByID: Dictionary(
            uniqueKeysWithValues: windows.map { window in
                (
                    window.id,
                    RuntimeWindowContext(
                        id: window.id,
                        title: window.title,
                        isMinimized: window.isMinimized,
                        ownerPID: runningApp.processIdentifier,
                        cgWindowID: nil,
                        inferredTitleBarStyle: nil
                    )
                )
            }
        )
    )
}
