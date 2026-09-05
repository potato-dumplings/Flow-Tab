import AppKit
import Combine
import FlowTabCore
import XCTest
@testable import FlowTab

@MainActor
final class ControlTabPressureLifecycleTests: XCTestCase {
    func testRepeatedBootstrapPreparationPreservesRunAndProjectionUntilRouteChanges() throws {
        ControlTabPressureBootstrap.stop()
        defer { ControlTabPressureBootstrap.stop() }
        func environment(_ suffix: String) -> [String: String] {
            let prefix = "flowtab.pressure.lifecycle.\(UUID().uuidString).\(suffix)"
            return [
                ControlTabPressureRoute.commandEnvironmentKey: prefix + ".command",
                ControlTabPressureRoute.commandAcknowledgementEnvironmentKey: prefix + ".command-ack",
                ControlTabPressureRoute.evidenceEnvironmentKey: prefix + ".evidence",
                ControlTabPressureRoute.evidenceAcknowledgementEnvironmentKey: prefix + ".evidence-ack"
            ]
        }
        let initialEnvironment = environment("first")
        ControlTabPressureBootstrap.prepareIfNeeded(environment: initialEnvironment)
        var firstRun = try XCTUnwrap(ControlTabPressureBootstrap.run) as ControlTabPressureRun?
        weak var releasedRun = firstRun
        let firstProjection = ControlTabPressureBootstrap.systemProjectionService
        ControlTabPressureBootstrap.prepareIfNeeded(environment: initialEnvironment)
        XCTAssertTrue(ControlTabPressureBootstrap.run === firstRun)
        XCTAssertTrue(ControlTabPressureBootstrap.systemProjectionService.notificationSource
            === firstProjection.notificationSource)
        ControlTabPressureBootstrap.prepareIfNeeded(environment: environment("second"))
        XCTAssertFalse(ControlTabPressureBootstrap.run === firstRun)
        XCTAssertFalse(ControlTabPressureBootstrap.systemProjectionService.notificationSource
            === firstProjection.notificationSource)
        firstRun = nil
        XCTAssertNil(releasedRun)
        weak var stoppedRun = ControlTabPressureBootstrap.run
        ControlTabPressureBootstrap.stop()
        XCTAssertNil(stoppedRun)
        ControlTabPressureBootstrap.prepareIfNeeded(environment: [:])
        XCTAssertNil(ControlTabPressureBootstrap.run)
    }

    func testInputDecoratorPreservesHoldEvidenceAndSynchronousReentry() {
        let base = PressureHotkeySpy()
        let recorder = ControlTabPressureSpanRecorder(clock: ControlTabSystemProcessCPUClock())
        var events: [HotkeyInputEvent] = []
        base.onHotkeyEvent = { event in
            events.append(event)
            if events.count == 1 {
                base.onHotkeyEvent?(.init(identity: .init(sourceID: base.inputSourceID, sequence: 9),
                    phase: .released, isBackward: true, holdSetPressedEvidence: false))
            }
        }
        let decorated = ControlTabPressureHotkeyMonitor(base: base, recorder: recorder)
        decorated.start()
        decorated.requireChordEventMonitoring()
        decorated.stop()
        decorated.dispatch(phase: .pressed, isBackward: false, holdSetPressedEvidence: true)
        XCTAssertEqual(events.map(\.identity.sequence), [1, 2])
        XCTAssertTrue(events.allSatisfy { $0.identity.sourceID == decorated.inputSourceID })
        XCTAssertEqual(events.map(\.phase), [.pressed, .released])
        XCTAssertEqual(events.map(\.isBackward), [false, true])
        XCTAssertEqual(events.map(\.holdSetPressedEvidence), [true, false])
        XCTAssertEqual(base.calls, ["start", "require", "stop"])
        let late = base.onHotkeyEvent
        decorated.uninstall()
        late?(.init(identity: .init(sourceID: base.inputSourceID, sequence: 99), phase: .pressed, isBackward: true))
        XCTAssertEqual(events.count, 2)
        base.onHotkeyEvent?(.init(identity: .init(sourceID: base.inputSourceID, sequence: 100), phase: .pressed, isBackward: true))
        XCTAssertEqual(events.last?.identity.sourceID, base.inputSourceID)
        XCTAssertEqual(events.last?.identity.sequence, 100)
    }

    func testSessionDecoratorPreservesNestedPublicationOrder() {
        let base = SwitcherSessionState()
        let diagnostics = ControlTabPressureModelDiagnostics()
        let decorated = ControlTabPressureSessionState(base: base, diagnostics: diagnostics)
        var states: [String] = []
        decorated.didPublish = { _, current in
            states.append(current?.selectedApp.id ?? "nil")
            if current != nil { decorated.publish(nil) }
        }
        decorated.publish(makeSession())
        XCTAssertEqual(states, ["app", "nil"])
        XCTAssertNil(base.session)
        XCTAssertEqual(diagnostics.renderGeneration, 2)
    }

    func testPanelAssemblyRestoresBusinessOwnersWhenReleased() {
        let controller = makeController()
        let original = controller.presentationCoordinator
        let events = controller.panelEventMonitoring
        let shell = controller.reusablePanelShell
        var assembly: ControlTabPressurePanelAssembly? = ControlTabPressurePanelAssembly(controller: controller)
        weak var released = assembly
        XCTAssertTrue(controller.presentationCoordinator is ControlTabPressurePanelPresentation)
        assembly = nil
        XCTAssertNil(released)
        XCTAssertTrue(controller.presentationCoordinator === original)
        XCTAssertTrue(controller.panelEventMonitoring === events)
        XCTAssertTrue(controller.reusablePanelShell === shell)
        controller.panel.orderOut(nil)
    }

    func testReusableShellCompletesAtActualExecution() async {
        let controller = makeController()
        let owner = SwitcherReusablePanelShell(controller: controller)
        let finished = expectation(description: "shell prepared")
        var results: [SwitcherReusablePanelShellResult] = []
        owner.prepare(contentSize: NSSize(width: 325, height: 175)) { result in
            results.append(result)
            XCTAssertEqual(controller.panel.contentRect(forFrameRect: controller.panel.frame).size,
                           NSSize(width: 325, height: 175))
            finished.fulfill()
        }
        XCTAssertTrue(results.isEmpty)
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(results, [.prepared])
        controller.panel.orderOut(nil)
    }

    func testReusableShellCancellationAndSupersessionAreSingleTerminalResults() async {
        let controller = makeController()
        let owner = SwitcherReusablePanelShell(controller: controller)
        var results: [SwitcherReusablePanelShellResult] = []
        owner.prepare(contentSize: NSSize(width: 300, height: 150)) { results.append($0) }
        owner.cancel()
        owner.cancel()
        XCTAssertEqual(results, [.superseded])
        let finished = expectation(description: "superseded shell resolved")
        owner.prepare(contentSize: NSSize(width: 400, height: 200)) { result in
            results.append(result)
            finished.fulfill()
        }
        controller.presentationSessionGeneration += 1
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(results, [.superseded, .superseded])
        owner.prepare(contentSize: nil) { results.append($0) }
        XCTAssertEqual(results, [.superseded, .superseded, .notRequired])
        controller.panel.orderOut(nil)
    }

    func testRenderEvidenceRejectsOldPresentationWindowAndPreviewVersion() {
        let controller = makeController()
        let model = controller.model
        model.session = makeSession()
        model.overlayStyle = .windowOnly
        controller.panelVisibilityOverride = true
        controller.panelOcclusionStateOverride = .visible
        controller.panel.alphaValue = 1
        controller.presentationSessionGeneration = 4
        model.windowContentRenderGeneration = 8
        var received: [ControlTabPressureRenderEvent] = []
        let observer = controller.addPressureRenderMilestoneObserver { received.append($0) }
        defer { controller.removePressureRenderMilestoneObserver(observer); controller.panel.orderOut(nil) }
        let current = controller.pressureDrawIdentity
        for identity in [
            ControlTabPressureDrawIdentity(presentationGeneration: 3, selectedWindowID: current.selectedWindowID, previewVersion: 8),
            .init(presentationGeneration: 4, selectedWindowID: "other", previewVersion: 8),
            .init(presentationGeneration: 4, selectedWindowID: current.selectedWindowID, previewVersion: 7)
        ] {
            controller.handlePressureRenderMilestone(.init(milestone: .windowContent, renderGeneration: 8,
                drawnAtMilliseconds: 1, identity: identity))
        }
        XCTAssertTrue(received.isEmpty)
        XCTAssertNil(controller.controlTabPressureDiagnostics.lastObservedRenderGeneration)
        controller.handlePressureRenderMilestone(.init(milestone: .windowContent, renderGeneration: 8,
            drawnAtMilliseconds: 2, identity: current))
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.identity, current)
    }

    func testBatchCancellationOwnsResourcesAndScopesOldCallbacks() {
        let recorder = ControlTabPressureSpanRecorder(clock: ControlTabSystemProcessCPUClock())
        let measurements = ControlTabPressurePreviewMeasurements(recorder: recorder)
        let diagnostics = ControlTabPressureModelDiagnostics()
        let sink = PressureRecordingSink()
        diagnostics.sink = sink
        diagnostics.previewMeasurements = measurements
        let cancellation = WindowPreviewCaptureCancellation()
        let id = UUID()
        measurements.begin(.init(id: id, captures: [], generation: 0, cancellation: cancellation,
                                 captureSemaphore: DispatchSemaphore(value: 1)))
        recorder.cancel()
        var businessCallbackRan = false
        diagnostics.measuringBatch(id) {
            businessCallbackRan = true
            XCTAssertNil(diagnostics.measurementSink)
        }
        XCTAssertTrue(businessCallbackRan)
        XCTAssertTrue(diagnostics.measurementSink === sink)
        measurements.begin(.init(id: id, captures: [], generation: 0, cancellation: cancellation,
                                 captureSemaphore: DispatchSemaphore(value: 1)))
        measurements.cancel()
        XCTAssertTrue(cancellation.isCancelled)
        XCTAssertNil(measurements.takeGeneration(for: id))
    }

    func testPreviewCacheHitForwardsPlanAndRetainsConditionalEvidence() {
        let base = PressurePreviewPlannerSpy()
        let diagnostics = ControlTabPressureModelDiagnostics()
        let sink = PressureRecordingSink()
        diagnostics.sink = sink
        let decorated = ControlTabPressurePreviewPlanner(base: base, diagnostics: diagnostics)
        let context = SwitcherPreviewPlanningContext(session: makeSession(), overlayStyle: .windowOnly,
            titleBarStyleInferenceEnabled: true, previewCaptureOverride: nil)
        let result = decorated.plan(context: context, visibleRange: 3..<5)
        XCTAssertEqual(base.range, 3..<5)
        XCTAssertEqual(base.appID, "app")
        XCTAssertEqual(result?.appID, "cached")
        XCTAssertTrue(sink.outcomes.contains { $0.0 == .previewCapture && $0.1 == .cacheHit })
        XCTAssertTrue(sink.outcomes.contains { $0.0 == .previewBatchPublication && $0.1 == .cacheHit })
        XCTAssertTrue(sink.outcomes.contains { $0.0 == .previewResultDiscard && $0.1 == .notRequired })
    }

    private func makeController() -> SwitcherPanelController {
        SwitcherPanelController(model: LiveSwitcherModel(runtimeProjectionService: RecordingRuntimeProjectionService()))
    }

    func testActivationDecoratorForwardsRequestsRejectsMismatchesAndRestoresHandlers() {
        let base = PressureActivatorSpy()
        let model = LiveSwitcherModel(runtimeProjectionService: RecordingRuntimeProjectionService(), activator: base)
        let recorder = ControlTabPressureSpanRecorder(clock: ControlTabSystemProcessCPUClock())
        let coordinator = ControlTabPressureActivationCoordinator(spanRecorder: recorder)
        let app = NSRunningApplication.current
        let windowID = "cg:\(app.processIdentifier):77"
        let context = RuntimeAppContext(appID: "app", runningApp: app, windowsByID: [
            windowID: RuntimeWindowContext(id: windowID, title: "Window", isMinimized: false,
                ownerPID: app.processIdentifier, cgWindowID: nil, spaceIDs: [],
                inferredTitleBarStyle: nil, axWindow: nil)
        ])
        let target = ActivationTarget.window(appID: "app", windowID: windowID, restoreIfMinimized: true)
        var forwarded: [RuntimeWindowFocusVerification] = []
        base.windowFocusVerifiedHandler = { verification in
            forwarded.append(verification)
            XCTAssertFalse(coordinator.verificationReceipt.satisfied)
        }
        var restoredOverrideCalls = 0
        model.activationOverride = { actual, contexts in
            XCTAssertEqual(actual, target)
            XCTAssertEqual(contexts["app"]?.ownerPID, app.processIdentifier)
            restoredOverrideCalls += 1
        }
        coordinator.install(on: model, usesMockRuntime: false)
        model.activator.activate(target: target, contextsByID: ["app": context])
        XCTAssertEqual(base.target, target)
        XCTAssertEqual(base.contexts["app"]?.windowsByID[windowID]?.id, windowID)
        XCTAssertEqual(coordinator.verificationReceipt.cgWindowID, 77)
        func verification(pid: pid_t, id: String, targetID: CGWindowID, focusedID: CGWindowID) -> RuntimeWindowFocusVerification {
            .init(appID: "app", windowID: id, ownerPID: pid, targetCGWindowID: targetID,
                focusedCGWindowID: focusedID, focusedAXWindow: nil, title: "Window", frame: nil, allowedActions: [])
        }
        for value in [
            verification(pid: app.processIdentifier + 1, id: windowID, targetID: 77, focusedID: 77),
            verification(pid: app.processIdentifier, id: "other", targetID: 77, focusedID: 77),
            verification(pid: app.processIdentifier, id: windowID, targetID: 78, focusedID: 78),
            verification(pid: app.processIdentifier, id: windowID, targetID: 77, focusedID: 78)
        ] {
            base.windowFocusVerifiedHandler?(value)
            XCTAssertFalse(coordinator.verificationReceipt.satisfied)
            XCTAssertEqual(coordinator.verificationReceipt.generation, 0)
        }
        base.windowFocusVerifiedHandler?(verification(pid: app.processIdentifier, id: windowID, targetID: 77, focusedID: 77))
        XCTAssertEqual(forwarded.count, 5)
        XCTAssertTrue(coordinator.verificationReceipt.satisfied)
        XCTAssertEqual(coordinator.verificationReceipt.generation, 1)
        coordinator.uninstall(from: model)
        coordinator.uninstall(from: model)
        XCTAssertTrue(model.activator === base)
        model.activationOverride?(target, ["app": context])
        XCTAssertEqual(restoredOverrideCalls, 1)
        base.windowFocusVerifiedHandler?(verification(pid: app.processIdentifier, id: windowID, targetID: 77, focusedID: 77))
        XCTAssertEqual(forwarded.count, 6)
        XCTAssertFalse(coordinator.verificationReceipt.satisfied)
    }
    private func makeSession() -> SwitcherSession {
        let app = AppSwitchCandidate(id: "app", displayName: "App", groupID: "app", lastActiveAt: 1,
            windows: [WindowCandidate(id: "window", title: "Window", isMinimized: false, lastActiveAt: 1)])
        var session = SwitcherSession(apps: [app], preferences: .default, triggerDirection: .forward,
                                      rememberedWindowIDByAppID: [:])
        _ = session.enterWindowCycle(allowSingleWindow: true)
        return session
    }
}

private final class PressureHotkeySpy: HotkeyMonitoring {
    let inputSourceID = HotkeyInputSourceID()
    var onHotkeyEvent: ((HotkeyInputEvent) -> Void)?
    var calls: [String] = []
    func start() { calls.append("start") }
    func stop() { calls.append("stop") }
    func requireChordEventMonitoring() { calls.append("require") }
}

@MainActor
private final class PressureActivatorSpy: WindowActivating {
    var windowFocusVerifiedHandler: ((RuntimeWindowFocusVerification) -> Void)?
    var windowFocusReadbackMismatchHandler: ((WindowBindingReadbackDiagnostic) -> Void)?
    var target: ActivationTarget?
    var contexts: [String: RuntimeAppContext] = [:]
    func activate(target: ActivationTarget, contextsByID: [String: RuntimeAppContext]) {
        self.target = target
        self.contexts = contextsByID
    }
}

@MainActor
private final class PressurePreviewPlannerSpy: SwitcherPreviewPlanning {
    var range: Range<Int>?
    var appID: String?
    func plan(context: SwitcherPreviewPlanningContext, visibleRange: Range<Int>?) -> SwitcherPreviewPlan? {
        range = visibleRange
        appID = context.session?.selectedApp.id
        return .init(appID: "cached", selectedIndex: 0, items: [], pendingCaptures: [])
    }
    func resolve(context: SwitcherPreviewPlanningContext, appID: String, window: WindowCandidate,
                 pinForSession: Bool) -> ResolvedPreviewData {
        fatalError("Cache-only fixture must not resolve a new capture")
    }
}

@MainActor
private final class PressureRecordingSink: SwitcherInteractionDiagnosticSink {
    var outcomes: [(SwitcherInteractionComponent, SwitcherInteractionSpanOutcome)] = []
    func beginComponent(_ component: SwitcherInteractionComponent, parent: SwitcherInteractionComponent?, workUnits: Int) -> SwitcherInteractionSpanToken? { nil }
    func endComponent(_ token: SwitcherInteractionSpanToken?, outcome: SwitcherInteractionSpanOutcome, workUnits: Int?) {}
    func recordUnexecutedComponent(_ component: SwitcherInteractionComponent, parent: SwitcherInteractionComponent?, outcome: SwitcherInteractionSpanOutcome, workUnits: Int) { outcomes.append((component, outcome)) }
    func recordPremeasuredComponent(_ span: SwitcherInteractionPremeasuredComponentSpan) {}
}
