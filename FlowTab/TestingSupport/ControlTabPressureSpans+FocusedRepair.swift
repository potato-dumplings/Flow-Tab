#if FLOWTAB_TESTING
import Foundation

@MainActor
extension ControlTabPressureSpanRecorder {
    func recordRuntimeFocusedRepairSpans(
        _ spans: [RuntimeFocusedRepairDiagnosticSpan]
    ) {
        var recordedComponents = Set<SwitcherInteractionComponent>()
        for span in spans {
            guard let component = SwitcherInteractionComponent(
                rawValue: span.stage.rawValue
            ) else {
                continue
            }
            recordedComponents.insert(component)
            recordPremeasuredComponent(
                SwitcherInteractionPremeasuredComponentSpan(
                    component: component,
                    parent: .axCGSpaceReconciliation,
                    startedAtNanoseconds: span.startedAtNanoseconds,
                    completedAtNanoseconds:
                        span.completedAtNanoseconds,
                    startedCPUUserNanoseconds:
                        span.startedCPU.userNanoseconds,
                    startedCPUSystemNanoseconds:
                        span.startedCPU.systemNanoseconds,
                    startedCPUIsValid: span.startedCPU.isValid,
                    completedCPUUserNanoseconds:
                        span.completedCPU.userNanoseconds,
                    completedCPUSystemNanoseconds:
                        span.completedCPU.systemNanoseconds,
                    completedCPUIsValid: span.completedCPU.isValid,
                    outcome: .completed,
                    workUnits: span.workUnits
                )
            )
        }
        for component in [
            SwitcherInteractionComponent.onScreenCGRead,
            .allCGRead,
            .axRead,
            .mappingSpaceFilter
        ] where !recordedComponents.contains(component) {
            recordUnexecutedComponent(
                component,
                parent: .axCGSpaceReconciliation,
                outcome: .notRequested,
                workUnits: 0
            )
        }
    }
}
#endif
