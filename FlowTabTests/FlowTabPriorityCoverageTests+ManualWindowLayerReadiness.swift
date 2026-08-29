import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testSwitcherPanelControllerManualWindowLayerEntryUsesAlreadyCompleteProjectionWithoutRepair() {
        let fixture = makeManualWindowLayerReadinessFixture(
            currentWindowIDs: ["fullscreen", "normal"],
            sourceGeneration: RuntimeReadModelGeneration(
                space: 3,
                projection: 5
            ),
            isCompleteForScope: true
        )

        XCTAssertTrue(
            fixture.controller.beginGlobalHotkeySessionForTesting()
        )
        fixture.controller.advance(.downArrow)

        XCTAssertTrue(
            fixture.runtimeService
                .selectedCurrentAppWindowChangeSignalsRecorded()
                .isEmpty
        )
        XCTAssertFalse(
            fixture.controller.manualWindowLayerEntryObservationOwner
                .isObserving
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .windowCycle(appID: fixture.appID)
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?
                .selectedApp.windows.map(\.id),
            ["fullscreen", "normal"]
        )
        fixture.controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerManualWindowLayerEntryAcceptsCompleteZeroWindowProjectionWithoutRepair() {
        let fixture = makeManualWindowLayerReadinessFixture(
            currentWindowIDs: [],
            sourceGeneration: RuntimeReadModelGeneration(
                space: 3,
                projection: 5
            ),
            isCompleteForScope: true
        )

        XCTAssertTrue(
            fixture.controller.beginGlobalHotkeySessionForTesting()
        )
        fixture.controller.advance(.downArrow)

        XCTAssertTrue(
            fixture.runtimeService
                .selectedCurrentAppWindowChangeSignalsRecorded()
                .isEmpty
        )
        XCTAssertFalse(
            fixture.controller.manualWindowLayerEntryObservationOwner
                .isObserving
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .appCycle
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?
                .selectedApp.windows.map(\.id),
            []
        )
        fixture.controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerManualWindowLayerEntryWaitsForLaterCompleteProjectionOrderingEvidence() {
        let fixture = makeManualWindowLayerReadinessFixture(
            currentWindowIDs: ["normal", "fullscreen"],
            sourceGeneration: RuntimeReadModelGeneration(
                space: 3,
                projection: 5
            ),
            isCompleteForScope: false
        )
        var observedBeforeSignal = false
        fixture.runtimeService
            .setSelectedCurrentAppWindowChangeSignalHandler {
                [weak controller = fixture.controller] _, _ in
                observedBeforeSignal = controller?
                    .manualWindowLayerEntryObservationOwner
                    .isObserving == true
            }

        XCTAssertTrue(
            fixture.controller.beginGlobalHotkeySessionForTesting()
        )
        fixture.controller.advance(.downArrow)

        XCTAssertTrue(observedBeforeSignal)
        XCTAssertEqual(
            fixture.runtimeService
                .selectedCurrentAppWindowChangeSignalsRecorded()
                .map(\.appID),
            [fixture.appID]
        )
        XCTAssertTrue(
            fixture.controller.manualWindowLayerEntryObservationOwner
                .isObserving
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .appCycle
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?
                .selectedApp.windows.map(\.id),
            ["normal", "fullscreen"]
        )

        let laterGeneration = RuntimeReadModelGeneration(
            space: 4,
            projection: 6
        )
        fixture.runtimeService.setCurrentAppWindowProjection(
            fixture.currentProjection(
                windowIDs: ["fullscreen", "normal"],
                sourceGeneration: laterGeneration,
                isCompleteForScope: true
            ),
            appID: fixture.appID
        )
        XCTAssertFalse(
            fixture.controller
                .handleCurrentAppWindowProjectionDidUpdateForTesting(
                    appID: "com.example.unrelated",
                    evidence: RuntimeCurrentAppWindowProjectionUpdateEvidence(
                        appID: "com.example.unrelated",
                        processIdentifier: fixture.pid,
                        windowIDs: ["fullscreen", "normal"],
                        isCompleteForScope: true,
                        sourceGeneration: laterGeneration
                    )
                )
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .appCycle
        )

        XCTAssertTrue(
            fixture.controller
                .handleCurrentAppWindowProjectionDidUpdateForTesting(
                    appID: fixture.appID,
                    evidence: RuntimeCurrentAppWindowProjectionUpdateEvidence(
                        appID: fixture.appID,
                        processIdentifier: fixture.pid,
                        windowIDs: ["fullscreen", "normal"],
                        isCompleteForScope: true,
                        sourceGeneration: laterGeneration
                    )
                )
        )

        XCTAssertFalse(
            fixture.controller.manualWindowLayerEntryObservationOwner
                .isObserving
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .windowCycle(appID: fixture.appID)
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?
                .selectedApp.windows.map(\.id),
            ["fullscreen", "normal"]
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?
                .selectedWindow?.id,
            "fullscreen"
        )
        fixture.controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerManualWindowLayerEntryUsesSynchronousPostRequestProjection() {
        let fixture = makeManualWindowLayerReadinessFixture(
            currentWindowIDs: ["normal", "fullscreen"],
            sourceGeneration: RuntimeReadModelGeneration(
                space: 8,
                projection: 13
            ),
            isCompleteForScope: false
        )
        let laterProjection = fixture.currentProjection(
            windowIDs: ["fullscreen", "normal"],
            sourceGeneration: RuntimeReadModelGeneration(
                space: 9,
                projection: 14
            ),
            isCompleteForScope: true
        )
        let appID = fixture.appID
        fixture.runtimeService
            .setSelectedCurrentAppWindowChangeSignalHandler {
                [weak runtimeService = fixture.runtimeService] _, _ in
                runtimeService?.setCurrentAppWindowProjection(
                    laterProjection,
                    appID: appID
                )
            }

        XCTAssertTrue(
            fixture.controller.beginGlobalHotkeySessionForTesting()
        )
        fixture.controller.advance(.downArrow)

        XCTAssertEqual(
            fixture.runtimeService
                .selectedCurrentAppWindowChangeSignalsRecorded()
                .map(\.appID),
            [fixture.appID]
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .windowCycle(appID: fixture.appID)
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?
                .selectedApp.windows.map(\.id),
            ["fullscreen", "normal"]
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?
                .selectedWindow?.id,
            "fullscreen"
        )
        fixture.controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerManualWindowLayerEntryCancelsWithPresentation() {
        let fixture = makeManualWindowLayerReadinessFixture(
            currentWindowIDs: ["normal", "fullscreen"],
            sourceGeneration: RuntimeReadModelGeneration(
                space: 21,
                projection: 34
            ),
            isCompleteForScope: false
        )

        XCTAssertTrue(
            fixture.controller.beginGlobalHotkeySessionForTesting()
        )
        fixture.controller.advance(.downArrow)
        XCTAssertTrue(
            fixture.controller.manualWindowLayerEntryObservationOwner
                .isObserving
        )

        fixture.controller.cancelSelectionForTesting()

        XCTAssertFalse(
            fixture.controller.manualWindowLayerEntryObservationOwner
                .isObserving
        )
    }

    @MainActor
    private func makeManualWindowLayerReadinessFixture(
        currentWindowIDs: [String],
        sourceGeneration: RuntimeReadModelGeneration,
        isCompleteForScope: Bool
    ) -> ManualWindowLayerReadinessFixture {
        let runningApp = NSRunningApplication.current
        let appID = "com.example.manual-window-readiness"
        let windowsByID = [
            "normal": WindowCandidate(
                id: "normal",
                title: "Normal Tab",
                isMinimized: false,
                lastActiveAt: 20
            ),
            "fullscreen": WindowCandidate(
                id: "fullscreen",
                title: "Fullscreen Tab",
                isMinimized: false,
                lastActiveAt: 30
            ),
        ]
        let staleWindows = ["normal", "fullscreen"].compactMap {
            windowsByID[$0]
        }
        let currentWindows = currentWindowIDs.compactMap {
            windowsByID[$0]
        }
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            windows: Array(windowsByID.values)
        )
        let staleCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Manual Window Readiness",
            groupID: "manual-window-readiness",
            lastActiveAt: 100,
            windows: staleWindows
        )
        let currentAppFreshness = RuntimeProjectionFreshness(
            generatedAt: 12,
            sourceGeneration: sourceGeneration,
            dirtyAppIDs: isCompleteForScope ? [] : [appID],
            dirtyPIDs: isCompleteForScope
                ? []
                : [runningApp.processIdentifier],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: isCompleteForScope
                ? []
                : ["selectedCurrentAppWindows:\(appID)"],
            isCompleteForScope: isCompleteForScope
        )
        let appSwitcherFreshness = RuntimeProjectionFreshness(
            generatedAt: 11,
            sourceGeneration: sourceGeneration,
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let currentPayload = ManualWindowLayerReadinessFixture.payload(
            appID: appID,
            runningApp: runningApp,
            windows: currentWindows,
            context: context
        )
        let runtimeService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [staleCandidate],
                contextsByID: [appID: context],
                freshness: appSwitcherFreshness
            ),
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    currentAppWindowPayload: currentPayload,
                    freshness: currentAppFreshness
                )
            ]
        )
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                windowRecencyTracker: RuntimeWindowRecencyTracker(),
                runtimeProjectionService: runtimeService
            )
        )
        controller.windowLayerPresentationDelayOverride = 30
        return ManualWindowLayerReadinessFixture(
            appID: appID,
            pid: runningApp.processIdentifier,
            runningApp: runningApp,
            windowsByID: windowsByID,
            context: context,
            runtimeService: runtimeService,
            controller: controller
        )
    }
}

private struct ManualWindowLayerReadinessFixture {
    let appID: String
    let pid: pid_t
    let runningApp: NSRunningApplication
    let windowsByID: [String: WindowCandidate]
    let context: RuntimeAppContext
    let runtimeService: RecordingRuntimeProjectionService
    let controller: SwitcherPanelController

    func currentProjection(
        windowIDs: [String],
        sourceGeneration: RuntimeReadModelGeneration,
        isCompleteForScope: Bool
    ) -> RuntimeCurrentAppWindowProjection {
        let windows = windowIDs.compactMap { windowsByID[$0] }
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 14,
            sourceGeneration: sourceGeneration,
            dirtyAppIDs: isCompleteForScope ? [] : [appID],
            dirtyPIDs: isCompleteForScope ? [] : [pid],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: isCompleteForScope
                ? []
                : ["selectedCurrentAppWindows:\(appID)"],
            isCompleteForScope: isCompleteForScope
        )
        return RuntimeCurrentAppWindowProjection(
            appID: appID,
            currentAppWindowPayload: Self.payload(
                appID: appID,
                runningApp: runningApp,
                windows: windows,
                context: context
            ),
            freshness: freshness
        )
    }

    static func payload(
        appID: String,
        runningApp: NSRunningApplication,
        windows: [WindowCandidate],
        context: RuntimeAppContext
    ) -> RuntimeCurrentAppWindowPayload {
        RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Manual Window Readiness",
                groupID: "manual-window-readiness",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: AppSwitchCandidate(
                id: appID,
                displayName: "Manual Window Readiness",
                groupID: "manual-window-readiness",
                lastActiveAt: 100,
                windows: windows
            ),
            context: context,
            appDirectoryEntries: [
                RuntimeAppDirectoryEntry(app: runningApp)
            ]
        )
    }
}
