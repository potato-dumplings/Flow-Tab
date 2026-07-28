import AppKit
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testTemporaryActivationRestorationCompletesFromInitialReadback() {
        let window = TestAppWindow(
            isPanelWindow: false,
            isMiniaturized: false,
            isVisible: true
        )
        let application = TestAppWindowApplication(
            isHidden: false,
            isActive: true,
            appWindows: [window]
        )
        let activationPolicyApplication =
            TestActivationPolicyApplication(initialPolicy: .regular)
        let scheduler = ManualTemporaryActivationScheduler()
        let owner = TemporaryRegularActivationRestorationOwner(
            generation: 1,
            application: application,
            window: window,
            activationPolicyApplication: activationPolicyApplication,
            scheduler: scheduler
        )
        var presentationCount = 0
        var outcomes: [TemporaryRegularActivationRestorationOutcome] = []

        owner.start(
            requestPresentation: {
                presentationCount += 1
            },
            onOutcome: {
                outcomes.append($0)
            }
        )

        XCTAssertEqual(presentationCount, 0)
        XCTAssertEqual(outcomes.count, 1)
        guard case let .stable(evidence) = outcomes.first else {
            return XCTFail("Expected stable initial evidence.")
        }
        XCTAssertEqual(evidence.source, .initialReadback)
        XCTAssertEqual(application.activeActivationEvidenceObserverCount, 0)
        XCTAssertEqual(window.activePresentationEvidenceObserverCount, 0)
        XCTAssertEqual(scheduler.activeEntryCount, 0)
    }

    @MainActor
    func testTemporaryActivationRestorationInstallsObserversBeforePresentationReadback() {
        let window = TestAppWindow(
            isPanelWindow: false,
            isMiniaturized: true,
            isVisible: false
        )
        let application = TestAppWindowApplication(
            isHidden: false,
            isActive: false,
            appWindows: [window]
        )
        let activationPolicyApplication =
            TestActivationPolicyApplication(initialPolicy: .regular)
        let scheduler = ManualTemporaryActivationScheduler()
        let owner = TemporaryRegularActivationRestorationOwner(
            generation: 2,
            application: application,
            window: window,
            activationPolicyApplication: activationPolicyApplication,
            scheduler: scheduler
        )
        var didObserveBeforePresentation = false
        var outcomes: [TemporaryRegularActivationRestorationOutcome] = []

        owner.start(
            requestPresentation: {
                didObserveBeforePresentation =
                    application.activeActivationEvidenceObserverCount == 1
                    && window.activePresentationEvidenceObserverCount == 1
                application.flowTabIsActive = true
                window.isMiniaturized = false
                window.isVisible = true
            },
            onOutcome: {
                outcomes.append($0)
            }
        )

        XCTAssertTrue(didObserveBeforePresentation)
        XCTAssertEqual(outcomes.count, 1)
        guard case let .stable(evidence) = outcomes.first else {
            return XCTFail("Expected presentation readback evidence.")
        }
        XCTAssertEqual(evidence.source, .presentationReadback)
        XCTAssertEqual(scheduler.activeEntryCount, 0)
    }

    @MainActor
    func testTemporaryActivationRestorationUsesExactOutOfOrderEvidenceOnce() {
        let window = TestAppWindow(
            isPanelWindow: false,
            isMiniaturized: true,
            isVisible: false
        )
        let unrelatedWindow = TestAppWindow(
            isPanelWindow: false,
            isMiniaturized: false,
            isVisible: false
        )
        let application = TestAppWindowApplication(
            isHidden: false,
            isActive: false,
            appWindows: [window, unrelatedWindow]
        )
        let activationPolicyApplication =
            TestActivationPolicyApplication(initialPolicy: .regular)
        let scheduler = ManualTemporaryActivationScheduler()
        let owner = TemporaryRegularActivationRestorationOwner(
            generation: 3,
            application: application,
            window: window,
            activationPolicyApplication: activationPolicyApplication,
            scheduler: scheduler
        )
        var outcomes: [TemporaryRegularActivationRestorationOutcome] = []

        owner.start(
            requestPresentation: {},
            onOutcome: {
                outcomes.append($0)
            }
        )

        unrelatedWindow.isVisible = true
        unrelatedWindow.emitPresentationEvidence(.windowDidBecomeKey)
        XCTAssertTrue(outcomes.isEmpty)

        window.isMiniaturized = false
        window.isVisible = true
        window.emitPresentationEvidence(.windowDidBecomeKey)
        XCTAssertTrue(outcomes.isEmpty)

        application.flowTabIsActive = true
        application.emitActivationEvidence(.applicationDidBecomeActive)
        window.emitPresentationEvidence(.windowDidBecomeMain)
        application.emitActivationEvidence(.applicationDidBecomeActive)

        XCTAssertEqual(outcomes.count, 1)
        guard case let .stable(evidence) = outcomes.first else {
            return XCTFail("Expected stable activation evidence.")
        }
        XCTAssertEqual(evidence.source, .applicationDidBecomeActive)
    }

    @MainActor
    func testTemporaryActivationRestorationCancellationStopsEveryOwnedWait() {
        let context = makePendingTemporaryActivationContext(generation: 4)
        var outcomes: [TemporaryRegularActivationRestorationOutcome] = []

        context.owner.start(
            requestPresentation: {},
            onOutcome: {
                outcomes.append($0)
            }
        )
        context.owner.cancel()

        context.application.flowTabIsActive = true
        context.window.isVisible = true
        context.application.emitActivationEvidence(.applicationDidBecomeActive)
        context.window.emitPresentationEvidence(.windowDidBecomeKey)
        context.scheduler.runAllActiveEntries()

        XCTAssertTrue(outcomes.isEmpty)
        XCTAssertFalse(context.owner.isObserving)
        XCTAssertEqual(
            context.application.activeActivationEvidenceObserverCount,
            0
        )
        XCTAssertEqual(
            context.window.activePresentationEvidenceObserverCount,
            0
        )
        XCTAssertEqual(context.scheduler.activeEntryCount, 0)
    }

    @MainActor
    func testTemporaryActivationFallbackCadenceChangesElapsedTimeOnly() {
        for elapsedMilliseconds in [25.0, 2_500.0] {
            let context = makePendingTemporaryActivationContext(
                generation: UInt64(elapsedMilliseconds)
            )
            var presentationCount = 0
            var outcomes: [
                TemporaryRegularActivationRestorationOutcome
            ] = []

            context.owner.start(
                requestPresentation: {
                    presentationCount += 1
                },
                onOutcome: {
                    outcomes.append($0)
                }
            )
            context.application.flowTabIsActive = true
            context.window.isMiniaturized = false
            context.window.isVisible = true
            context.clock.monotonicMilliseconds = elapsedMilliseconds

            XCTAssertTrue(
                context.scheduler.runFirstActiveEntry(after: 0.5)
            )
            XCTAssertEqual(presentationCount, 1)
            XCTAssertEqual(outcomes.count, 1)
            guard case let .stable(evidence) = outcomes.first else {
                return XCTFail("Expected fallback readback evidence.")
            }
            XCTAssertEqual(evidence.source, .fallbackReadback)
            XCTAssertEqual(
                evidence.elapsedMilliseconds,
                elapsedMilliseconds,
                accuracy: 0.001
            )
        }
    }

    @MainActor
    func testTemporaryActivationFallbackRetriesPresentationConditionally() {
        let context = makePendingTemporaryActivationContext(generation: 5)
        var presentationCount = 0
        var outcomes: [TemporaryRegularActivationRestorationOutcome] = []

        context.owner.start(
            requestPresentation: {
                presentationCount += 1
                context.window.isMiniaturized = false
            },
            onOutcome: {
                outcomes.append($0)
            }
        )
        context.window.isMiniaturized = true

        XCTAssertTrue(
            context.scheduler.runFirstActiveEntry(after: 0.5)
        )
        XCTAssertEqual(presentationCount, 2)
        XCTAssertTrue(outcomes.isEmpty)

        context.application.flowTabIsActive = true
        context.window.isMiniaturized = false
        context.window.isVisible = true
        XCTAssertTrue(
            context.scheduler.runFirstActiveEntry(after: 0.5)
        )

        XCTAssertEqual(presentationCount, 2)
        XCTAssertEqual(outcomes.count, 1)
        guard case let .stable(evidence) = outcomes.first else {
            return XCTFail("Expected a stable fallback outcome.")
        }
        XCTAssertEqual(evidence.source, .fallbackReadback)
    }

    @MainActor
    func testTemporaryActivationWatchdogReportsFinalUnsatisfiedEvidence() {
        let context = makePendingTemporaryActivationContext(generation: 6)
        var outcomes: [TemporaryRegularActivationRestorationOutcome] = []

        context.owner.start(
            requestPresentation: {},
            onOutcome: {
                outcomes.append($0)
            }
        )
        context.application.flowTabIsActive = true
        context.window.isMiniaturized = true
        context.clock.monotonicMilliseconds = 5_000

        XCTAssertTrue(
            context.scheduler.runFirstActiveEntry(after: 5)
        )
        XCTAssertEqual(outcomes.count, 1)
        guard case let .watchdogExpired(evidence) = outcomes.first else {
            return XCTFail("Expected watchdog failure evidence.")
        }
        XCTAssertEqual(evidence.source, .watchdogReadback)
        XCTAssertTrue(evidence.applicationIsActive)
        XCTAssertFalse(evidence.windowIsVisible)
        XCTAssertTrue(evidence.windowIsMiniaturized)
        XCTAssertEqual(evidence.activationPolicy, .regular)
        XCTAssertTrue(evidence.logFields.contains("appActive=true"))
        XCTAssertTrue(evidence.logFields.contains("windowVisible=false"))
        XCTAssertEqual(context.scheduler.activeEntryCount, 0)
    }

    @MainActor
    func testTemporaryActivationRepeatedSupersessionPressureKeepsOneOwnerSet() {
        let context = makePendingTemporaryActivationContext(generation: 7)
        var presentationCount = 0
        var outcomeCount = 0

        for _ in 0..<2_000 {
            context.owner.start(
                requestPresentation: {
                    presentationCount += 1
                },
                onOutcome: { _ in
                    outcomeCount += 1
                }
            )
        }

        XCTAssertEqual(presentationCount, 2_000)
        XCTAssertEqual(outcomeCount, 0)
        XCTAssertEqual(
            context.application.activeActivationEvidenceObserverCount,
            1
        )
        XCTAssertEqual(
            context.window.activePresentationEvidenceObserverCount,
            1
        )
        XCTAssertEqual(context.scheduler.activeEntryCount, 2)

        context.owner.cancel()
        XCTAssertEqual(context.scheduler.activeEntryCount, 0)
        XCTAssertEqual(
            context.application.activeActivationEvidenceObserverCount,
            0
        )
        XCTAssertEqual(
            context.window.activePresentationEvidenceObserverCount,
            0
        )
    }

    @MainActor
    private func makePendingTemporaryActivationContext(
        generation: UInt64
    ) -> PendingTemporaryActivationContext {
        let window = TestAppWindow(
            isPanelWindow: false,
            isMiniaturized: true,
            isVisible: false
        )
        let application = TestAppWindowApplication(
            isHidden: false,
            isActive: false,
            appWindows: [window]
        )
        let activationPolicyApplication =
            TestActivationPolicyApplication(initialPolicy: .regular)
        let scheduler = ManualTemporaryActivationScheduler()
        let clock = ManualTemporaryActivationClock()
        let owner = TemporaryRegularActivationRestorationOwner(
            generation: generation,
            application: application,
            window: window,
            activationPolicyApplication: activationPolicyApplication,
            scheduler: scheduler,
            clock: clock,
            policy: TemporaryRegularActivationRestorationPolicy(
                fallbackReadbackInterval: 0.5,
                watchdogInterval: 5
            )
        )
        return PendingTemporaryActivationContext(
            owner: owner,
            application: application,
            window: window,
            scheduler: scheduler,
            clock: clock
        )
    }
}

@MainActor
private struct PendingTemporaryActivationContext {
    let owner: TemporaryRegularActivationRestorationOwner
    let application: TestAppWindowApplication
    let window: TestAppWindow
    let scheduler: ManualTemporaryActivationScheduler
    let clock: ManualTemporaryActivationClock
}

@MainActor
private final class ManualTemporaryActivationClock:
    TemporaryRegularActivationClockReading
{
    var monotonicMilliseconds: Double = 0
}

private final class ManualTemporaryActivationToken:
    TemporaryRegularActivationCancellable
{
    private(set) var isCancelled = false
    private(set) var hasRun = false

    func cancel() {
        isCancelled = true
    }

    func markRun() {
        hasRun = true
    }
}

@MainActor
private final class ManualTemporaryActivationScheduler:
    TemporaryRegularActivationScheduling
{
    private struct Entry {
        let interval: TimeInterval
        let token: ManualTemporaryActivationToken
        let action: @MainActor @Sendable () -> Void
    }

    private var entries: [Entry] = []

    var activeEntryCount: Int {
        entries.filter {
            !$0.token.isCancelled && !$0.token.hasRun
        }.count
    }

    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any TemporaryRegularActivationCancellable {
        let token = ManualTemporaryActivationToken()
        entries.append(
            Entry(interval: interval, token: token, action: action)
        )
        return token
    }

    @discardableResult
    func runFirstActiveEntry(after interval: TimeInterval) -> Bool {
        guard let entry = entries.first(where: {
            !$0.token.isCancelled
                && !$0.token.hasRun
                && $0.interval == interval
        }) else {
            return false
        }
        entry.token.markRun()
        entry.action()
        return true
    }

    func runAllActiveEntries() {
        let activeEntries = entries.filter {
            !$0.token.isCancelled && !$0.token.hasRun
        }
        for entry in activeEntries {
            entry.token.markRun()
            entry.action()
        }
    }
}
