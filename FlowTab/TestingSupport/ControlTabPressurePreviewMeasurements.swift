#if FLOWTAB_TESTING
import Foundation

@MainActor
final class ControlTabPressurePreviewMeasurements {
    private let recorder: ControlTabPressureSpanRecorder
    private var batches: [UUID: (generation: UInt64, cancellation: WindowPreviewCaptureCancellation)] = [:]

    init(recorder: ControlTabPressureSpanRecorder) { self.recorder = recorder }
    func begin(_ request: SwitcherPreviewBatchRequest) {
        batches[request.id] = (recorder.currentGeneration, request.cancellation)
    }
    func takeGeneration(for id: UUID) -> UInt64? { batches.removeValue(forKey: id)?.generation }
    func isCurrent(_ generation: UInt64) -> Bool { recorder.isCurrentGeneration(generation) }
    func cancel() {
        let cancelled = batches.values
        batches.removeAll()
        for batch in cancelled { batch.cancellation.cancel() }
    }
}
#endif
