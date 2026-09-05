import AppKit
import XCTest
@testable import FlowTab

@MainActor
final class ControlTabPressurePreviewCompletionTests: XCTestCase {
    private let captureStages: Set<String> = [
        "preview_shareable_content_lookup", "preview_screenshot_manager_capture",
        "preview_core_graphics_capture", "preview_transparent_trim", "preview_image_scale",
        "preview_image_materialization", "preview_title_bar_inference"
    ]

    func testFailedLookupPreservesResultsAndCompletesEveryCaptureStage() async throws {
        let windows = FailedPressureShareableWindows()
        let (results, evidence) = await capture(windows: windows)

        XCTAssertEqual(results.map(\.failureReason), [.screenCaptureUnavailable, .screenCaptureUnavailable])
        XCTAssertTrue(results.allSatisfy { $0.image == nil })
        XCTAssertEqual(windows.lookupCount, 1)
        let stages = assertCompleteCaptureEvidence(evidence)
        let lookup = try XCTUnwrap(stages.first { $0.name == "preview_shareable_content_lookup" })
        XCTAssertEqual(lookup.outcome, "failed")
        XCTAssertEqual(lookup.workUnits, 1)
        assertUnexecuted(stages.filter { $0.name != lookup.name }, outcome: "failed", workUnits: 2)
        XCTAssertTrue(evidence.requiredComponentsPresent)
        XCTAssertTrue(evidence.timelineReconciled)
        XCTAssertFalse(evidence.componentTimingValid)
    }

    func testCancellationDuringLookupCompletesCancelledEvidence() async {
        let windows = FailedPressureShareableWindows(cancelDuringLookup: true)
        let (results, evidence) = await capture(windows: windows)

        XCTAssertEqual(results.map(\.failureReason), [.transientSystemError, .transientSystemError])
        XCTAssertEqual(windows.lookupCount, 1)
        let stages = assertCompleteCaptureEvidence(evidence)
        XCTAssertTrue(stages.allSatisfy { $0.outcome == "cancelled" })
        assertUnexecuted(stages.filter { $0.name != "preview_shareable_content_lookup" },
                         outcome: "cancelled", workUnits: 2)
        XCTAssertEqual(captureParent(evidence)?.outcome, "cancelled")
        XCTAssertTrue(evidence.requiredComponentsPresent)
        XCTAssertTrue(evidence.timelineReconciled)
        XCTAssertFalse(evidence.componentTimingValid)
    }

    func testPermissionFailureBeforeLookupCompletesUnexecutedEvidence() async {
        let windows = FailedPressureShareableWindows()
        let (results, evidence) = await capture(windows: windows, permissionGranted: false)

        XCTAssertEqual(results.map(\.failureReason), [.permissionDenied, .permissionDenied])
        XCTAssertEqual(windows.lookupCount, 0)
        assertUnexecuted(assertCompleteCaptureEvidence(evidence), outcome: "failed", workUnits: 2)
        XCTAssertTrue(evidence.requiredComponentsPresent)
        XCTAssertTrue(evidence.timelineReconciled)
        XCTAssertFalse(evidence.componentTimingValid)
    }

    func testSuccessfulOverridePreservesImagesAndSingleConditionalSpanPerStage() async {
        let recorder = makeRecorder()
        let request = makeRequest()
        let image = NSImage(size: NSSize(width: 20, height: 10))
        let factory = ControlTabPressurePreviewFactory(base: SwitcherPreviewBatchFactory(), recorder: recorder)
        let batch = factory.makeBatch(request: request, resolver: .default, capture: nil,
            captureOutcomes: { requests in
                XCTAssertEqual(requests.map(\.preferredWindowID), [41, 42])
                return requests.map {
                    .success(.init(image: image, resolvedWindowID: $0.preferredWindowID ?? 0,
                                   titleBarStyle: nil))
                }
            })
        let results = await batch.capture()
        let evidence = finish(recorder)

        XCTAssertEqual(results.map(\.resolvedWindowID), [41, 42])
        XCTAssertTrue(results.allSatisfy { $0.image === image && $0.failureReason == nil })
        assertUnexecuted(assertCompleteCaptureEvidence(evidence), outcome: "not_required", workUnits: 2)
        XCTAssertEqual(captureParent(evidence)?.outcome, "completed")
        XCTAssertTrue(evidence.isValid)
    }

    private func capture(windows: FailedPressureShareableWindows, permissionGranted: Bool = true)
        async -> ([WindowPreviewResult], ControlTabPressureSpanEvidence) {
        let previous = ScreenCapturePermissionChecker.hasPermissionOverrideForTesting
        ScreenCapturePermissionChecker.hasPermissionOverrideForTesting = { permissionGranted }
        defer { ScreenCapturePermissionChecker.hasPermissionOverrideForTesting = previous }
        let recorder = makeRecorder()
        let factory = ControlTabPressurePreviewFactory(base: SwitcherPreviewBatchFactory(), recorder: recorder)
        let resolver = WindowPreviewProviderResolver(specialProviders: [],
            genericProvider: GenericWindowScreenshotPreviewProvider(
                batchFactory: FailedPressureCaptureBatchFactory(windows: windows)))
        let request = makeRequest()
        let batch = factory.makeBatch(request: request, resolver: resolver, capture: nil, captureOutcomes: nil)
        let results = await batch.capture()
        XCTAssertTrue(windows.cancellation == nil || windows.cancellation === request.cancellation)
        return (results, finish(recorder))
    }

    private func makeRequest() -> SwitcherPreviewBatchRequest {
        .init(id: UUID(), captures: [41, 42].map { windowID in
            .init(appID: "capture-fixture", bundleIdentifier: nil, windowID: "window-\(windowID)",
                ownerPID: 987_654, preferredWindowID: CGWindowID(windowID), preferredTitle: "Fixture",
                windowFrame: nil, inferTitleBarStyle: true, activationHandleID: nil,
                initialCacheKey: "preview-\(windowID)")
        }, generation: 1, cancellation: WindowPreviewCaptureCancellation(),
              captureSemaphore: DispatchSemaphore(value: 2))
    }

    private func makeRecorder() -> ControlTabPressureSpanRecorder {
        let clock = ControlTabSystemProcessCPUClock()
        let recorder = ControlTabPressureSpanRecorder(clock: clock)
        recorder.beginPhase(.init(sequence: 1, phase: .open,
            startedAtNanoseconds: DispatchTime.now().uptimeNanoseconds, startedCPU: clock.snapshot(),
            panelWasPresented: false, selectedAppIDBefore: nil, selectedWindowIDBefore: nil,
            selectedWindowCountBefore: 0, activationRequestGenerationBefore: 0,
            activationVerificationGenerationBefore: 0, completeProjectionUpdateGenerationBefore: 0,
            focusedSessionDiagnosticGenerationBefore: 0, windowContentRenderGenerationBefore: 0,
            reusableShellPreparationGenerationBefore: 0, panelHiddenGenerationBefore: 0,
            cleanupCompleteGenerationBefore: 0, presentationCleanupRequiredBefore: false))
        for component in ControlTabPressureSpanRequirements.components(for: .open)
            where component != .previewCapture && !captureStages.contains(component.rawValue) {
            recorder.recordUnexecutedComponent(component, outcome: .notRequired)
        }
        return recorder
    }

    private func finish(_ recorder: ControlTabPressureSpanRecorder) -> ControlTabPressureSpanEvidence {
        recorder.finishPhase(completedAtNanoseconds: DispatchTime.now().uptimeNanoseconds,
                             completedCPU: ControlTabSystemProcessCPUClock().snapshot())
    }

    private func captureParent(_ evidence: ControlTabPressureSpanEvidence) -> ControlTabPressureSpan? {
        evidence.spans.first { $0.scope == .componentInclusive && $0.name == "preview_capture" }
    }

    @discardableResult
    private func assertCompleteCaptureEvidence(_ evidence: ControlTabPressureSpanEvidence,
                                               file: StaticString = #filePath, line: UInt = #line)
        -> [ControlTabPressureSpan] {
        let stages = evidence.spans.filter { $0.scope == .componentInclusive && captureStages.contains($0.name) }
        XCTAssertEqual(Set(stages.map(\.name)), captureStages, file: file, line: line)
        XCTAssertEqual(stages.count, captureStages.count, file: file, line: line)
        guard let parent = captureParent(evidence) else {
            XCTFail("Missing capture parent", file: file, line: line)
            return stages
        }
        for stage in stages {
            XCTAssertEqual(stage.parent, parent.name, file: file, line: line)
            XCTAssertGreaterThanOrEqual(stage.startedAtNanoseconds, parent.startedAtNanoseconds, file: file, line: line)
            XCTAssertLessThanOrEqual(stage.completedAtNanoseconds, parent.completedAtNanoseconds, file: file, line: line)
        }
        return stages
    }

    private func assertUnexecuted(_ spans: [ControlTabPressureSpan], outcome: String, workUnits: Int,
                                 file: StaticString = #filePath, line: UInt = #line) {
        for span in spans {
            XCTAssertEqual(span.outcome, outcome, file: file, line: line)
            XCTAssertEqual(span.workUnits, workUnits, file: file, line: line)
            XCTAssertEqual(span.startedAtNanoseconds, span.completedAtNanoseconds, file: file, line: line)
            XCTAssertEqual(span.duration.wallMilliseconds, 0, file: file, line: line)
            XCTAssertEqual(span.duration.cpuTimeMilliseconds, 0, file: file, line: line)
        }
    }
}

private final class FailedPressureShareableWindows: RuntimeShareableWindowsProviding {
    let cancelDuringLookup: Bool
    private(set) var lookupCount = 0
    private(set) var cancellation: WindowPreviewCaptureCancellation?

    init(cancelDuringLookup: Bool = false) { self.cancelDuringLookup = cancelDuringLookup }

    func windows(onScreenOnly: Bool, cancellation: WindowPreviewCaptureCancellation?)
        -> RuntimeWindowPreviewProvider.ShareableWindowLookup {
        lookupCount += 1
        self.cancellation = cancellation
        if cancelDuringLookup { cancellation?.cancel() }
        return .init(windowsByID: [:], failureReason: .screenCaptureUnavailable)
    }
}

private struct FailedPressureCaptureBatchFactory: WindowPreviewCaptureBatchCreating {
    let windows: FailedPressureShareableWindows

    func makeBatch(requests: [RuntimeWindowPreviewProvider.CaptureRequest],
                   captureSemaphore: DispatchSemaphore?, cancellation: WindowPreviewCaptureCancellation)
        -> any WindowPreviewCaptureBatchRunning {
        let operations = WindowPreviewCaptureOperations.system
        return RuntimeWindowPreviewCaptureBatch(requests: requests, captureSemaphore: captureSemaphore,
            cancellation: cancellation, operations: .init(windows: windows,
                capture: operations.capture, images: operations.images))
    }
}

final class RuntimePreviewPipelineCompletionTests: XCTestCase {
    func testCaptureFailureCompletesOnlyMissingStagesAndIsIdempotent() {
        let collector = RuntimeWindowPreviewCaptureDiagnosticCollector()
        let lookup = collector.begin(.shareableContentLookup, workUnits: 1)
        collector.end(lookup)
        collector.recordUnexecuted(.coreGraphicsCapture, outcome: .notRequired, workUnits: 3)
        let capture = collector.begin(.screenshotManagerCapture, workUnits: 3)
        collector.end(capture, outcome: .failed)
        let recorded = collector.spans()
        let boundary = DispatchTime.now().uptimeNanoseconds
        let cpu = RuntimeProcessDiagnosticClock.cpuSnapshot()

        collector.completePipeline(outcome: .failed, workUnits: 3,
            completedAtNanoseconds: boundary, completedCPU: cpu)
        let completed = collector.spans()
        XCTAssertEqual(completed.count, 7)
        XCTAssertTrue(recorded.allSatisfy { completed.contains($0) })
        let missing = completed.filter { !recorded.contains($0) }
        XCTAssertEqual(Set(missing.map(\.stage)),
                       [.transparentTrim, .imageScale, .imageMaterialization, .titleBarInference])
        for span in missing {
            XCTAssertEqual(span.outcome, .failed)
            XCTAssertEqual(span.workUnits, 3)
            XCTAssertEqual(span.startedAtNanoseconds, boundary)
            XCTAssertEqual(span.completedAtNanoseconds, boundary)
            XCTAssertEqual(span.startedCPU, cpu)
            XCTAssertEqual(span.completedCPU, cpu)
        }
        collector.completePipeline(outcome: .cancelled, workUnits: 9,
            completedAtNanoseconds: boundary + 1, completedCPU: cpu)
        XCTAssertEqual(collector.spans(), completed)
    }

    func testCancellationAfterImageProcessingPreservesCompletedWork() {
        let collector = RuntimeWindowPreviewCaptureDiagnosticCollector()
        for stage in [RuntimeWindowPreviewCaptureDiagnosticStage.shareableContentLookup,
                      .screenshotManagerCapture, .transparentTrim, .imageScale] {
            collector.end(collector.begin(stage, workUnits: 1))
        }
        collector.recordUnexecuted(.coreGraphicsCapture, outcome: .notRequired, workUnits: 1)
        let recorded = collector.spans()

        collector.completePipeline(outcome: .cancelled, workUnits: 1,
            completedAtNanoseconds: DispatchTime.now().uptimeNanoseconds,
            completedCPU: RuntimeProcessDiagnosticClock.cpuSnapshot())

        let completed = collector.spans()
        XCTAssertTrue(recorded.allSatisfy { completed.contains($0) })
        XCTAssertEqual(completed.count, 7)
        let cancelled = completed.filter { $0.outcome == .cancelled }
        XCTAssertEqual(Set(cancelled.map(\.stage)), [.imageMaterialization, .titleBarInference])
        XCTAssertTrue(cancelled.allSatisfy { $0.startedAtNanoseconds == $0.completedAtNanoseconds })
    }

    func testCompleteSuccessfulPipelinePreservesRepeatedMeasurements() {
        let collector = RuntimeWindowPreviewCaptureDiagnosticCollector()
        collector.end(collector.begin(.shareableContentLookup, workUnits: 1))
        for _ in 0..<2 {
            collector.recordUnexecuted(.coreGraphicsCapture, outcome: .notRequired, workUnits: 1)
            for stage in [RuntimeWindowPreviewCaptureDiagnosticStage.screenshotManagerCapture,
                          .transparentTrim, .imageScale, .imageMaterialization, .titleBarInference] {
                collector.end(collector.begin(stage, workUnits: 1))
            }
        }
        let recorded = collector.spans()
        XCTAssertEqual(recorded.count, 13)

        collector.completePipeline(outcome: .failed, workUnits: 2,
            completedAtNanoseconds: DispatchTime.now().uptimeNanoseconds,
            completedCPU: RuntimeProcessDiagnosticClock.cpuSnapshot())

        XCTAssertEqual(collector.spans(), recorded)
    }
}
