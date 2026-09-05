#if FLOWTAB_TESTING
import Foundation

@MainActor
final class ControlTabPressureSpanRecorder:
    SwitcherInteractionDiagnosticSink
{
    struct ComponentDrainToken: Hashable {
        fileprivate let id: UUID
    }

    private enum Transition {
        case none
        case begin(UInt64, SwitcherInteractionComponent)
        case end(UInt64)
    }

    private struct Boundary {
        let time: UInt64
        let cpu: ControlTabProcessCPUSnapshot
        let transition: Transition
    }

    private struct ActiveComponent {
        let component: SwitcherInteractionComponent
        let parent: SwitcherInteractionComponent?
        let startedAt: UInt64
        let startedCPU: ControlTabProcessCPUSnapshot
        let workUnits: Int
    }

    private struct PhaseState {
        let token: ControlTabPressureMeasurementToken
        var outputSequence: UInt64
        var nextSpanID: UInt64 = 0
        var boundaries: [Boundary]
        var active: [UInt64: ActiveComponent] = [:]
        var components: [ControlTabPressureSpan] = []
    }

    private let clock: any ControlTabProcessCPUClock
    private var state: PhaseState?
    private var phaseGeneration: UInt64 = 0
    private var componentDrainActions: [UUID: () -> Void] = [:]
    private(set) var isComponentRecordingEnabled = true

    init(clock: any ControlTabProcessCPUClock) {
        self.clock = clock
    }

    func setComponentRecordingEnabled(_ isEnabled: Bool) {
        precondition(state == nil)
        isComponentRecordingEnabled = isEnabled
    }

    func cancel() {
        phaseGeneration &+= 1
        state = nil
        componentDrainActions.removeAll()
    }

    func beginPhase(_ token: ControlTabPressureMeasurementToken) {
        phaseGeneration &+= 1
        componentDrainActions.removeAll()
        state = PhaseState(
            token: token,
            outputSequence: token.sequence,
            boundaries: [
                Boundary(
                    time: token.startedAtNanoseconds,
                    cpu: token.startedCPU,
                    transition: .none
                )
            ]
        )
    }

    func setOutputSequence(_ sequence: UInt64) {
        state?.outputSequence = sequence
    }

    var currentGeneration: UInt64 { phaseGeneration }
    func isCurrentGeneration(_ generation: UInt64) -> Bool {
        state != nil && phaseGeneration == generation
    }

    func beginComponent(
        _ component: SwitcherInteractionComponent,
        parent: SwitcherInteractionComponent?,
        workUnits: Int
    ) -> SwitcherInteractionSpanToken? {
        guard isComponentRecordingEnabled, var state else {
            return nil
        }
        state.nextSpanID &+= 1
        let id = state.nextSpanID
        let time = DispatchTime.now().uptimeNanoseconds
        let cpu = clock.snapshot()
        state.boundaries.append(
            Boundary(
                time: time,
                cpu: cpu,
                transition: .begin(id, component)
            )
        )
        state.active[id] = ActiveComponent(
            component: component,
            parent: parent,
            startedAt: time,
            startedCPU: cpu,
            workUnits: max(0, workUnits)
        )
        self.state = state
        return SwitcherInteractionSpanToken(rawValue: id, generation: phaseGeneration)
    }

    func endComponent(
        _ token: SwitcherInteractionSpanToken?,
        outcome: SwitcherInteractionSpanOutcome,
        workUnits: Int?
    ) {
        guard owns(token) else { return }
        endComponent(token, outcome: outcome, workUnits: workUnits,
            completedAt: DispatchTime.now().uptimeNanoseconds, completedCPU: clock.snapshot())
    }

    func owns(_ token: SwitcherInteractionSpanToken?) -> Bool {
        guard let token, token.generation == phaseGeneration else { return false }
        return state?.active[token.rawValue] != nil
    }

    func endComponent(
        _ token: SwitcherInteractionSpanToken?,
        outcome: SwitcherInteractionSpanOutcome,
        workUnits: Int?,
        completedAt time: UInt64,
        completedCPU cpu: ControlTabProcessCPUSnapshot
    ) {
        guard let token, var state,
              token.generation == phaseGeneration,
              let active = state.active.removeValue(
                forKey: token.rawValue
              )
        else {
            return
        }
        state.boundaries.append(
            Boundary(
                time: time,
                cpu: cpu,
                transition: .end(token.rawValue)
            )
        )
        state.components.append(
            componentSpan(
                state: state,
                active: active,
                completedAt: time,
                completedCPU: cpu,
                outcome: outcome.rawValue,
                workUnits: workUnits ?? active.workUnits
            )
        )
        self.state = state
        runComponentDrainActionsIfNeeded()
    }

    @discardableResult
    func afterActiveComponentsDrain(
        _ action: @escaping () -> Void
    ) -> ComponentDrainToken? {
        guard state?.active.isEmpty == false else {
            action()
            return nil
        }
        let token = ComponentDrainToken(id: UUID())
        componentDrainActions[token.id] = action
        return token
    }

    func cancelComponentDrainAction(_ token: ComponentDrainToken?) {
        guard let token else { return }
        componentDrainActions[token.id] = nil
    }

    func recordUnexecutedComponent(
        _ component: SwitcherInteractionComponent,
        parent: SwitcherInteractionComponent?,
        outcome: SwitcherInteractionSpanOutcome,
        workUnits: Int
    ) {
        guard isComponentRecordingEnabled, var state else { return }
        let time = DispatchTime.now().uptimeNanoseconds
        let cpu = state.boundaries.last?.cpu ?? state.token.startedCPU
        let duration = ControlTabPressureMetricRules.duration(
            startedAtNanoseconds: time,
            completedAtNanoseconds: time,
            startedCPU: cpu,
            completedCPU: cpu
        )
        state.components.append(
            ControlTabPressureSpan(
                phase: state.token.phase,
                sequence: state.outputSequence,
                name: component.rawValue,
                parent: parent?.rawValue,
                startedAtNanoseconds: time,
                completedAtNanoseconds: time,
                duration: duration,
                scope: .componentInclusive,
                outcome: outcome.rawValue,
                workUnits: max(0, workUnits)
            )
        )
        self.state = state
    }

    func recordPremeasuredComponent(
        _ span: SwitcherInteractionPremeasuredComponentSpan
    ) {
        guard isComponentRecordingEnabled, var state else { return }
        state.nextSpanID &+= 1
        let id = state.nextSpanID
        let startedCPU = ControlTabProcessCPUSnapshot(
            userNanoseconds: span.startedCPUUserNanoseconds,
            systemNanoseconds: span.startedCPUSystemNanoseconds,
            isValid: span.startedCPUIsValid
        )
        let completedCPU = ControlTabProcessCPUSnapshot(
            userNanoseconds: span.completedCPUUserNanoseconds,
            systemNanoseconds: span.completedCPUSystemNanoseconds,
            isValid: span.completedCPUIsValid
        )
        state.boundaries.append(
            Boundary(
                time: span.startedAtNanoseconds,
                cpu: startedCPU,
                transition: .begin(id, span.component)
            )
        )
        state.boundaries.append(
            Boundary(
                time: span.completedAtNanoseconds,
                cpu: completedCPU,
                transition: .end(id)
            )
        )
        state.components.append(
            ControlTabPressureSpan(
                phase: state.token.phase,
                sequence: state.outputSequence,
                name: span.component.rawValue,
                parent: span.parent?.rawValue,
                startedAtNanoseconds: span.startedAtNanoseconds,
                completedAtNanoseconds: span.completedAtNanoseconds,
                duration: ControlTabPressureMetricRules.duration(
                    startedAtNanoseconds: span.startedAtNanoseconds,
                    completedAtNanoseconds:
                        span.completedAtNanoseconds,
                    startedCPU: startedCPU,
                    completedCPU: completedCPU
                ),
                scope: .componentInclusive,
                outcome: span.outcome.rawValue,
                workUnits: max(0, span.workUnits)
            )
        )
        self.state = state
    }

    func finishPhase(
        completedAtNanoseconds: UInt64,
        completedCPU: ControlTabProcessCPUSnapshot
    ) -> ControlTabPressureSpanEvidence {
        guard var state else {
            return ControlTabPressureSpanEvidence(
                spans: [],
                requiredComponentsPresent: false,
                timelineReconciled: false,
                componentTimingValid: false
            )
        }
        for (id, active) in state.active.sorted(
            by: { $0.key < $1.key }
        ) {
            state.boundaries.append(
                Boundary(
                    time: completedAtNanoseconds,
                    cpu: completedCPU,
                    transition: .end(id)
                )
            )
            state.components.append(
                componentSpan(
                    state: state,
                    active: active,
                    completedAt: completedAtNanoseconds,
                    completedCPU: completedCPU,
                    outcome:
                        SwitcherInteractionSpanOutcome.incomplete.rawValue,
                    workUnits: active.workUnits
                )
            )
        }
        state.active.removeAll()
        state.boundaries.append(
            Boundary(
                time: completedAtNanoseconds,
                cpu: completedCPU,
                transition: .none
            )
        )
        if !isComponentRecordingEnabled {
            state.components = syntheticRequiredComponents(
                state: state,
                completedAtNanoseconds: completedAtNanoseconds,
                completedCPU: completedCPU
            )
        }
        let timeline = makeTimeline(from: state)
        let required = ControlTabPressureSpanRequirements.components(
            for: state.token.phase
        )
        let present = Set(state.components.compactMap {
            SwitcherInteractionComponent(rawValue: $0.name)
        })
        let requiredComponentsPresent = required.isSubset(of: present)
        let phaseDuration = ControlTabPressureMetricRules.duration(
            startedAtNanoseconds: state.token.startedAtNanoseconds,
            completedAtNanoseconds: completedAtNanoseconds,
            startedCPU: state.token.startedCPU,
            completedCPU: completedCPU
        )
        let timelineWall = timeline.reduce(0) {
            $0 + $1.duration.wallMilliseconds
        }
        let timelineCPU = timeline.reduce(0) {
            $0 + $1.duration.cpuTimeMilliseconds
        }
        let reconciled = phaseDuration.isValid
            && abs(timelineWall - phaseDuration.wallMilliseconds) <= 0.5
            && abs(timelineCPU - phaseDuration.cpuTimeMilliseconds) <= 0.5
        let componentsValid = state.components.allSatisfy { span in
            guard span.duration.isValid,
                  span.startedAtNanoseconds
                    >= state.token.startedAtNanoseconds,
                  span.completedAtNanoseconds
                    <= completedAtNanoseconds
            else {
                return false
            }
            switch span.outcome {
            case SwitcherInteractionSpanOutcome.failed.rawValue,
                 SwitcherInteractionSpanOutcome.timedOut.rawValue,
                 SwitcherInteractionSpanOutcome.staleGeneration.rawValue,
                 SwitcherInteractionSpanOutcome.incomplete.rawValue:
                return false
            case SwitcherInteractionSpanOutcome.cancelled.rawValue:
                return state.token.phase == .cancel
                    || state.token.phase == .commit
            default:
                return true
            }
        }
        componentDrainActions.removeAll()
        self.state = nil
        return ControlTabPressureSpanEvidence(
            spans: state.components + timeline,
            requiredComponentsPresent: requiredComponentsPresent,
            timelineReconciled: reconciled,
            componentTimingValid: componentsValid
        )
    }

    private func runComponentDrainActionsIfNeeded() {
        guard state?.active.isEmpty != false,
              !componentDrainActions.isEmpty
        else {
            return
        }
        let actions = Array(componentDrainActions.values)
        componentDrainActions.removeAll()
        actions.forEach { $0() }
    }

    private func componentSpan(
        state: PhaseState,
        active: ActiveComponent,
        completedAt: UInt64,
        completedCPU: ControlTabProcessCPUSnapshot,
        outcome: String,
        workUnits: Int
    ) -> ControlTabPressureSpan {
        ControlTabPressureSpan(
            phase: state.token.phase,
            sequence: state.outputSequence,
            name: active.component.rawValue,
            parent: active.parent?.rawValue,
            startedAtNanoseconds: active.startedAt,
            completedAtNanoseconds: completedAt,
            duration: ControlTabPressureMetricRules.duration(
                startedAtNanoseconds: active.startedAt,
                completedAtNanoseconds: completedAt,
                startedCPU: active.startedCPU,
                completedCPU: completedCPU
            ),
            scope: .componentInclusive,
            outcome: outcome,
            workUnits: max(0, workUnits)
        )
    }

    private func syntheticRequiredComponents(
        state: PhaseState,
        completedAtNanoseconds: UInt64,
        completedCPU: ControlTabProcessCPUSnapshot
    ) -> [ControlTabPressureSpan] {
        ControlTabPressureSpanRequirements.components(
            for: state.token.phase
        ).sorted { $0.rawValue < $1.rawValue }.map { component in
            ControlTabPressureSpan(
                phase: state.token.phase,
                sequence: state.outputSequence,
                name: component.rawValue,
                parent: nil,
                startedAtNanoseconds: completedAtNanoseconds,
                completedAtNanoseconds: completedAtNanoseconds,
                duration: ControlTabPressureMetricRules.duration(
                    startedAtNanoseconds: completedAtNanoseconds,
                    completedAtNanoseconds: completedAtNanoseconds,
                    startedCPU: completedCPU,
                    completedCPU: completedCPU
                ),
                scope: .componentInclusive,
                outcome:
                    SwitcherInteractionSpanOutcome.notRequested.rawValue,
                workUnits: 0
            )
        }
    }

    private func makeTimeline(
        from state: PhaseState
    ) -> [ControlTabPressureSpan] {
        guard state.boundaries.count > 1 else { return [] }
        let sortedBoundaries = state.boundaries.enumerated().sorted {
            if $0.element.time != $1.element.time {
                return $0.element.time < $1.element.time
            }
            return $0.offset < $1.offset
        }.map(\.element)
        let boundaries = monotonicTimelineBoundaries(sortedBoundaries)
        var active: [UInt64: SwitcherInteractionComponent] = [:]
        var result: [ControlTabPressureSpan] = []
        for index in 0..<(boundaries.count - 1) {
            let boundary = boundaries[index]
            switch boundary.transition {
            case .none:
                break
            case .begin(let id, let component):
                active[id] = component
            case .end(let id):
                active[id] = nil
            }
            let next = boundaries[index + 1]
            let names = Set(active.values.map(\.rawValue)).sorted()
            let name: String
            if names.isEmpty {
                name = "unattributed"
            } else if names.count == 1 {
                name = names[0]
            } else {
                name = "overlap:" + names.joined(separator: "+")
            }
            result.append(
                ControlTabPressureSpan(
                    phase: state.token.phase,
                    sequence: state.outputSequence,
                    name: name,
                    parent: nil,
                    startedAtNanoseconds: boundary.time,
                    completedAtNanoseconds: next.time,
                    duration: ControlTabPressureMetricRules.duration(
                        startedAtNanoseconds: boundary.time,
                        completedAtNanoseconds: next.time,
                        startedCPU: boundary.cpu,
                        completedCPU: next.cpu
                    ),
                    scope: .timelineExclusive,
                    outcome:
                        SwitcherInteractionSpanOutcome.completed.rawValue,
                    workUnits: active.count
                )
            )
        }
        return result
    }

    private func monotonicTimelineBoundaries(
        _ boundaries: [Boundary]
    ) -> [Boundary] {
        guard let firstTotal = boundaries.first?.cpu.totalNanoseconds,
              let lastTotal = boundaries.last?.cpu.totalNanoseconds,
              lastTotal >= firstTotal,
              boundaries.allSatisfy({
                  $0.cpu.totalNanoseconds != nil
              })
        else {
            return boundaries
        }

        var previousTotal = firstTotal
        return boundaries.enumerated().map { index, boundary in
            let total = boundary.cpu.totalNanoseconds ?? previousTotal
            let normalizedTotal: UInt64
            if index == boundaries.count - 1 {
                normalizedTotal = lastTotal
            } else {
                normalizedTotal = min(
                    lastTotal,
                    max(previousTotal, total)
                )
            }
            previousTotal = normalizedTotal
            return Boundary(
                time: boundary.time,
                cpu: ControlTabProcessCPUSnapshot(
                    userNanoseconds: normalizedTotal,
                    systemNanoseconds: 0
                ),
                transition: boundary.transition
            )
        }
    }
}
#endif
