import AppKit
import Combine
import FlowTabCore
import ScreenCaptureKit
import XCTest
@testable import FlowTab

@MainActor
final class ControlTabPressureDecoratorTests: XCTestCase {
    func testOldFactBatchContinuesBusinessWorkWithoutRecordingIntoNextPhase() {
        let collector = RuntimeFocusedRepairDiagnosticCollector()
        collector.setEnabled(true)
        let base = PressureFactsSpy()
        let pid = NSRunningApplication.current.processIdentifier
        let previous = ControlTabPressureFactContext(collector: collector, pid: pid, workUnits: 1)
        let provider = ControlTabPressureFactProvider(base: base, context: previous)
        _ = provider.collectCGWindowsWithSpaceTopologyDiff(options: .optionOnScreenOnly, now: 1)
        collector.reset()
        _ = provider.collectCGWindowsWithSpaceTopologyDiff(options: .optionAll, now: 2)
        XCTAssertEqual(base.times, [1, 2])
        XCTAssertTrue(collector.drain(processIdentifier: pid).isEmpty)
        let current = ControlTabPressureFactContext(collector: collector, pid: pid, workUnits: 1)
        _ = ControlTabPressureFactProvider(base: base, context: current)
            .collectCGWindowsWithSpaceTopologyDiff(options: .optionOnScreenOnly, now: 3)
        XCTAssertEqual(base.times, [1, 2, 3])
        XCTAssertEqual(collector.drain(processIdentifier: pid).map(\.stage), [.onScreenCGRead])
    }

    func testHomeProjectionObserverReceivesOnlyDecoratedSourceNotifications() {
        let base = RecordingRuntimeProjectionService()
        let decorated = RuntimeUITestFrontmostProjectionService(baseService: base, targetProvider: { nil })
        let center = NotificationCenter()
        let owner = HomeAppSummaryProjectionObservationOwner(runtimeProjectionService: decorated,
            notificationCenter: center)
        owner.start(reason: "decorated-source") { _ in }
        defer { owner.stop(reason: "testComplete") }
        let reads = base.homeSummaryProjectionReadCount()
        center.post(name: .runtimeAppSwitcherProjectionDidUpdate, object: NSObject())
        XCTAssertEqual(base.homeSummaryProjectionReadCount(), reads)
        center.post(name: .runtimeAppSwitcherProjectionDidUpdate, object: base.notificationSource)
        XCTAssertEqual(base.homeSummaryProjectionReadCount(), reads + 1)
    }

    func testFactDecoratorsForwardCollectionOptionsCompletenessAndMapping() {
        let app = NSRunningApplication.current
        let pid = app.processIdentifier
        let base = PressureFactsSpy()
        let collector = RuntimeFocusedRepairDiagnosticCollector()
        collector.setEnabled(true)
        let context = ControlTabPressureFactContext(collector: collector, pid: pid, workUnits: 1)
        let provider = ControlTabPressureFactProvider(base: base, context: context)
        let onScreen = [pid: [RuntimeCGWindowEntry(id: 41, title: "Visible", bounds: nil)]]
        let all = [pid: [RuntimeCGWindowEntry(id: 42, title: "Hidden", bounds: nil, isOnscreen: false)]]
        let ax = provider.collectAXWindowData(for: [app], cgWindowsByPID: onScreen,
            allCGWindowsByPID: all, allCGCollectionIsComplete: false)
        XCTAssertEqual(base.apps.map(\.processIdentifier), [pid])
        XCTAssertEqual(base.onScreen[pid]?.map(\.id), [41])
        XCTAssertEqual(base.all[pid]?.map(\.id), [42])
        XCTAssertFalse(base.complete)
        XCTAssertEqual(Set(ax.keys), [pid])
        for options in [CGWindowListOption.optionOnScreenOnly, .optionAll] {
            let result = provider.collectCGWindowsWithSpaceTopologyDiff(options: options, now: 123)
            XCTAssertFalse(result.isComplete)
            XCTAssertEqual(result.windowsByPID[pid]?.map(\.id), [42])
        }
        XCTAssertEqual(base.options.map(\.rawValue), [CGWindowListOption.optionOnScreenOnly.rawValue,
                                                     CGWindowListOption.optionAll.rawValue])
        XCTAssertEqual(base.times, [123, 123])
        let mapping = ControlTabPressureWindowEntries(base: base, context: context)
        XCTAssertEqual(Set(mapping.entries(for: [app]).keys), [pid])
        XCTAssertEqual(base.mappedApps.map(\.processIdentifier), [pid])
        XCTAssertEqual(Set(collector.drain(processIdentifier: pid).map(\.stage)),
                       [.axRead, .onScreenCGRead, .allCGRead, .mappingSpaceFilter])
    }

    func testCaptureDecoratorsPreserveFailureAndCancellationResults() {
        let collector = RuntimeWindowPreviewCaptureDiagnosticCollector()
        let base = PressureCaptureSpy()
        let windows = ControlTabPressureShareableWindows(base: base, collector: collector)
        let cancellation = WindowPreviewCaptureCancellation()
        let failed = windows.windows(onScreenOnly: false, cancellation: cancellation)
        XCTAssertEqual(failed.failureReason, .screenCaptureUnavailable)
        XCTAssertTrue(base.cancellation === cancellation)
        XCTAssertEqual(base.onScreenOnly, false)
        cancellation.cancel()
        XCTAssertEqual(windows.windows(onScreenOnly: true, cancellation: cancellation).failureReason,
                       .screenCaptureUnavailable)
        XCTAssertEqual(base.onScreenOnly, true)
        let capture = ControlTabPressureWindowCapture(base: base, collector: collector)
        XCTAssertNil(capture.coreGraphicsImage(windowID: 99))
        XCTAssertEqual(base.windowIDs, [99])
        XCTAssertEqual(collector.spans().filter { $0.stage == .shareableContentLookup }.map(\.outcome),
                       [.failed, .cancelled])
        XCTAssertEqual(collector.spans().first { $0.stage == .coreGraphicsCapture }?.outcome, .failed)
        XCTAssertEqual(collector.spans().first { $0.stage == .screenshotManagerCapture }?.outcome, .notRequired)
    }

    func testImageDecoratorForwardsInputsResultsAndOptionalInference() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 32,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let base = RecordingPreviewImages(image: image)
        let collector = RuntimeWindowPreviewCaptureDiagnosticCollector()
        let decorated = ControlTabPressurePreviewImages(base: base, collector: collector)

        XCTAssertTrue(decorated.trim(image) === image)
        XCTAssertNil(decorated.scale(image))
        XCTAssertTrue(decorated.materialize(image) === base.materialized)
        XCTAssertEqual(decorated.titleBarStyle(from: image, requested: true), .dark)
        XCTAssertNil(decorated.titleBarStyle(from: image, requested: false))
        XCTAssertEqual(base.calls, ["trim", "scale", "materialize", "title:true", "title:false"])
        XCTAssertTrue(base.inputs.allSatisfy { $0 === image })
        XCTAssertEqual(collector.spans().first { $0.stage == .imageScale }?.outcome, .failed)
        XCTAssertEqual(collector.spans().filter { $0.stage == .titleBarInference }.map(\.outcome),
                       [.completed, .notRequested])
    }

    func testSessionPublicationPreservesSynchronousReadbackOrder() throws {
        let state = SwitcherSessionState()
        let diagnostics = ControlTabPressureModelDiagnostics()
        let decorated = ControlTabPressureSessionState(base: state, diagnostics: diagnostics)
        let app = AppSwitchCandidate(id: "app", displayName: "App", groupID: "app", lastActiveAt: 1,
            windows: [WindowCandidate(id: "window", title: "Window", isMinimized: false, lastActiveAt: 1)])
        let session = try XCTUnwrap(decorated.buildWindowSession(app: app, preferences: .default,
            direction: .backward, rememberedWindows: [:]))
        var calls: [String] = []
        let observation = state.willChange.sink {
            calls.append("will:\(state.session?.selectedApp.id ?? "nil")")
        }
        decorated.didPublish = { previous, current in
            calls.append("did:\(previous?.selectedApp.id ?? "nil"):\(current?.selectedApp.id ?? "nil")")
            XCTAssertEqual(state.session?.selectedApp.id, "app")
            XCTAssertEqual(diagnostics.renderGeneration, 1)
        }
        decorated.publish(session)
        XCTAssertEqual(calls, ["will:nil", "did:nil:app"])
        XCTAssertEqual(decorated.session?.selectedWindow?.id, state.session?.selectedWindow?.id)
        withExtendedLifetime(observation) {}
    }

    func testProjectionNotificationIdentitySurvivesDecoration() {
        let base = RecordingRuntimeProjectionService()
        let decorated = RuntimeUITestFrontmostProjectionService(baseService: base, targetProvider: { nil })
        XCTAssertTrue(decorated.notificationSource === base.notificationSource)
        let center = NotificationCenter()
        var received = 0
        let observer = center.addObserver(forName: .runtimeAppSwitcherProjectionDidUpdate,
            object: decorated.notificationSource, queue: nil) { _ in received += 1 }
        center.post(name: .runtimeAppSwitcherProjectionDidUpdate, object: base.notificationSource)
        XCTAssertEqual(received, 1)
        center.removeObserver(observer)
    }

    func testPreviewClearCancelsOwnedResourcesAndRejectsOldBatch() {
        let state = SwitcherPreviewStorage()
        let publication = SwitcherPreviewPublication()
        let session = SwitcherPreviewSession(state: state, contexts: SwitcherRuntimeContextStore(),
                                             publication: publication)
        let cancellation = WindowPreviewCaptureCancellation()
        let id = UUID()
        state.previewCaptureCancellationsByID[id] = cancellation
        state.previewCaptureStatesByKey["window"] = .inFlight(generation: 0)
        state.previewCaptureInFlightKeys.insert("window")
        var publications = 0
        publication.preparationChanged = { publications += 1 }

        session.clear()
        XCTAssertTrue(cancellation.isCancelled)
        XCTAssertTrue(state.previewCaptureCancellationsByID.isEmpty)
        XCTAssertTrue(state.previewCaptureStatesByKey.isEmpty)
        XCTAssertTrue(state.previewCaptureInFlightKeys.isEmpty)
        XCTAssertEqual(state.previewCaptureGeneration, 1)
        XCTAssertEqual(session.completeBatch([], pendingCaptures: [], batchID: id,
            cancellation: cancellation, generation: 0, startMs: 0, completeMs: 1), .cancelled)
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(session.completeBatch([], pendingCaptures: [], batchID: UUID(),
            cancellation: WindowPreviewCaptureCancellation(), generation: 0, startMs: 0, completeMs: 1), .stale)
        XCTAssertEqual(publications, 0)
    }
}

private final class RecordingPreviewImages: RuntimePreviewImageProcessing {
    let image: CGImage
    let materialized = NSImage(size: NSSize(width: 32, height: 32))
    var inputs: [CGImage] = []
    var calls: [String] = []

    init(image: CGImage) { self.image = image }
    func trim(_ image: CGImage) -> CGImage {
        inputs.append(image); calls.append("trim"); return self.image
    }
    func scale(_ image: CGImage) -> CGImage? {
        inputs.append(image); calls.append("scale"); return nil
    }
    func materialize(_ image: CGImage) -> NSImage {
        inputs.append(image); calls.append("materialize"); return materialized
    }
    func titleBarStyle(from image: CGImage, requested: Bool) -> WindowTitleBarStyleGuess? {
        inputs.append(image); calls.append("title:\(requested)"); return requested ? .dark : nil
    }
}

private final class PressureFactsSpy: RuntimeProjectionRepairFactProviding, RuntimeWindowEntryProjecting {
    var apps: [NSRunningApplication] = []
    var mappedApps: [NSRunningApplication] = []
    var onScreen: [pid_t: [RuntimeCGWindowEntry]] = [:]
    var all: [pid_t: [RuntimeCGWindowEntry]] = [:]
    var complete = true
    var options: [CGWindowListOption] = []
    var times: [TimeInterval] = []

    func collectAXWindowData(for runningApps: [NSRunningApplication],
        cgWindowsByPID: [pid_t: [RuntimeCGWindowEntry]],
        allCGWindowsByPID: [pid_t: [RuntimeCGWindowEntry]],
        allCGCollectionIsComplete: Bool) -> [pid_t: [RuntimeWindowListEntry]] {
        apps = runningApps
        onScreen = cgWindowsByPID
        all = allCGWindowsByPID
        complete = allCGCollectionIsComplete
        return Dictionary(uniqueKeysWithValues: runningApps.map { ($0.processIdentifier, []) })
    }

    func collectCGWindowsWithSpaceTopologyDiff(options: CGWindowListOption, now: TimeInterval)
        -> RuntimeCGWindowCollection {
        self.options.append(options)
        times.append(now)
        return RuntimeCGWindowCollection(windowsByPID: all, spaceTopologyDiff: nil, isComplete: complete)
    }

    func entries(for runningApps: [NSRunningApplication]) -> [pid_t: [RuntimeWindowListEntry]] {
        mappedApps = runningApps
        return Dictionary(uniqueKeysWithValues: runningApps.map { ($0.processIdentifier, []) })
    }
}

private final class PressureCaptureSpy: RuntimeShareableWindowsProviding, RuntimeWindowImageCapturing {
    var onScreenOnly: Bool?
    var cancellation: WindowPreviewCaptureCancellation?
    var windowIDs: [CGWindowID] = []

    func windows(onScreenOnly: Bool, cancellation: WindowPreviewCaptureCancellation?)
        -> RuntimeWindowPreviewProvider.ShareableWindowLookup {
        self.onScreenOnly = onScreenOnly
        self.cancellation = cancellation
        return .init(windowsByID: [:], failureReason: .screenCaptureUnavailable)
    }

    @available(macOS 14.0, *)
    func screenshot(of window: SCWindow, cancellation: WindowPreviewCaptureCancellation?) -> CGImage? { nil }
    func coreGraphicsImage(windowID: CGWindowID) -> CGImage? {
        windowIDs.append(windowID)
        return nil
    }
}
