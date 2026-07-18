import AppKit
import FlowTabCore
import XCTest
@testable import FlowTab

private final class RetainingTerminatedAppRuntimeProjectionService:
    RuntimeProjectionServing,
    @unchecked Sendable
{
    private let recording: RecordingRuntimeProjectionService
    private let lock = NSLock()
    private var terminationSignals: [(appID: String, pid: pid_t)] = []

    init(recording: RecordingRuntimeProjectionService) {
        self.recording = recording
    }

    func appTerminationSignalsRecorded() -> [(appID: String, pid: pid_t)] {
        lock.lock()
        defer { lock.unlock() }
        return terminationSignals
    }

    func readAppSwitcherProjection() -> RuntimeAppSwitcherProjection? {
        recording.readAppSwitcherProjection()
    }

    func readHomeSummaryProjection() -> RuntimeHomeSummaryProjection? {
        recording.readHomeSummaryProjection()
    }

    func readHomeAppDetailProjection(appID: String) -> RuntimeHomeAppDetailProjection? {
        recording.readHomeAppDetailProjection(appID: appID)
    }

    func readCurrentAppWindowProjection(appID: String) -> RuntimeCurrentAppWindowProjection? {
        recording.readCurrentAppWindowProjection(appID: appID)
    }

    func readFocusedCurrentAppWindowProjection() -> RuntimeFocusedCurrentAppWindowProjectionRead? {
        recording.readFocusedCurrentAppWindowProjection()
    }

    func readActivationTargetProjection() -> RuntimeActivationTargetProjection? {
        recording.readActivationTargetProjection()
    }

    func readSpaceTopologyProjection() -> RuntimeSpaceTopologyProjection? {
        recording.readSpaceTopologyProjection()
    }

    func readCommittedSearchIndexForSearch() -> RuntimeSearchIndexRead {
        recording.readCommittedSearchIndexForSearch()
    }

    func runtimeReadModelDiagnostics() -> RuntimeReadModelDiagnostics {
        recording.runtimeReadModelDiagnostics()
    }

    func requestAppSwitcherProjectionMaintenance(reason: RuntimeProjectionMaintenanceReason) {
        recording.requestAppSwitcherProjectionMaintenance(reason: reason)
    }

    func requestSearchIndexFreshnessBarrier(reason: RuntimeProjectionMaintenanceReason) {
        recording.requestSearchIndexFreshnessBarrier(reason: reason)
    }

    func signalSpaceTopologyChanged() {
        recording.signalSpaceTopologyChanged()
    }

    func signalAppLaunched(
        appID: String,
        pid: pid_t,
        appDirectoryEntry: RuntimeAppDirectoryEntry?
    ) {
        recording.signalAppLaunched(
            appID: appID,
            pid: pid,
            appDirectoryEntry: appDirectoryEntry
        )
    }

    func signalAppWindowsChanged(appID: String, pid: pid_t) {
        recording.signalAppWindowsChanged(appID: appID, pid: pid)
    }

    func signalSelectedCurrentAppWindowsChanged(appID: String, pid: pid_t) {
        recording.signalSelectedCurrentAppWindowsChanged(appID: appID, pid: pid)
    }

    func signalFocusedCurrentAppWindowsChanged() {
        recording.signalFocusedCurrentAppWindowsChanged()
    }

    func signalAXWindowDestroyed(appID: String, pid: pid_t, axWindowID: String) {
        recording.signalAXWindowDestroyed(appID: appID, pid: pid, axWindowID: axWindowID)
    }

    func signalAppTerminated(appID: String, pid: pid_t) {
        lock.lock()
        terminationSignals.append((appID, pid))
        lock.unlock()
    }

    func signalWindowFocusVerified(_ verification: RuntimeWindowFocusVerification) {
        recording.signalWindowFocusVerified(verification)
    }

    func signalWindowFocusVerified(appID: String, pid: pid_t) {
        recording.signalWindowFocusVerified(appID: appID, pid: pid)
    }

    func signalWindowFocusReadbackMismatch(_ diagnostic: WindowBindingReadbackDiagnostic) {
        recording.signalWindowFocusReadbackMismatch(diagnostic)
    }
}

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testLiveSwitcherModelPreservesActiveWindowCycleAcrossDegradedAppProjectionRefresh() {
        let appID = "com.example.degraded-window-cycle-refresh"
        let runningApp = NSRunningApplication.current
        let windows = [
            WindowCandidate(
                id: "window-one",
                title: "Window One",
                isMinimized: false,
                lastActiveAt: 20
            ),
            WindowCandidate(
                id: "window-two",
                title: "Window Two",
                isMinimized: false,
                lastActiveAt: 10
            )
        ]
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: "Degraded Window Cycle",
            groupID: "degraded-window-cycle",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            windows: windows
        )
        let completeFreshness = RuntimeProjectionFreshness(
            generatedAt: 10,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let degradedFreshness = RuntimeProjectionFreshness(
            generatedAt: 11,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [appID],
            dirtyPIDs: [runningApp.processIdentifier],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: ["spaceTopology"],
            isCompleteForScope: false
        )
        let currentProjection = RuntimeCurrentAppWindowProjection(
            appID: appID,
            currentAppWindowPayload: RuntimeCurrentAppWindowPayload(
                summary: RuntimeHomeAppSummary(
                    appID: appID,
                    displayName: candidate.displayName,
                    groupID: candidate.groupID,
                    lastActiveAt: candidate.lastActiveAt,
                    windowCount: windows.count,
                    pid: runningApp.processIdentifier
                ),
                candidate: candidate,
                context: context,
                appDirectoryEntries: [RuntimeAppDirectoryEntry(app: runningApp)]
            ),
            freshness: degradedFreshness
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [candidate],
                contextsByID: [appID: context],
                freshness: completeFreshness
            ),
            currentAppWindowProjectionsByAppID: [appID: currentProjection]
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        model.runtimeProjectionMaintenanceEnabled = false

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        model.handle(.downArrow)
        model.handle(.rightArrow)
        XCTAssertEqual(model.session?.selectedWindow?.id, "window-two")

        runtimeProjectionService.installAppSwitcherProjection(
            apps: [
                AppSwitchCandidate(
                    id: candidate.id,
                    displayName: candidate.displayName,
                    groupID: candidate.groupID,
                    lastActiveAt: candidate.lastActiveAt,
                    windows: []
                )
            ],
            contextsByID: [
                appID: makeRuntimeAppContext(
                    appID: appID,
                    runningApp: runningApp,
                    windows: []
                )
            ],
            generatedAt: 12
        )

        XCTAssertTrue(model.handleAppSwitcherProjectionDidUpdate())
        XCTAssertEqual(model.session?.selectedApp.windows.map(\.id), ["window-one", "window-two"])
        XCTAssertEqual(model.session?.selectedWindow?.id, "window-two")
        XCTAssertEqual(
            Set(model.runtimeContextsByID[appID]?.windowsByID.keys.map { $0 } ?? []),
            Set(windows.map(\.id))
        )
    }

    @MainActor
    func testLiveSwitcherModelFiltersTerminatedAppFromDegradedRuntimeProjection() {
        let apps = terminateScenarioApps()
        let terminatedApp = apps[1]
        let runningApp = NSRunningApplication.current
        let context = makeRuntimeAppContext(
            appID: terminatedApp.id,
            runningApp: runningApp,
            windows: terminatedApp.windows
        )
        let recordingService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: apps,
                contextsByID: [terminatedApp.id: context],
                freshness: RuntimeProjectionFreshness(
                    generatedAt: 10,
                    sourceGeneration: RuntimeReadModelGeneration(projection: 1),
                    dirtyAppIDs: [terminatedApp.id],
                    dirtyPIDs: [runningApp.processIdentifier],
                    dirtyCGWindowIDs: [],
                    pendingRepairScopes: ["appTerminated:\(terminatedApp.id)"],
                    isCompleteForScope: false
                )
            )
        )
        let runtimeProjectionService = RetainingTerminatedAppRuntimeProjectionService(
            recording: recordingService
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertEqual(model.selectedApp?.id, terminatedApp.id)

        XCTAssertTrue(
            model.handleApplicationTerminated(
                appID: terminatedApp.id,
                pid: runningApp.processIdentifier
            )
        )

        XCTAssertTrue(
            runtimeProjectionService.readAppSwitcherProjection()?.apps.contains {
                $0.id == terminatedApp.id
            } ?? false,
            "The degraded committed projection must remain available to non-Switcher consumers."
        )
        XCTAssertFalse(
            model.session?.apps.contains { $0.id == terminatedApp.id } ?? true,
            "A confirmed process termination must not be reintroduced into the active Switcher session by a degraded projection."
        )
        XCTAssertEqual(
            runtimeProjectionService.appTerminationSignalsRecorded().map(\.appID),
            [terminatedApp.id]
        )
        model.cancelSelection()
    }

    @MainActor
    func testSwitcherPanelControllerTerminationRefreshPreservesRequestInterruptionProtection() {
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherApps: terminateScenarioApps()
        )
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        )

        XCTAssertTrue(controller.modelForTesting.startSession(triggerDirection: .forward))
        let terminatedAppID = controller.modelForTesting.selectedApp?.id
        controller.beginTerminateInterruptionProtection(trigger: "terminate_request_test")
        XCTAssertTrue(controller.shouldProtectTerminateSystemInterruption())
        let requestProtectionDeadline = controller.terminateInterruptionProtectionUntil

        guard let terminatedAppID else {
            XCTFail("Expected selected app before workspace terminate refresh")
            return
        }
        controller.handleWorkspaceApplicationTerminatedForTesting(
            appID: terminatedAppID,
            pid: 42_302
        )

        XCTAssertGreaterThanOrEqual(
            controller.terminateInterruptionProtectionUntil,
            requestProtectionDeadline,
            "Workspace termination refresh must preserve the request protection deadline so late system interruptions cannot close the active switcher session."
        )
        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertFalse(
            controller.modelForTesting.session?.apps.contains { $0.id == terminatedAppID } ?? true
        )
        controller.cancelSelectionForTesting()
    }
}
