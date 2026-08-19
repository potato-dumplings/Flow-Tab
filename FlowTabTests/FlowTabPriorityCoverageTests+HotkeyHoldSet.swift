import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testSwitcherPanelControllerChordReleaseEvidenceReplacesSpeculativeConfirmation() {
        let releaseScheduler = ManualModifierReleaseObservationScheduler()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: RecordingRuntimeProjectionService(
                    appSwitcherApps: searchScenarioApps()
                )
            ),
            modifierReleaseObservationScheduler: releaseScheduler,
            modifierReleaseEventSource: ManualModifierReleaseEventSource()
        )
        var activatedTargets: [ActivationTarget] = []
        controller.modelForTesting.activationOverride = { target, _ in
            activatedTargets.append(target)
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.globalHotkeyHoldSetPressedOverride = true
        controller.scheduleModifierReleaseConfirmation(
            trigger: "flags_changed"
        )
        let speculativeGeneration =
            controller.modifierReleaseConfirmationGeneration
        XCTAssertEqual(
            controller.modifierReleaseState,
            .pressed(generation: speculativeGeneration)
        )

        controller.scheduleModifierReleaseConfirmation(
            trigger: "hotkey_released",
            holdSetPressedEvidence: false
        )
        let chordReleaseGeneration =
            controller.modifierReleaseConfirmationGeneration
        XCTAssertGreaterThan(
            chordReleaseGeneration,
            speculativeGeneration
        )
        XCTAssertEqual(
            controller.modifierReleaseState,
            .confirming(
                trigger: "hotkey_released",
                generation: chordReleaseGeneration,
                releasedSamples: 1
            )
        )

        releaseScheduler.fireNext()

        XCTAssertEqual(activatedTargets.count, 1)
        XCTAssertFalse(controller.hasPendingModifierReleaseConfirmation)
    }
}
