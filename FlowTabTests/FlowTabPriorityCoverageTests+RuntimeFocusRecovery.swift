import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testFocusRecoveryCompletesFromImmediateInitialReadbackAndCleansUp() {
        let scheduler = ManualRuntimeFocusRecoveryScheduler()
        let notificationCenter = NotificationCenter()
        let workspaceNotificationCenter = NotificationCenter()
        let coordinator = RuntimeFocusRecoveryCoordinator(
            scheduler: scheduler,
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
        var triggers: [RuntimeFocusRecoveryTrigger] = []

        let generation = coordinator.start(
            target: focusRecoveryTarget(appID: "com.example.initial"),
            policy: focusRecoveryPolicy
        ) { trigger in
            triggers.append(trigger)
            return self.focusRecoveryReadback(conditionSatisfied: true)
        }

        XCTAssertNotNil(generation)
        XCTAssertEqual(scheduler.pendingIntervals.sorted(), [0.1, 2])
        coordinator.performInitialReadback(generation: generation!)
        XCTAssertEqual(triggers, [.initialReadback])
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)

        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: self
        )
        XCTAssertEqual(triggers, [.initialReadback])
    }

    @MainActor
    func testFocusRecoveryObserverExistsBeforeActionAndConsumesExactAppEvent() {
        let scheduler = ManualRuntimeFocusRecoveryScheduler()
        let notificationCenter = NotificationCenter()
        let workspaceNotificationCenter = NotificationCenter()
        let coordinator = RuntimeFocusRecoveryCoordinator(
            scheduler: scheduler,
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
        let currentApp = NSRunningApplication.current
        var conditionSatisfied = false
        var triggers: [RuntimeFocusRecoveryTrigger] = []
        let target = focusRecoveryTarget(
            appID: "com.example.event",
            pid: currentApp.processIdentifier
        )

        let generation = coordinator.start(
            target: target,
            policy: focusRecoveryPolicy
        ) { trigger in
            triggers.append(trigger)
            return self.focusRecoveryReadback(
                conditionSatisfied: conditionSatisfied
            )
        }

        conditionSatisfied = true
        workspaceNotificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: self,
            userInfo: [NSWorkspace.applicationUserInfoKey: currentApp]
        )

        XCTAssertNotNil(generation)
        XCTAssertEqual(triggers, [.targetApplicationActivated])
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
    }

    @MainActor
    func testFocusRecoverySupersessionRejectsStaleAndOutOfOrderNotifications() {
        let scheduler = ManualRuntimeFocusRecoveryScheduler()
        let notificationCenter = NotificationCenter()
        let coordinator = RuntimeFocusRecoveryCoordinator(
            scheduler: scheduler,
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: NotificationCenter()
        )
        var firstTriggers: [RuntimeFocusRecoveryTrigger] = []
        var secondTriggers: [RuntimeFocusRecoveryTrigger] = []
        var secondConditionSatisfied = false

        _ = coordinator.start(
            target: focusRecoveryTarget(appID: "com.example.first"),
            policy: focusRecoveryPolicy
        ) { trigger in
            firstTriggers.append(trigger)
            return self.focusRecoveryReadback(conditionSatisfied: false)
        }
        _ = coordinator.start(
            target: focusRecoveryTarget(appID: "com.example.second"),
            policy: focusRecoveryPolicy
        ) { trigger in
            secondTriggers.append(trigger)
            return self.focusRecoveryReadback(
                conditionSatisfied: secondConditionSatisfied
            )
        }

        notificationCenter.post(
            name: .runtimeCurrentAppWindowProjectionDidUpdate,
            object: self,
            userInfo: [
                RuntimeProjectionNotificationUserInfoKey.appID:
                    "com.example.first"
            ]
        )
        XCTAssertTrue(firstTriggers.isEmpty)
        XCTAssertTrue(secondTriggers.isEmpty)

        notificationCenter.post(
            name: .runtimeCurrentAppWindowProjectionDidUpdate,
            object: self,
            userInfo: [
                RuntimeProjectionNotificationUserInfoKey.appID:
                    "com.example.second"
            ]
        )
        secondConditionSatisfied = true
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: self
        )
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: self
        )

        XCTAssertTrue(firstTriggers.isEmpty)
        XCTAssertEqual(
            secondTriggers,
            [
                .currentAppWindowProjectionUpdated,
                .appSwitcherProjectionUpdated
            ]
        )
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
    }

    @MainActor
    func testFocusRecoveryPollingCadenceChangesLatencyOnly() {
        for intervals in [[0.1, 0.3], [3.0, 7.0]] {
            let scheduler = ManualRuntimeFocusRecoveryScheduler()
            let coordinator = RuntimeFocusRecoveryCoordinator(
                scheduler: scheduler,
                notificationCenter: NotificationCenter(),
                workspaceNotificationCenter: NotificationCenter()
            )
            var pollingCount = 0
            var triggers: [RuntimeFocusRecoveryTrigger] = []
            let policy = RuntimeFocusRecoveryPolicy(
                pollingIntervals: intervals,
                watchdogInterval: 20
            )

            let generation = coordinator.start(
                target: focusRecoveryTarget(appID: "com.example.polling"),
                policy: policy
            ) { trigger in
                triggers.append(trigger)
                if trigger.permitsRecoveryAction {
                    pollingCount += 1
                }
                return self.focusRecoveryReadback(
                    conditionSatisfied: pollingCount == 2
                )
            }
            coordinator.performInitialReadback(generation: generation!)
            scheduler.fireNext(after: intervals[0])
            scheduler.fireNext(after: intervals[1])

            XCTAssertEqual(
                triggers,
                [
                    .initialReadback,
                    .polling(attempt: 1),
                    .polling(attempt: 2)
                ]
            )
            XCTAssertEqual(pollingCount, 2)
            XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
        }
    }

    @MainActor
    func testFocusRecoveryCancellationRemovesObserversAndScheduledWork() {
        let scheduler = ManualRuntimeFocusRecoveryScheduler()
        let notificationCenter = NotificationCenter()
        let coordinator = RuntimeFocusRecoveryCoordinator(
            scheduler: scheduler,
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: NotificationCenter()
        )
        var triggers: [RuntimeFocusRecoveryTrigger] = []
        let generation = coordinator.start(
            target: focusRecoveryTarget(appID: "com.example.cancel"),
            policy: focusRecoveryPolicy
        ) { trigger in
            triggers.append(trigger)
            return self.focusRecoveryReadback(conditionSatisfied: false)
        }
        coordinator.performInitialReadback(generation: generation!)

        coordinator.cancel(reason: "test")
        scheduler.fireAll()
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: self
        )

        XCTAssertEqual(triggers, [.initialReadback])
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
    }

    @MainActor
    func testFocusRecoveryWatchdogReportsFinalUnmetObservation() {
        let scheduler = ManualRuntimeFocusRecoveryScheduler()
        let coordinator = RuntimeFocusRecoveryCoordinator(
            scheduler: scheduler,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        let target = focusRecoveryTarget(appID: "com.example.watchdog")
        let lastObservation = RuntimeFocusRecoveryObservation(
            conditionSatisfied: false,
            processIsTerminated: false,
            targetIsVisible: true,
            focusedCGWindowID: 700,
            frontmostCGWindowID: 701,
            visibleCGWindowIDs: [700, 701]
        )
        var failures: [RuntimeFocusRecoveryFailure] = []
        var triggers: [RuntimeFocusRecoveryTrigger] = []
        coordinator.onFailure = { failures.append($0) }

        let generation = coordinator.start(
            target: target,
            policy: focusRecoveryPolicy
        ) { trigger in
            triggers.append(trigger)
            return RuntimeFocusRecoveryReadback(
                completed: false,
                observation: lastObservation
            )
        }
        coordinator.performInitialReadback(generation: generation!)
        scheduler.fireNext(after: 2)

        XCTAssertEqual(
            triggers,
            [.initialReadback, .watchdogReadback]
        )
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures[0].reason, .watchdogExpired)
        XCTAssertEqual(failures[0].lastTrigger, .watchdogReadback)
        XCTAssertEqual(failures[0].lastObservation, lastObservation)
        XCTAssertEqual(failures[0].target, target)
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
    }

    @MainActor
    func testFocusRecoveryWatchdogFinalReadbackCanStillComplete() {
        let scheduler = ManualRuntimeFocusRecoveryScheduler()
        let coordinator = RuntimeFocusRecoveryCoordinator(
            scheduler: scheduler,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        var conditionSatisfied = false
        var failures: [RuntimeFocusRecoveryFailure] = []
        coordinator.onFailure = { failures.append($0) }

        let generation = coordinator.start(
            target: focusRecoveryTarget(appID: "com.example.boundary"),
            policy: focusRecoveryPolicy
        ) { _ in
            self.focusRecoveryReadback(
                conditionSatisfied: conditionSatisfied
            )
        }
        coordinator.performInitialReadback(generation: generation!)
        conditionSatisfied = true
        scheduler.fireNext(after: 2)

        XCTAssertTrue(failures.isEmpty)
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
    }

    @MainActor
    func testFocusRecoveryTerminatesOnlyForExactTargetProcess() {
        let scheduler = ManualRuntimeFocusRecoveryScheduler()
        let workspaceNotificationCenter = NotificationCenter()
        let coordinator = RuntimeFocusRecoveryCoordinator(
            scheduler: scheduler,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: workspaceNotificationCenter
        )
        let currentApp = NSRunningApplication.current
        var failures: [RuntimeFocusRecoveryFailure] = []
        coordinator.onFailure = { failures.append($0) }
        let target = focusRecoveryTarget(
            appID: "com.example.termination",
            pid: currentApp.processIdentifier
        )

        _ = coordinator.start(
            target: target,
            policy: focusRecoveryPolicy
        ) { trigger in
            self.focusRecoveryReadback(
                conditionSatisfied: false,
                processIsTerminated:
                    trigger == .targetApplicationTerminated
            )
        }
        workspaceNotificationCenter.post(
            name: NSWorkspace.didTerminateApplicationNotification,
            object: self,
            userInfo: [NSWorkspace.applicationUserInfoKey: currentApp]
        )

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(
            failures[0].reason,
            .targetApplicationTerminated
        )
        XCTAssertTrue(failures[0].lastObservation.processIsTerminated)
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
    }

    @MainActor
    func testFocusRecoveryInitialReadbackDetectsAlreadyTerminatedProcess() {
        let scheduler = ManualRuntimeFocusRecoveryScheduler()
        let coordinator = RuntimeFocusRecoveryCoordinator(
            scheduler: scheduler,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        var failures: [RuntimeFocusRecoveryFailure] = []
        coordinator.onFailure = { failures.append($0) }

        let generation = coordinator.start(
            target: focusRecoveryTarget(appID: "com.example.already-terminated"),
            policy: focusRecoveryPolicy
        ) { _ in
            self.focusRecoveryReadback(
                conditionSatisfied: false,
                processIsTerminated: true
            )
        }
        coordinator.performInitialReadback(generation: generation!)

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(
            failures[0].reason,
            .targetApplicationTerminated
        )
        XCTAssertEqual(failures[0].lastTrigger, .initialReadback)
        XCTAssertTrue(failures[0].lastObservation.processIsTerminated)
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
    }

}
