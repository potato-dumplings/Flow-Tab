#if FLOWTAB_TESTING
import Foundation

enum RuntimeWindowPreviewCaptureDiagnosticContext {
    @TaskLocal static var current: RuntimeWindowPreviewCaptureDiagnosticCollector?
}

enum RuntimeWindowPreviewCaptureDiagnosticStage: String, CaseIterable, Sendable {
    case shareableContentLookup = "preview_shareable_content_lookup"
    case screenshotManagerCapture = "preview_screenshot_manager_capture"
    case coreGraphicsCapture = "preview_core_graphics_capture"
    case transparentTrim = "preview_transparent_trim"
    case imageScale = "preview_image_scale"
    case imageMaterialization = "preview_image_materialization"
    case titleBarInference = "preview_title_bar_inference"
}

enum RuntimeWindowPreviewCaptureDiagnosticOutcome: String, Sendable {
    case completed
    case cacheHit = "cache_hit"
    case notRequested = "not_requested"
    case notRequired = "not_required"
    case cancelled
    case timedOut = "timed_out"
    case failed
}

struct RuntimeWindowPreviewCaptureDiagnosticSpan: Equatable, Sendable {
    let stage: RuntimeWindowPreviewCaptureDiagnosticStage
    let startedAtNanoseconds: UInt64
    let completedAtNanoseconds: UInt64
    let startedCPU: RuntimeProcessCPUSnapshot
    let completedCPU: RuntimeProcessCPUSnapshot
    let outcome: RuntimeWindowPreviewCaptureDiagnosticOutcome
    let workUnits: Int
}

struct RuntimeWindowPreviewCaptureDiagnosticToken: Hashable, Sendable {
    let rawValue: UInt64
}

final class RuntimeWindowPreviewCaptureDiagnosticCollector: @unchecked Sendable {
    private struct ActiveSpan {
        let stage: RuntimeWindowPreviewCaptureDiagnosticStage
        let startedAtNanoseconds: UInt64
        let startedCPU: RuntimeProcessCPUSnapshot
        let workUnits: Int
    }

    private let lock = NSLock()
    private var nextToken: UInt64 = 0
    private var active: [UInt64: ActiveSpan] = [:]
    private var completed: [RuntimeWindowPreviewCaptureDiagnosticSpan] = []

    func begin(
        _ stage: RuntimeWindowPreviewCaptureDiagnosticStage,
        workUnits: Int = 0
    ) -> RuntimeWindowPreviewCaptureDiagnosticToken {
        lock.lock()
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let startedCPU = RuntimeProcessDiagnosticClock.cpuSnapshot()
        nextToken &+= 1
        let token = nextToken
        active[token] = ActiveSpan(
            stage: stage,
            startedAtNanoseconds: startedAt,
            startedCPU: startedCPU,
            workUnits: max(0, workUnits)
        )
        lock.unlock()
        return RuntimeWindowPreviewCaptureDiagnosticToken(rawValue: token)
    }

    func end(
        _ token: RuntimeWindowPreviewCaptureDiagnosticToken?,
        outcome: RuntimeWindowPreviewCaptureDiagnosticOutcome = .completed,
        workUnits: Int? = nil
    ) {
        guard let token else { return }
        lock.lock()
        guard let started = active.removeValue(forKey: token.rawValue) else {
            lock.unlock()
            return
        }
        let completedAt = DispatchTime.now().uptimeNanoseconds
        let completedCPU = RuntimeProcessDiagnosticClock.cpuSnapshot()
        completed.append(
            RuntimeWindowPreviewCaptureDiagnosticSpan(
                stage: started.stage,
                startedAtNanoseconds: started.startedAtNanoseconds,
                completedAtNanoseconds: completedAt,
                startedCPU: started.startedCPU,
                completedCPU: completedCPU,
                outcome: outcome,
                workUnits: max(0, workUnits ?? started.workUnits)
            )
        )
        lock.unlock()
    }

    func recordUnexecuted(
        _ stage: RuntimeWindowPreviewCaptureDiagnosticStage,
        outcome: RuntimeWindowPreviewCaptureDiagnosticOutcome,
        workUnits: Int = 0
    ) {
        lock.lock()
        let time = DispatchTime.now().uptimeNanoseconds
        let cpu = RuntimeProcessDiagnosticClock.cpuSnapshot()
        completed.append(
            RuntimeWindowPreviewCaptureDiagnosticSpan(
                stage: stage,
                startedAtNanoseconds: time,
                completedAtNanoseconds: time,
                startedCPU: cpu,
                completedCPU: cpu,
                outcome: outcome,
                workUnits: max(0, workUnits)
            )
        )
        lock.unlock()
    }

    func recordUnexecutedPipeline(
        outcome: RuntimeWindowPreviewCaptureDiagnosticOutcome,
        workUnits: Int
    ) {
        for stage in RuntimeWindowPreviewCaptureDiagnosticStage.allCases {
            recordUnexecuted(
                stage,
                outcome: outcome,
                workUnits: workUnits
            )
        }
    }

    func recordUnexecutedAfterShareableContentLookup(
        outcome: RuntimeWindowPreviewCaptureDiagnosticOutcome,
        workUnits: Int
    ) {
        for stage in [
            RuntimeWindowPreviewCaptureDiagnosticStage
                .screenshotManagerCapture,
            .coreGraphicsCapture,
            .transparentTrim,
            .imageScale,
            .imageMaterialization,
            .titleBarInference
        ] {
            recordUnexecuted(
                stage,
                outcome: outcome,
                workUnits: workUnits
            )
        }
    }

    func completePipeline(
        outcome: RuntimeWindowPreviewCaptureDiagnosticOutcome,
        workUnits: Int,
        completedAtNanoseconds: UInt64,
        completedCPU: RuntimeProcessCPUSnapshot
    ) {
        lock.lock()
        defer { lock.unlock() }
        let recordedStages = Set(completed.map(\.stage))
        // Missing operations have no elapsed work; bind their evidence to the batch's return boundary.
        for stage in RuntimeWindowPreviewCaptureDiagnosticStage.allCases where !recordedStages.contains(stage) {
            completed.append(RuntimeWindowPreviewCaptureDiagnosticSpan(
                stage: stage,
                startedAtNanoseconds: completedAtNanoseconds,
                completedAtNanoseconds: completedAtNanoseconds,
                startedCPU: completedCPU,
                completedCPU: completedCPU,
                outcome: outcome,
                workUnits: max(0, workUnits)
            ))
        }
    }

    func spans() -> [RuntimeWindowPreviewCaptureDiagnosticSpan] {
        lock.lock()
        let snapshot = completed.sorted {
            if $0.startedAtNanoseconds != $1.startedAtNanoseconds {
                return $0.startedAtNanoseconds < $1.startedAtNanoseconds
            }
            return $0.stage.rawValue < $1.stage.rawValue
        }
        lock.unlock()
        return snapshot
    }
}
#endif
