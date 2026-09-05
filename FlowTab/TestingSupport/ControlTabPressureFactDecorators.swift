#if FLOWTAB_TESTING
import AppKit

struct ControlTabPressureFocusedWindowFacts: RuntimeFocusedWindowFactCollecting {
    let base: RuntimeFocusedWindowFactCollector
    let collector: RuntimeFocusedRepairDiagnosticCollector

    func collect(for app: NSRunningApplication, in runningApps: [NSRunningApplication])
        -> RuntimeFocusedCurrentAppWindowFacts {
        let apps = RuntimeProjectionRepairFactSource.focusedAppGroup(for: app, in: runningApps)
        let context = ControlTabPressureFactContext(
            collector: collector, pid: app.processIdentifier, workUnits: apps.count
        )
        return RuntimeFocusedWindowFactCollector(
            runtimeFactProvider: ControlTabPressureFactProvider(base: base.runtimeFactProvider, context: context),
            windowEntries: ControlTabPressureWindowEntries(base: base.windowEntries, context: context)
        ).collect(for: app, in: runningApps)
    }
}

struct ControlTabPressureFactContext {
    let collector: RuntimeFocusedRepairDiagnosticCollector
    let pid: pid_t
    let workUnits: Int
    private let scopeGeneration: UInt64

    init(collector: RuntimeFocusedRepairDiagnosticCollector, pid: pid_t, workUnits: Int) {
        self.collector = collector
        self.pid = pid
        self.workUnits = workUnits
        scopeGeneration = collector.scopeGeneration
    }

    func measure<Result>(_ stage: RuntimeFocusedRepairDiagnosticStage, operation: () -> Result) -> Result {
        let token = collector.begin(stage, processIdentifier: pid, scopeGeneration: scopeGeneration)
        defer { collector.end(token, workUnits: workUnits) }
        return operation()
    }
}

final class ControlTabPressureFactProvider: RuntimeProjectionRepairFactProviding {
    let base: any RuntimeProjectionRepairFactProviding
    let context: ControlTabPressureFactContext

    init(base: any RuntimeProjectionRepairFactProviding, context: ControlTabPressureFactContext) {
        self.base = base
        self.context = context
    }

    func collectAXWindowData(
        for runningApps: [NSRunningApplication],
        cgWindowsByPID: [pid_t: [RuntimeCGWindowEntry]],
        allCGWindowsByPID: [pid_t: [RuntimeCGWindowEntry]],
        allCGCollectionIsComplete: Bool
    ) -> [pid_t: [RuntimeWindowListEntry]] {
        context.measure(.axRead) {
            base.collectAXWindowData(for: runningApps, cgWindowsByPID: cgWindowsByPID,
                allCGWindowsByPID: allCGWindowsByPID, allCGCollectionIsComplete: allCGCollectionIsComplete)
        }
    }

    func collectCGWindowsWithSpaceTopologyDiff(options: CGWindowListOption, now: TimeInterval)
        -> RuntimeCGWindowCollection {
        context.measure(options.contains(.optionOnScreenOnly) ? .onScreenCGRead : .allCGRead) {
            base.collectCGWindowsWithSpaceTopologyDiff(options: options, now: now)
        }
    }
}

struct ControlTabPressureWindowEntries: RuntimeWindowEntryProjecting {
    let base: any RuntimeWindowEntryProjecting
    let context: ControlTabPressureFactContext

    func entries(for runningApps: [NSRunningApplication]) -> [pid_t: [RuntimeWindowListEntry]] {
        context.measure(.mappingSpaceFilter) { base.entries(for: runningApps) }
    }
}
#endif
