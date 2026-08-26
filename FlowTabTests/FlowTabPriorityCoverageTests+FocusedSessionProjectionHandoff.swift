import AppKit
import FlowTabCore
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testLiveSwitcherModelDirtyFocusedWindowSessionWaitsForStrictlyLaterCompleteProjection() {
        let runningApp = NSRunningApplication.current
        let appID = "com.flowtab.tests.focused-session-handoff"
        let retainedWindow = WindowCandidate(
            id: "focused-handoff-1",
            title: "Focused Handoff One",
            isMinimized: false,
            lastActiveAt: 20
        )
        let addedWindow = WindowCandidate(
            id: "focused-handoff-2",
            title: "Focused Handoff Two",
            isMinimized: false,
            lastActiveAt: 30
        )
        let service = RecordingRuntimeProjectionService(
            currentAppWindowProjectionsByAppID: [
                appID: makeFocusedSessionHandoffProjection(
                    appID: appID,
                    runningApp: runningApp,
                    windows: [retainedWindow],
                    generatedAt: 10,
                    isCompleteForScope: false
                )
            ]
        )
        let model = LiveSwitcherModel(runtimeProjectionService: service)

        guard case .awaitingFreshProjection(let pending) =
            model.startFocusedAppWindowSession(
                triggerDirection: .forward
            )
        else {
            return XCTFail("Dirty focused projection must defer the session")
        }
        XCTAssertNil(model.session)
        XCTAssertEqual(
            service.selectedCurrentAppWindowChangeSignalsRecorded()
                .map(\.appID),
            [appID]
        )

        let sameGenerationProjection = makeFocusedSessionHandoffProjection(
            appID: appID,
            runningApp: runningApp,
            windows: [addedWindow, retainedWindow],
            generatedAt: 10,
            isCompleteForScope: true
        )
        service.setFocusedCurrentAppWindowProjectionRead(
            RuntimeFocusedCurrentAppWindowProjectionRead(
                appID: appID,
                pid: runningApp.processIdentifier,
                projection: sameGenerationProjection
            )
        )
        XCTAssertFalse(
            model.completePendingFocusedAppWindowSession(pending)
        )
        XCTAssertNil(model.session)

        let freshProjection = makeFocusedSessionHandoffProjection(
            appID: appID,
            runningApp: runningApp,
            windows: [addedWindow, retainedWindow],
            generatedAt: 20,
            isCompleteForScope: true
        )
        service.setCurrentAppWindowProjection(freshProjection, appID: appID)
        service.setFocusedCurrentAppWindowProjectionRead(
            RuntimeFocusedCurrentAppWindowProjectionRead(
                appID: appID,
                pid: runningApp.processIdentifier,
                projection: freshProjection
            )
        )
        XCTAssertTrue(
            model.completePendingFocusedAppWindowSession(pending)
        )
        XCTAssertEqual(
            model.session?.mode,
            .windowCycle(appID: appID)
        )
        XCTAssertEqual(
            model.session?.selectedApp.windows.map(\.id),
            [addedWindow.id, retainedWindow.id]
        )
    }

    @MainActor
    func testFocusedWindowSessionPendingPresentationCancelsWhenControlIsReleased() {
        let fixture = makePendingFocusedSessionControllerFixture()
        let inputSource = ManualHotkeyInputSource()
        inputSource.register(
            on: fixture.controller,
            for: .inAppWindowSwitcher
        )

        inputSource.deliver(
            HotkeyInputEvent(
                identity: HotkeyInputEventIdentity(
                    sourceID: inputSource.sourceID,
                    sequence: 1
                ),
                phase: .pressed,
                isBackward: false,
                holdSetPressedEvidence: true
            ),
            to: fixture.controller,
            for: .inAppWindowSwitcher
        )
        XCTAssertTrue(
            fixture.controller.hasPendingFocusedWindowSessionForTesting
        )
        XCTAssertEqual(fixture.scheduler.pendingCount, 1)
        XCTAssertNil(fixture.controller.modelForTesting.session)

        inputSource.deliver(
            HotkeyInputEvent(
                identity: HotkeyInputEventIdentity(
                    sourceID: inputSource.sourceID,
                    sequence: 2
                ),
                phase: .released,
                isBackward: false,
                holdSetPressedEvidence: false
            ),
            to: fixture.controller,
            for: .inAppWindowSwitcher
        )

        XCTAssertFalse(
            fixture.controller.hasPendingFocusedWindowSessionForTesting
        )
        XCTAssertEqual(fixture.scheduler.pendingCount, 0)
        XCTAssertNil(fixture.controller.modelForTesting.session)
    }

    @MainActor
    func testFocusedWindowSessionPendingPresentationWatchdogKeepsPanelClosed() {
        let fixture = makePendingFocusedSessionControllerFixture()
        fixture.controller.inAppHotkeyHoldSetPressedOverride = true

        fixture.controller.showInAppWindowSwitcher(
            direction: .forward,
            initialKeyInput: .tabForward
        )

        XCTAssertTrue(
            fixture.controller.hasPendingFocusedWindowSessionForTesting
        )
        XCTAssertEqual(
            fixture.scheduler.scheduledIntervals,
            [FocusedWindowSessionFreshnessObservationOwner.watchdogInterval]
        )
        XCTAssertTrue(fixture.scheduler.fireNext())
        XCTAssertFalse(
            fixture.controller.hasPendingFocusedWindowSessionForTesting
        )
        XCTAssertFalse(fixture.controller.isPanelPresented)
        XCTAssertNil(fixture.controller.modelForTesting.session)
    }

    @MainActor
    private func makePendingFocusedSessionControllerFixture() -> (
        controller: SwitcherPanelController,
        scheduler: ManualFocusedWindowSessionFreshnessScheduler
    ) {
        let runningApp = NSRunningApplication.current
        let appID = "com.flowtab.tests.focused-session-pending"
        let projection = makeFocusedSessionHandoffProjection(
            appID: appID,
            runningApp: runningApp,
            windows: [
                WindowCandidate(
                    id: "pending-focused-window",
                    title: "Pending Focused Window",
                    isMinimized: false,
                    lastActiveAt: 10
                )
            ],
            generatedAt: 10,
            isCompleteForScope: false
        )
        let service = RecordingRuntimeProjectionService(
            currentAppWindowProjectionsByAppID: [appID: projection]
        )
        let scheduler = ManualFocusedWindowSessionFreshnessScheduler()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(runtimeProjectionService: service),
            focusedWindowSessionFreshnessScheduler: scheduler
        )
        controller.panelVisibilityOverride = false
        controller.hideNonPanelWindowsOverride = {}
        return (controller, scheduler)
    }

    private func makeFocusedSessionHandoffProjection(
        appID: String,
        runningApp: NSRunningApplication,
        windows: [WindowCandidate],
        generatedAt: TimeInterval,
        isCompleteForScope: Bool
    ) -> RuntimeCurrentAppWindowProjection {
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: "Focused Session Handoff",
            groupID: "focused-session-handoff",
            lastActiveAt: generatedAt,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            windows: windows
        )
        return RuntimeCurrentAppWindowProjection(
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
                appDirectoryEntries: [
                    RuntimeAppDirectoryEntry(app: runningApp)
                ]
            ),
            freshness: RuntimeProjectionFreshness(
                generatedAt: generatedAt,
                sourceGeneration: RuntimeReadModelGeneration(
                    projection: UInt64(generatedAt)
                ),
                dirtyAppIDs: isCompleteForScope ? [] : [appID],
                dirtyPIDs: isCompleteForScope
                    ? []
                    : [runningApp.processIdentifier],
                dirtyCGWindowIDs: [],
                pendingRepairScopes: isCompleteForScope
                    ? []
                    : ["appWindows:\(appID)"],
                isCompleteForScope: isCompleteForScope
            )
        )
    }
}

@MainActor
private final class ManualFocusedWindowSessionFreshnessScheduler:
    FocusedWindowSessionFreshnessScheduling
{
    private struct ScheduledAction {
        let interval: TimeInterval
        let token: ManualFocusedWindowSessionFreshnessToken
        let action: @MainActor @Sendable () -> Void
    }

    private var scheduled: [ScheduledAction] = []

    var pendingCount: Int {
        scheduled.filter(\.token.isAvailable).count
    }

    var scheduledIntervals: [TimeInterval] {
        scheduled.map(\.interval)
    }

    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any FocusedWindowSessionFreshnessCancellable {
        let token = ManualFocusedWindowSessionFreshnessToken()
        scheduled.append(
            ScheduledAction(
                interval: interval,
                token: token,
                action: action
            )
        )
        return token
    }

    @discardableResult
    func fireNext() -> Bool {
        guard let scheduledAction = scheduled.first(where: {
            $0.token.isAvailable
        }) else {
            return false
        }
        scheduledAction.token.markFired()
        scheduledAction.action()
        return true
    }
}

@MainActor
private final class ManualFocusedWindowSessionFreshnessToken:
    FocusedWindowSessionFreshnessCancellable
{
    private(set) var isCancelled = false
    private(set) var didFire = false

    var isAvailable: Bool {
        !isCancelled && !didFire
    }

    func markFired() {
        didFire = true
    }

    func cancel() {
        isCancelled = true
    }
}
