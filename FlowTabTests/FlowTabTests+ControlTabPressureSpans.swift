import Foundation
import XCTest
@testable import FlowTab

private final class IncrementingControlTabCPUClock:
    ControlTabProcessCPUClock
{
    private var totalNanoseconds: UInt64 = 0
    private(set) var snapshotCount = 0

    func snapshot() -> ControlTabProcessCPUSnapshot {
        snapshotCount += 1
        totalNanoseconds &+= 1_000
        return ControlTabProcessCPUSnapshot(
            userNanoseconds: totalNanoseconds,
            systemNanoseconds: 0
        )
    }
}

extension FlowTabTests {
    @MainActor
    func testControlTabLateComponentCompletionCannotDrainNextPhase() {
        let recorder = ControlTabPressureSpanRecorder(clock: IncrementingControlTabCPUClock())
        recorder.beginPhase(makeControlTabSpanToken(phase: .cooldown))
        let old = recorder.beginComponent(.previewCapture, parent: .previewPlanning, workUnits: 1)
        recorder.beginPhase(makeControlTabSpanToken(phase: .cooldown))
        let current = recorder.beginComponent(.previewCapture, parent: .previewPlanning, workUnits: 1)
        XCTAssertEqual(old?.rawValue, current?.rawValue)
        var drained = false
        _ = recorder.afterActiveComponentsDrain { drained = true }
        recorder.endComponent(old)
        XCTAssertFalse(drained)
        recorder.endComponent(current)
        XCTAssertTrue(drained)
    }

    func testControlTabPhysicalSelectionLatchesTargetAtRealDraw() {
        var expectation = ControlTabPressureSelectionRenderExpectation(
            selectedWindowIDBefore: "window-1",
            renderGenerationBefore: 7
        )

        expectation.observeCommandReturn(
            selectedWindowID: "window-1",
            renderGeneration: 7
        )
        XCTAssertFalse(
            expectation.matchesReadback(selectedWindowID: "window-2")
        )
        XCTAssertTrue(
            expectation.acceptDraw(
                selectedWindowID: "window-2",
                renderGeneration: 8,
                currentRenderGeneration: 8
            )
        )
        XCTAssertEqual(expectation.selectedWindowID, "window-2")
        XCTAssertEqual(expectation.renderGeneration, 8)
        XCTAssertTrue(
            expectation.matchesReadback(selectedWindowID: "window-2")
        )
    }

    func testControlTabSelectionRejectsStaleOrSupersededDraw() {
        var expectation = ControlTabPressureSelectionRenderExpectation(
            selectedWindowIDBefore: "window-1",
            renderGenerationBefore: 7
        )

        XCTAssertFalse(
            expectation.acceptDraw(
                selectedWindowID: "window-2",
                renderGeneration: 7,
                currentRenderGeneration: 7
            )
        )
        XCTAssertFalse(
            expectation.acceptDraw(
                selectedWindowID: "window-2",
                renderGeneration: 8,
                currentRenderGeneration: 9
            )
        )
    }

    func testControlTabSynchronousSelectionKeepsCommandTarget() {
        var expectation = ControlTabPressureSelectionRenderExpectation(
            selectedWindowIDBefore: "window-1",
            renderGenerationBefore: 7
        )

        expectation.observeCommandReturn(
            selectedWindowID: "window-2",
            renderGeneration: 8
        )
        XCTAssertTrue(
            expectation.acceptDraw(
                selectedWindowID: "window-2",
                renderGeneration: 8,
                currentRenderGeneration: 8
            )
        )
        XCTAssertFalse(
            expectation.acceptDraw(
                selectedWindowID: "window-3",
                renderGeneration: 9,
                currentRenderGeneration: 9
            )
        )
    }

    @MainActor
    func testControlTabSpanTimelineReconcilesOverlappingComponents() {
        let clock = IncrementingControlTabCPUClock()
        let recorder = ControlTabPressureSpanRecorder(clock: clock)
        let token = makeControlTabSpanToken(phase: .cooldown)
        recorder.beginPhase(token)
        let outer = recorder.beginComponent(.inputRouting)
        let inner = recorder.beginComponent(
            .selectionMutation,
            parent: .inputRouting
        )
        recorder.endComponent(inner)
        recorder.endComponent(outer)
        let completed = DispatchTime.now().uptimeNanoseconds
        let evidence = recorder.finishPhase(
            completedAtNanoseconds: completed,
            completedCPU: clock.snapshot()
        )

        let timeline = evidence.spans.filter {
            $0.scope == .timelineExclusive
        }
        let components = evidence.spans.filter {
            $0.scope == .componentInclusive
        }
        XCTAssertTrue(evidence.timelineReconciled)
        XCTAssertTrue(evidence.componentTimingValid)
        XCTAssertEqual(components.count, 2)
        XCTAssertTrue(
            timeline.contains {
                $0.name.contains("overlap:")
                    && $0.name.contains("input_routing")
                    && $0.name.contains("selection_mutation")
            }
        )
    }

    @MainActor
    func testControlTabSpanCompletionWaitsForActiveComponentsToDrain() {
        let clock = IncrementingControlTabCPUClock()
        let recorder = ControlTabPressureSpanRecorder(clock: clock)
        recorder.beginPhase(makeControlTabSpanToken(phase: .open))
        let outer = recorder.beginComponent(.previewImageProcessCache)
        let inner = recorder.beginComponent(
            .previewBatchPublication,
            parent: .previewCapture
        )
        var completionCount = 0

        let drainToken = recorder.afterActiveComponentsDrain {
            completionCount += 1
        }
        XCTAssertNotNil(drainToken)
        XCTAssertEqual(completionCount, 0)

        recorder.endComponent(inner)
        XCTAssertEqual(completionCount, 0)
        recorder.endComponent(outer)
        XCTAssertEqual(completionCount, 1)
    }

    @MainActor
    func testControlTabSpanCompletionRunsImmediatelyWhenAlreadyDrained() {
        let recorder = ControlTabPressureSpanRecorder(
            clock: IncrementingControlTabCPUClock()
        )
        recorder.beginPhase(makeControlTabSpanToken(phase: .open))
        var didComplete = false

        let drainToken = recorder.afterActiveComponentsDrain {
            didComplete = true
        }

        XCTAssertNil(drainToken)
        XCTAssertTrue(didComplete)
    }

    @MainActor
    func testControlTabSpanTimelineNormalizesConcurrentCPUSnapshotOrder() {
        let clock = IncrementingControlTabCPUClock()
        let recorder = ControlTabPressureSpanRecorder(clock: clock)
        let startedAt: UInt64 = 1_000
        let token = ControlTabPressureMeasurementToken(
            sequence: 9,
            phase: .cooldown,
            startedAtNanoseconds: startedAt,
            startedCPU: ControlTabProcessCPUSnapshot(
                userNanoseconds: 0,
                systemNanoseconds: 0
            ),
            panelWasPresented: false,
            selectedAppIDBefore: nil,
            selectedWindowIDBefore: nil,
            selectedWindowCountBefore: 0,
            activationRequestGenerationBefore: 0,
            activationVerificationGenerationBefore: 0,
            completeProjectionUpdateGenerationBefore: 0,
            focusedSessionDiagnosticGenerationBefore: 0,
            windowContentRenderGenerationBefore: 0,
            reusableShellPreparationGenerationBefore: 0,
            panelHiddenGenerationBefore: 0,
            cleanupCompleteGenerationBefore: 0,
            presentationCleanupRequiredBefore: false
        )
        recorder.beginPhase(token)
        recorder.recordPremeasuredComponent(
            SwitcherInteractionPremeasuredComponentSpan(
                component: .previewCapture,
                parent: nil,
                startedAtNanoseconds: startedAt + 100,
                completedAtNanoseconds: startedAt + 400,
                startedCPUUserNanoseconds: 20,
                startedCPUSystemNanoseconds: 0,
                startedCPUIsValid: true,
                completedCPUUserNanoseconds: 40,
                completedCPUSystemNanoseconds: 0,
                completedCPUIsValid: true,
                outcome: .completed,
                workUnits: 1
            )
        )
        recorder.recordPremeasuredComponent(
            SwitcherInteractionPremeasuredComponentSpan(
                component: .previewScreenshotManagerCapture,
                parent: .previewCapture,
                startedAtNanoseconds: startedAt + 101,
                completedAtNanoseconds: startedAt + 300,
                startedCPUUserNanoseconds: 10,
                startedCPUSystemNanoseconds: 0,
                startedCPUIsValid: true,
                completedCPUUserNanoseconds: 30,
                completedCPUSystemNanoseconds: 0,
                completedCPUIsValid: true,
                outcome: .completed,
                workUnits: 1
            )
        )

        let evidence = recorder.finishPhase(
            completedAtNanoseconds: startedAt + 500,
            completedCPU: ControlTabProcessCPUSnapshot(
                userNanoseconds: 50,
                systemNanoseconds: 0
            )
        )

        XCTAssertTrue(evidence.timelineReconciled)
        XCTAssertTrue(evidence.componentTimingValid)
        XCTAssertTrue(
            evidence.spans
                .filter { $0.scope == .timelineExclusive }
                .allSatisfy(\.duration.isValid)
        )
    }

    @MainActor
    func testControlTabSpanExplicitUnexecutedOutcomesSatisfySchema() {
        let clock = IncrementingControlTabCPUClock()
        let recorder = ControlTabPressureSpanRecorder(clock: clock)
        let token = makeControlTabSpanToken(phase: .open)
        recorder.beginPhase(token)
        for component in ControlTabPressureSpanRequirements.components(
            for: .open
        ) {
            recorder.recordUnexecutedComponent(
                component,
                outcome: .notRequired
            )
        }
        XCTAssertEqual(clock.snapshotCount, 0)
        let evidence = recorder.finishPhase(
            completedAtNanoseconds:
                DispatchTime.now().uptimeNanoseconds,
            completedCPU: clock.snapshot()
        )

        XCTAssertTrue(evidence.requiredComponentsPresent)
        XCTAssertTrue(evidence.componentTimingValid)
        XCTAssertTrue(evidence.timelineReconciled)
        XCTAssertTrue(
            evidence.spans
                .filter { $0.scope == .componentInclusive }
                .allSatisfy { $0.outcome == "not_required" }
        )
    }

    @MainActor
    func testControlTabSpanPendingEvidenceKeepsTimingValid() {
        let clock = IncrementingControlTabCPUClock()
        let recorder = ControlTabPressureSpanRecorder(clock: clock)
        let token = makeControlTabSpanToken(phase: .cooldown)
        recorder.beginPhase(token)
        let span = recorder.beginComponent(.projectionRead)
        recorder.endComponent(span, outcome: .pendingEvidence)
        let evidence = recorder.finishPhase(
            completedAtNanoseconds:
                DispatchTime.now().uptimeNanoseconds,
            completedCPU: clock.snapshot()
        )

        XCTAssertTrue(evidence.componentTimingValid)
        XCTAssertTrue(evidence.isValid)
        XCTAssertTrue(
            evidence.spans.contains {
                $0.scope == .componentInclusive
                    && $0.name
                        == SwitcherInteractionComponent
                            .projectionRead.rawValue
                    && $0.outcome
                        == SwitcherInteractionSpanOutcome
                            .pendingEvidence.rawValue
            }
        )
    }

    @MainActor
    func testControlTabExternalOnlyRecorderAvoidsComponentCPUSnapshots() {
        let clock = IncrementingControlTabCPUClock()
        let recorder = ControlTabPressureSpanRecorder(clock: clock)
        recorder.setComponentRecordingEnabled(false)
        let token = makeControlTabSpanToken(phase: .open)
        recorder.beginPhase(token)

        XCTAssertNil(recorder.beginComponent(.inputRouting))
        recorder.recordUnexecutedComponent(
            .projectionRead,
            outcome: .notRequired
        )
        recorder.recordPremeasuredComponent(
            SwitcherInteractionPremeasuredComponentSpan(
                component: .axRead,
                parent: .axCGSpaceReconciliation,
                startedAtNanoseconds: token.startedAtNanoseconds,
                completedAtNanoseconds: token.startedAtNanoseconds,
                startedCPUUserNanoseconds: 0,
                startedCPUSystemNanoseconds: 0,
                startedCPUIsValid: true,
                completedCPUUserNanoseconds: 0,
                completedCPUSystemNanoseconds: 0,
                completedCPUIsValid: true,
                outcome: .completed,
                workUnits: 1
            )
        )
        let completedAt = DispatchTime.now().uptimeNanoseconds
        let evidence = recorder.finishPhase(
            completedAtNanoseconds: completedAt,
            completedCPU: ControlTabProcessCPUSnapshot(
                userNanoseconds: 0,
                systemNanoseconds: 0
            )
        )

        XCTAssertEqual(clock.snapshotCount, 0)
        XCTAssertTrue(evidence.isValid)
        let components = evidence.spans.filter {
            $0.scope == .componentInclusive
        }
        XCTAssertEqual(
            Set(components.map(\.name)),
            Set(
                ControlTabPressureSpanRequirements.components(
                    for: .open
                ).map(\.rawValue)
            )
        )
        XCTAssertTrue(
            components.allSatisfy {
                $0.outcome == "not_requested"
                    && $0.duration.wallMilliseconds == 0
                    && $0.duration.cpuTimeMilliseconds == 0
            }
        )
        XCTAssertTrue(
            evidence.spans
                .filter { $0.scope == .timelineExclusive }
                .allSatisfy { $0.name == "unattributed" }
        )
    }

    @MainActor
    func testControlTabSpanStaleGenerationInvalidatesEvidence() {
        let clock = IncrementingControlTabCPUClock()
        let recorder = ControlTabPressureSpanRecorder(clock: clock)
        let token = makeControlTabSpanToken(phase: .cooldown)
        recorder.beginPhase(token)
        let span = recorder.beginComponent(.projectionRead)
        recorder.endComponent(span, outcome: .staleGeneration)
        let evidence = recorder.finishPhase(
            completedAtNanoseconds:
                DispatchTime.now().uptimeNanoseconds,
            completedCPU: clock.snapshot()
        )

        XCTAssertFalse(evidence.componentTimingValid)
        XCTAssertFalse(evidence.isValid)
    }

    @MainActor
    func testControlTabSpanFailedComponentInvalidatesEvidence() {
        let clock = IncrementingControlTabCPUClock()
        let recorder = ControlTabPressureSpanRecorder(clock: clock)
        let token = makeControlTabSpanToken(phase: .cooldown)
        recorder.beginPhase(token)
        let span = recorder.beginComponent(.previewCapture)
        recorder.endComponent(span, outcome: .failed)
        let evidence = recorder.finishPhase(
            completedAtNanoseconds:
                DispatchTime.now().uptimeNanoseconds,
            completedCPU: clock.snapshot()
        )

        XCTAssertFalse(evidence.componentTimingValid)
        XCTAssertFalse(evidence.isValid)
    }

    @MainActor
    func testControlTabSpanImportsBackgroundRuntimeRepairBoundaries() {
        let clock = IncrementingControlTabCPUClock()
        let recorder = ControlTabPressureSpanRecorder(clock: clock)
        let now = DispatchTime.now().uptimeNanoseconds
        let started = now - 1_000_000
        let token = ControlTabPressureMeasurementToken(
            sequence: 9,
            phase: .cooldown,
            startedAtNanoseconds: started,
            startedCPU: ControlTabProcessCPUSnapshot(
                userNanoseconds: 0,
                systemNanoseconds: 0
            ),
            panelWasPresented: false,
            selectedAppIDBefore: nil,
            selectedWindowIDBefore: nil,
            selectedWindowCountBefore: 0,
            activationRequestGenerationBefore: 0,
            activationVerificationGenerationBefore: 0,
            completeProjectionUpdateGenerationBefore: 0,
            focusedSessionDiagnosticGenerationBefore: 0,
            windowContentRenderGenerationBefore: 0,
            reusableShellPreparationGenerationBefore: 0,
            panelHiddenGenerationBefore: 0,
            cleanupCompleteGenerationBefore: 0,
            presentationCleanupRequiredBefore: false
        )
        recorder.beginPhase(token)
        recorder.recordRuntimeFocusedRepairSpans(
            [
                RuntimeFocusedRepairDiagnosticSpan(
                    processIdentifier: 42,
                    stage: .axRead,
                    startedAtNanoseconds: started + 100_000,
                    completedAtNanoseconds: started + 200_000,
                    startedCPU: RuntimeFocusedRepairCPUSnapshot(
                        userNanoseconds: 100,
                        systemNanoseconds: 0,
                        isValid: true
                    ),
                    completedCPU: RuntimeFocusedRepairCPUSnapshot(
                        userNanoseconds: 200,
                        systemNanoseconds: 0,
                        isValid: true
                    ),
                    workUnits: 3
                )
            ]
        )
        let evidence = recorder.finishPhase(
            completedAtNanoseconds:
                DispatchTime.now().uptimeNanoseconds,
            completedCPU: clock.snapshot()
        )

        XCTAssertTrue(evidence.timelineReconciled)
        XCTAssertTrue(evidence.componentTimingValid)
        XCTAssertTrue(
            evidence.spans.contains {
                $0.name == "ax_read"
                    && $0.scope == .componentInclusive
                    && $0.parent == "ax_cg_space_reconciliation"
                    && $0.workUnits == 3
            }
        )
    }

    func testRuntimeFocusedRepairCollectorDrainsByPID() {
        let collector = RuntimeFocusedRepairDiagnosticCollector.shared
        collector.setEnabled(true)
        collector.reset()
        defer { collector.setEnabled(false) }
        let token = collector.begin(
            .onScreenCGRead,
            processIdentifier: 42
        )
        collector.end(token, workUnits: 5)

        XCTAssertTrue(collector.drain(processIdentifier: 7).isEmpty)
        let spans = collector.drain(processIdentifier: 42)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].stage, .onScreenCGRead)
        XCTAssertEqual(spans[0].workUnits, 5)
        XCTAssertTrue(spans[0].startedCPU.isValid)
        XCTAssertTrue(spans[0].completedCPU.isValid)
    }

    @MainActor
    func testControlTabRuntimeRepairMarksPrePhaseStagesNotRequested() {
        let clock = IncrementingControlTabCPUClock()
        let recorder = ControlTabPressureSpanRecorder(clock: clock)
        let token = makeControlTabSpanToken(phase: .open)
        recorder.beginPhase(token)
        let repairStages = Set([
            SwitcherInteractionComponent.onScreenCGRead,
            .allCGRead,
            .axRead,
            .mappingSpaceFilter
        ])
        for component in ControlTabPressureSpanRequirements.components(
            for: .open
        ) where !repairStages.contains(component) {
            recorder.recordUnexecutedComponent(
                component,
                outcome: .notRequired
            )
        }
        let started = token.startedAtNanoseconds + 10_000
        recorder.recordRuntimeFocusedRepairSpans([
            RuntimeFocusedRepairDiagnosticSpan(
                processIdentifier: 42,
                stage: .axRead,
                startedAtNanoseconds: started,
                completedAtNanoseconds: started + 10_000,
                startedCPU: RuntimeFocusedRepairCPUSnapshot(
                    userNanoseconds: 1_000,
                    systemNanoseconds: 0,
                    isValid: true
                ),
                completedCPU: RuntimeFocusedRepairCPUSnapshot(
                    userNanoseconds: 2_000,
                    systemNanoseconds: 0,
                    isValid: true
                ),
                workUnits: 1
            )
        ])
        let evidence = recorder.finishPhase(
            completedAtNanoseconds:
                token.startedAtNanoseconds + 100_000,
            completedCPU: clock.snapshot()
        )
        let componentSpans = evidence.spans.filter {
            $0.scope == .componentInclusive
        }

        XCTAssertTrue(evidence.requiredComponentsPresent)
        XCTAssertTrue(
            componentSpans.contains {
                $0.name == "ax_read" && $0.outcome == "completed"
            }
        )
        for name in [
            "on_screen_cg_read", "all_cg_read",
            "mapping_space_filter"
        ] {
            XCTAssertTrue(
                componentSpans.contains {
                    $0.name == name
                        && $0.outcome == "not_requested"
                }
            )
        }
    }

    func testControlTabNoOpCancelAcceptsExistingReusableShell() {
        let token = makeControlTabSpanToken(phase: .cancel)
        let activeToken = makeControlTabSpanToken(
            phase: .cancel,
            presentationCleanupRequired: true
        )

        XCTAssertTrue(
            token.reusableShellPreparationCompleted(at: 0)
        )
        XCTAssertFalse(
            activeToken.reusableShellPreparationCompleted(at: 0)
        )
        XCTAssertTrue(
            activeToken.reusableShellPreparationCompleted(at: 1)
        )
    }

    private func makeControlTabSpanToken(
        phase: ControlTabPressurePhase,
        presentationCleanupRequired: Bool = false
    ) -> ControlTabPressureMeasurementToken {
        ControlTabPressureMeasurementToken(
            sequence: 1,
            phase: phase,
            startedAtNanoseconds:
                DispatchTime.now().uptimeNanoseconds,
            startedCPU: ControlTabProcessCPUSnapshot(
                userNanoseconds: 0,
                systemNanoseconds: 0
            ),
            panelWasPresented: false,
            selectedAppIDBefore: nil,
            selectedWindowIDBefore: nil,
            selectedWindowCountBefore: 0,
            activationRequestGenerationBefore: 0,
            activationVerificationGenerationBefore: 0,
            completeProjectionUpdateGenerationBefore: 0,
            focusedSessionDiagnosticGenerationBefore: 0,
            windowContentRenderGenerationBefore: 0,
            reusableShellPreparationGenerationBefore: 0,
            panelHiddenGenerationBefore: 0,
            cleanupCompleteGenerationBefore: 0,
            presentationCleanupRequiredBefore:
                presentationCleanupRequired
        )
    }
}
