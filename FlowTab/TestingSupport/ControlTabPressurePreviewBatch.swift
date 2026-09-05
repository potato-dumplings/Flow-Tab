#if FLOWTAB_TESTING
import Foundation

@MainActor
struct ControlTabPressurePreviewFactory: SwitcherPreviewBatchCreating {
    let base: any SwitcherPreviewBatchCreating
    let recorder: ControlTabPressureSpanRecorder
    var measurements: ControlTabPressurePreviewMeasurements? = nil

    func makeBatch(request: SwitcherPreviewBatchRequest, resolver: WindowPreviewProviderResolver,
                   capture: SwitcherPreviewBatchCapture?, captureOutcomes: SwitcherPreviewBatchCaptureOutcomes?)
        -> any SwitcherPreviewBatchRunning {
        measurements?.begin(request)
        guard let token = recorder.beginComponent(.previewCapture, parent: .previewPlanning,
                                                   workUnits: request.captures.count) else {
            return base.makeBatch(request: request, resolver: resolver, capture: capture, captureOutcomes: captureOutcomes)
        }
        let collector = RuntimeWindowPreviewCaptureDiagnosticCollector()
        let generic: any GenericWindowPreviewProviding
        if var screenshot = resolver.genericProvider as? GenericWindowScreenshotPreviewProvider {
            screenshot.batchFactory = ControlTabPressurePreviewBatchFactory(base: screenshot.batchFactory, collector: collector)
            generic = screenshot
        } else {
            generic = ControlTabPressureGenericPreview(base: resolver.genericProvider, collector: collector)
        }
        let decoratedResolver = WindowPreviewProviderResolver(
            specialProviders: resolver.specialProviders.map { ControlTabPressureSpecialPreview(base: $0, collector: collector) },
            genericProvider: generic
        )
        if capture != nil || captureOutcomes != nil {
            collector.recordUnexecutedPipeline(outcome: .notRequired, workUnits: request.captures.count)
        }
        return ControlTabPressurePreviewBatch(
            base: base.makeBatch(request: request, resolver: decoratedResolver, capture: capture, captureOutcomes: captureOutcomes),
            request: request, recorder: recorder, token: token, collector: collector
        )
    }
}

private struct ControlTabPressurePreviewBatch: SwitcherPreviewBatchRunning {
    let base: any SwitcherPreviewBatchRunning
    let request: SwitcherPreviewBatchRequest
    let recorder: ControlTabPressureSpanRecorder
    let token: SwitcherInteractionSpanToken
    let collector: RuntimeWindowPreviewCaptureDiagnosticCollector

    func capture() async -> [WindowPreviewResult] {
        let results = await base.capture()
        let finishedAt = DispatchTime.now().uptimeNanoseconds
        let cpu = RuntimeProcessDiagnosticClock.cpuSnapshot()
        let cancelled = request.cancellation.isCancelled
        collector.completePipeline(outcome: cancelled ? .cancelled : .failed,
            workUnits: request.captures.count, completedAtNanoseconds: finishedAt, completedCPU: cpu)
        let spans = collector.spans()
        await MainActor.run {
            guard recorder.owns(token) else { return }
            for span in spans {
                guard let component = SwitcherInteractionComponent(rawValue: span.stage.rawValue),
                      let outcome = SwitcherInteractionSpanOutcome(rawValue: span.outcome.rawValue) else { continue }
                recorder.recordPremeasuredComponent(.init(component: component, parent: .previewCapture,
                    startedAtNanoseconds: span.startedAtNanoseconds, completedAtNanoseconds: span.completedAtNanoseconds,
                    startedCPUUserNanoseconds: span.startedCPU.userNanoseconds,
                    startedCPUSystemNanoseconds: span.startedCPU.systemNanoseconds, startedCPUIsValid: span.startedCPU.isValid,
                    completedCPUUserNanoseconds: span.completedCPU.userNanoseconds,
                    completedCPUSystemNanoseconds: span.completedCPU.systemNanoseconds, completedCPUIsValid: span.completedCPU.isValid,
                    outcome: outcome, workUnits: span.workUnits))
            }
            recorder.endComponent(token, outcome: cancelled ? .cancelled : .completed,
                workUnits: request.captures.count, completedAt: finishedAt,
                completedCPU: ControlTabProcessCPUSnapshot(userNanoseconds: cpu.userNanoseconds,
                    systemNanoseconds: cpu.systemNanoseconds, isValid: cpu.isValid))
        }
        return results
    }
}

private struct ControlTabPressureSpecialPreview: SpecialWindowPreviewProviding {
    let base: any SpecialWindowPreviewProviding
    let collector: RuntimeWindowPreviewCaptureDiagnosticCollector

    func supports(_ request: WindowPreviewRequest) -> Bool { base.supports(request) }
    func previews(for requests: [WindowPreviewRequest]) async -> [WindowPreviewResult] {
        collector.recordUnexecutedPipeline(outcome: .notRequired, workUnits: requests.count)
        return await base.previews(for: requests)
    }
}

private struct ControlTabPressureGenericPreview: GenericWindowPreviewProviding {
    let base: any GenericWindowPreviewProviding
    let collector: RuntimeWindowPreviewCaptureDiagnosticCollector

    func previews(for requests: [WindowPreviewRequest], captureSemaphore: DispatchSemaphore?,
                  cancellation: WindowPreviewCaptureCancellation) async -> [WindowPreviewResult] {
        collector.recordUnexecutedPipeline(outcome: .notRequired, workUnits: requests.count)
        return await base.previews(for: requests, captureSemaphore: captureSemaphore, cancellation: cancellation)
    }
}
#endif
