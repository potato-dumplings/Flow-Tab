import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testInAppMainKeyReleaseKeepsSessionUntilBaseKeysRelease() throws {
        let runningApp = NSRunningApplication.current
        let appID = runningApp.bundleIdentifier
            ?? "pid:\(runningApp.processIdentifier)"
        let windows = [
            WindowCandidate(
                id: "in-app-hold-current",
                title: "Current",
                isMinimized: false,
                lastActiveAt: 20
            ),
            WindowCandidate(
                id: "in-app-hold-next",
                title: "Next",
                isMinimized: false,
                lastActiveAt: 10
            )
        ]
        let releaseScheduler = ManualModifierReleaseObservationScheduler()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService:
                    makeCurrentAppWindowProjectionService(
                        appID: appID,
                        runningApp: runningApp,
                        windows: windows
                    )
            ),
            modifierReleaseObservationScheduler: releaseScheduler,
            modifierReleaseEventSource: ManualModifierReleaseEventSource()
        )
        var activatedTarget: ActivationTarget?
        controller.modelForTesting.activationOverride = { target, _ in
            activatedTarget = target
        }
        XCTAssertTrue(controller.beginInAppWindowHotkeySessionForTesting())

        let configuration = InAppWindowHotkeyPreferencesStore.resolve(
            baseKeysRaw: "control",
            reverseKeysRaw: "shift",
            mainKeysRaw: "tab"
        ).configuration
        var stateMachine = HotkeyChordStateMachine(
            forwardKeys: configuration.mainShortcut.keys,
            backwardKeys: configuration.backwardShortcut.keys,
            holdKeys: configuration.baseKeys
        )
        _ = stateMachine.update(pressedKeys: [.control, .tab])
        let tabRelease = try XCTUnwrap(
            stateMachine.update(pressedKeys: [.control]).first
        )

        let inputSource = ManualHotkeyInputSource()
        inputSource.register(on: controller, for: .inAppWindowSwitcher)
        inputSource.deliver(
            HotkeyInputEvent(
                identity: HotkeyInputEventIdentity(
                    sourceID: inputSource.sourceID,
                    sequence: 1
                ),
                phase: tabRelease.phase,
                isBackward: tabRelease.isBackward,
                holdSetPressedEvidence: tabRelease.isHoldSetPressed
            ),
            to: controller,
            for: .inAppWindowSwitcher
        )

        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertFalse(controller.hasPendingModifierReleaseConfirmation)

        inputSource.deliver(
            HotkeyInputEvent(
                identity: HotkeyInputEventIdentity(
                    sourceID: inputSource.sourceID,
                    sequence: 2
                ),
                phase: .released,
                isBackward: false,
                holdSetPressedEvidence: false
            ),
            to: controller,
            for: .inAppWindowSwitcher
        )
        XCTAssertTrue(controller.hasPendingModifierReleaseConfirmation)
        releaseScheduler.fireNext()

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertNotNil(activatedTarget)
    }

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
