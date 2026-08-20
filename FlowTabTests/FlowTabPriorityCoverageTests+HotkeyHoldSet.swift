import AppKit
import Carbon
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    func testOptionTabHotkeyMonitorCarbonReleaseLeavesHoldSetEvidenceUnknown() {
        let monitor = OptionTabHotkeyMonitor(
            configuration: SwitcherHotkeyPreferencesStore.resolve(
                baseKeysRaw: SwitcherHotkeyKey.option.rawValue,
                mainKeysRaw: SwitcherHotkeyKey.tab.rawValue,
                quitKeysRaw: SwitcherHotkeyKey.q.rawValue
            ),
            signature: 0x54455354,
            forwardHotkeyID: 11,
            backwardHotkeyID: 22,
            startsMonitoring: false
        )
        var events: [HotkeyInputEvent] = []
        monitor.onHotkeyEvent = { events.append($0) }

        XCTAssertEqual(
            monitor.dispatchHotkeyEventForTesting(
                id: 11,
                phase: .pressed
            ),
            noErr
        )
        XCTAssertEqual(
            monitor.dispatchHotkeyEventForTesting(
                id: 11,
                phase: .released
            ),
            noErr
        )

        XCTAssertEqual(
            events.map(\.holdSetPressedEvidence),
            [true, nil],
            "A Carbon release identifies the chord transition, not which member of the chord was released."
        )
    }

    @MainActor
    func testGlobalCarbonMainKeyReleaseKeepsSessionUntilModifierRelease() {
        let configuration = SwitcherHotkeyPreferencesStore.resolve(
            baseKeysRaw: "option",
            reverseKeysRaw: "shift",
            mainKeysRaw: "tab",
            quitKeysRaw: "q"
        )
        let restoreConfiguration =
            installTemporarySwitcherHotkeyConfiguration(configuration)
        defer { restoreConfiguration() }

        let releaseScheduler =
            ManualModifierReleaseObservationScheduler()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService:
                    RecordingRuntimeProjectionService(
                        appSwitcherApps: searchScenarioApps()
                    )
            ),
            modifierReleaseObservationScheduler:
                releaseScheduler,
            modifierReleaseEventSource:
                ManualModifierReleaseEventSource()
        )
        controller.modelForTesting.activationOverride = { _, _ in }
        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())

        let inputSource = ManualHotkeyInputSource()
        inputSource.register(on: controller, for: .globalAppSwitcher)
        inputSource.deliver(
            HotkeyInputEvent(
                identity: HotkeyInputEventIdentity(
                    sourceID: inputSource.sourceID,
                    sequence: 1
                ),
                phase: .pressed,
                isBackward: false,
                holdSetPressedEvidence: true
            ),
            to: controller,
            for: .globalAppSwitcher
        )
        controller
            .scheduleModifierReleaseConfirmationAfterRecoveredPresentationIfNeeded(
                trigger: "global_show"
            )
        XCTAssertFalse(controller.hasPendingModifierReleaseConfirmation)

        inputSource.deliver(
            HotkeyInputEvent(
                identity: HotkeyInputEventIdentity(
                    sourceID: inputSource.sourceID,
                    sequence: 2
                ),
                phase: .released,
                isBackward: false,
                holdSetPressedEvidence: true
            ),
            to: controller,
            for: .globalAppSwitcher
        )

        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertFalse(controller.hasPendingModifierReleaseConfirmation)

        controller.handleFlagsChangedForTesting(
            Self.makeFlagsChangedEvent(
                keyCode: UInt16(kVK_Option),
                modifierFlags: []
            )
        )
        XCTAssertTrue(controller.hasPendingModifierReleaseConfirmation)
        releaseScheduler.fireNext()

        XCTAssertNil(controller.modelForTesting.session)
    }

    @MainActor
    func testCarbonQueueModifierMismatchKeepsGlobalSessionUntilHardwareRelease() {
        let configuration = SwitcherHotkeyPreferencesStore.resolve(
            baseKeysRaw: "option",
            reverseKeysRaw: "shift",
            mainKeysRaw: "tab",
            quitKeysRaw: "q"
        )
        let restoreConfiguration =
            installTemporarySwitcherHotkeyConfiguration(configuration)
        defer { restoreConfiguration() }

        let releaseScheduler =
            ManualModifierReleaseObservationScheduler()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService:
                    RecordingRuntimeProjectionService(
                        appSwitcherApps: searchScenarioApps()
                    )
            ),
            modifierReleaseObservationScheduler:
                releaseScheduler,
            modifierReleaseEventSource:
                ManualModifierReleaseEventSource()
        )
        controller.modelForTesting.activationOverride = { _, _ in }
        controller.globalHotkeyHoldSetPressedOverride = true
        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())

        let monitor = OptionTabHotkeyMonitor(
            configuration: configuration,
            signature: 0x54455354,
            forwardHotkeyID: 11,
            backwardHotkeyID: 22,
            startsMonitoring: false
        )
        controller.registerHotkeyInputSource(
            monitor.inputSourceID,
            for: .globalAppSwitcher
        )
        monitor.onHotkeyEvent = {
            controller.handleGlobalHotkeyInput($0)
        }

        XCTAssertEqual(
            monitor.dispatchHotkeyEventForTesting(
                id: 11,
                phase: .released
            ),
            noErr
        )

        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertFalse(
            controller.hasPendingModifierReleaseConfirmation,
            "Queue-synchronized modifier state must not end a session while hardware still reports Option held."
        )

        controller.globalHotkeyHoldSetPressedOverride = false
        controller.handleFlagsChangedForTesting(
            Self.makeFlagsChangedEvent(
                keyCode: UInt16(kVK_Option),
                modifierFlags: []
            )
        )
        XCTAssertTrue(controller.hasPendingModifierReleaseConfirmation)
        releaseScheduler.fireNext()

        XCTAssertNil(controller.modelForTesting.session)
    }

    @MainActor
    func testCarbonUnknownReleaseKeepsInAppSessionUntilControlHardwareRelease() {
        let runningApp = NSRunningApplication.current
        let appID = runningApp.bundleIdentifier
            ?? "pid:\(runningApp.processIdentifier)"
        let windows = [
            WindowCandidate(
                id: "in-app-carbon-current",
                title: "Current",
                isMinimized: false,
                lastActiveAt: 20
            ),
            WindowCandidate(
                id: "in-app-carbon-next",
                title: "Next",
                isMinimized: false,
                lastActiveAt: 10
            )
        ]
        let releaseScheduler =
            ManualModifierReleaseObservationScheduler()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService:
                    makeCurrentAppWindowProjectionService(
                        appID: appID,
                        runningApp: runningApp,
                        windows: windows
                    )
            ),
            modifierReleaseObservationScheduler:
                releaseScheduler,
            modifierReleaseEventSource:
                ManualModifierReleaseEventSource()
        )
        controller.modelForTesting.activationOverride = { _, _ in }
        controller.inAppHotkeyHoldSetPressedOverride = true
        XCTAssertTrue(controller.beginInAppWindowHotkeySessionForTesting())

        let configuration = InAppWindowHotkeyPreferencesStore.resolve(
            baseKeysRaw: "control",
            reverseKeysRaw: "shift",
            mainKeysRaw: "tab"
        ).configuration
        let monitor = OptionTabHotkeyMonitor(
            configuration: configuration,
            signature: 0x54455354,
            forwardHotkeyID: 11,
            backwardHotkeyID: 22,
            startsMonitoring: false
        )
        controller.registerHotkeyInputSource(
            monitor.inputSourceID,
            for: .inAppWindowSwitcher
        )
        monitor.onHotkeyEvent = {
            controller.handleInAppWindowHotkeyInput($0)
        }

        XCTAssertEqual(
            monitor.dispatchHotkeyEventForTesting(
                id: 11,
                phase: .released
            ),
            noErr
        )

        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertFalse(controller.hasPendingModifierReleaseConfirmation)

        controller.inAppHotkeyHoldSetPressedOverride = false
        controller.handleFlagsChangedForTesting(
            Self.makeFlagsChangedEvent(
                keyCode: UInt16(kVK_Control),
                modifierFlags: []
            )
        )
        XCTAssertTrue(controller.hasPendingModifierReleaseConfirmation)
        releaseScheduler.fireNext()

        XCTAssertNil(controller.modelForTesting.session)
    }

    @MainActor
    func testGlobalModifierReleaseWhilePanelHiddenAllowsNextSession() {
        let configuration = SwitcherHotkeyPreferencesStore.resolve(
            baseKeysRaw: "option",
            reverseKeysRaw: "shift",
            mainKeysRaw: "tab",
            quitKeysRaw: "q"
        )
        let restoreConfiguration =
            installTemporarySwitcherHotkeyConfiguration(configuration)
        defer { restoreConfiguration() }

        let releaseScheduler =
            ManualModifierReleaseObservationScheduler()
        let releaseEventSource = ManualModifierReleaseEventSource()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService:
                    RecordingRuntimeProjectionService(
                        appSwitcherApps: searchScenarioApps()
                    )
            ),
            modifierReleaseObservationScheduler:
                releaseScheduler,
            modifierReleaseEventSource:
                releaseEventSource
        )
        controller.modelForTesting.activationOverride = { _, _ in }
        controller.globalMainKeySetPressedOverride = false

        let inputSource = ManualHotkeyInputSource()
        inputSource.register(on: controller, for: .globalAppSwitcher)
        var sequence: UInt64 = 0
        func deliver(
            phase: HotkeyInputEvent.Phase,
            holdSetPressedEvidence: Bool
        ) {
            sequence &+= 1
            inputSource.deliver(
                HotkeyInputEvent(
                    identity: HotkeyInputEventIdentity(
                        sourceID: inputSource.sourceID,
                        sequence: sequence
                    ),
                    phase: phase,
                    isBackward: false,
                    holdSetPressedEvidence: holdSetPressedEvidence
                ),
                to: controller,
                for: .globalAppSwitcher
            )
        }

        deliver(phase: .pressed, holdSetPressedEvidence: true)
        controller.panelVisibilityOverride = true
        deliver(phase: .released, holdSetPressedEvidence: true)
        controller.globalHotkeyHoldSetPressedOverride = false
        controller.handleFlagsChangedForTesting(
            Self.makeFlagsChangedEvent(
                keyCode: UInt16(kVK_Option),
                modifierFlags: []
            )
        )
        releaseScheduler.fireNext()

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertFalse(
            controller.suppressHotkeyReplayUntilReleaseForTesting
        )

        deliver(phase: .pressed, holdSetPressedEvidence: true)
        controller.panelVisibilityOverride = true
        deliver(phase: .released, holdSetPressedEvidence: true)
        controller.panelVisibilityOverride = false
        controller.globalHotkeyHoldSetPressedOverride = true
        controller.cancelSelectionForSystemInterruption(
            trigger: "panel_visibility_recovery"
        )

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertTrue(
            controller.suppressHotkeyReplayUntilReleaseForTesting
        )

        controller.globalHotkeyHoldSetPressedOverride = false
        controller.handleFlagsChangedForTesting(
            Self.makeFlagsChangedEvent(
                keyCode: UInt16(kVK_Option),
                modifierFlags: []
            )
        )
        releaseEventSource.emitInputTransition()

        XCTAssertFalse(
            controller.suppressHotkeyReplayUntilReleaseForTesting,
            "A physical modifier release must clear replay suppression while the panel is hidden."
        )

        deliver(phase: .pressed, holdSetPressedEvidence: true)

        XCTAssertNotNil(
            controller.modelForTesting.session,
            "The next deliberate global hotkey press must start a new switcher session."
        )
    }

    @MainActor
    func testInAppModifierReleaseWhilePanelHiddenClearsReplaySuppression() {
        let defaults = UserDefaults.standard
        let values: [(String, String)] = [
            (AppPreferenceKeys.inAppWindowHotkeyBaseKeys, "control"),
            (AppPreferenceKeys.inAppWindowHotkeyReverseKeys, "shift"),
            (AppPreferenceKeys.inAppWindowHotkeyMainKeys, "tab")
        ]
        let previousValues = values.reduce(
            into: [String: Any]()
        ) { result, entry in
            result[entry.0] = defaults.object(forKey: entry.0)
        }
        for (key, value) in values {
            defaults.set(value, forKey: key)
        }
        defer {
            for (key, _) in values {
                restoreUserDefaultsValue(
                    previousValues[key],
                    forKey: key,
                    userDefaults: defaults
                )
            }
        }

        let releaseScheduler =
            ManualModifierReleaseObservationScheduler()
        let releaseEventSource = ManualModifierReleaseEventSource()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(),
            modifierReleaseObservationScheduler:
                releaseScheduler,
            modifierReleaseEventSource:
                releaseEventSource
        )
        controller.inAppMainKeySetPressedOverride = false
        let inputSource = ManualHotkeyInputSource()
        inputSource.register(on: controller, for: .inAppWindowSwitcher)
        controller.updateHotkeyHoldSetPressedEvidence(
            true,
            for: .inAppWindowSwitcher
        )
        controller.inAppHotkeyHoldSetPressedOverride = true
        controller.beginHotkeyReplaySuppressionUntilRelease(
            for: .inAppWindowSwitcher,
            trigger: "hidden_in_app_panel"
        )

        XCTAssertTrue(
            controller.suppressHotkeyReplayUntilReleaseForTesting
        )

        controller.inAppHotkeyHoldSetPressedOverride = false
        controller.handleFlagsChangedForTesting(
            Self.makeFlagsChangedEvent(
                keyCode: UInt16(kVK_Control),
                modifierFlags: []
            )
        )

        XCTAssertFalse(
            controller.suppressHotkeyReplayUntilReleaseForTesting
        )
        XCTAssertEqual(releaseScheduler.pendingCount, 0)
        XCTAssertEqual(releaseEventSource.activeObserverCount, 0)
    }

    @MainActor
    func testHiddenModifierReleaseReplaySuppressionPressureCleansEveryObservation() {
        let configuration = SwitcherHotkeyPreferencesStore.resolve(
            baseKeysRaw: "option",
            reverseKeysRaw: "shift",
            mainKeysRaw: "tab",
            quitKeysRaw: "q"
        )
        let restoreConfiguration =
            installTemporarySwitcherHotkeyConfiguration(configuration)
        defer { restoreConfiguration() }

        let releaseScheduler =
            ManualModifierReleaseObservationScheduler()
        let releaseEventSource = ManualModifierReleaseEventSource()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(),
            modifierReleaseObservationScheduler:
                releaseScheduler,
            modifierReleaseEventSource:
                releaseEventSource
        )
        let inputSource = ManualHotkeyInputSource()
        inputSource.register(on: controller, for: .globalAppSwitcher)

        for iteration in 1...1_000 {
            controller.globalHotkeyHoldSetPressedOverride = true
            controller.updateHotkeyHoldSetPressedEvidence(
                true,
                for: .globalAppSwitcher
            )
            controller.beginHotkeyReplaySuppressionUntilRelease(
                for: .globalAppSwitcher,
                trigger: "hidden_release_pressure_\(iteration)"
            )

            XCTAssertTrue(
                controller.suppressHotkeyReplayUntilReleaseForTesting,
                "iteration \(iteration)"
            )

            controller.globalHotkeyHoldSetPressedOverride = false
            controller.handleFlagsChangedForTesting(
                Self.makeFlagsChangedEvent(
                    keyCode: UInt16(kVK_Option),
                    modifierFlags: []
                )
            )

            XCTAssertFalse(
                controller.suppressHotkeyReplayUntilReleaseForTesting,
                "iteration \(iteration)"
            )
            XCTAssertEqual(
                releaseScheduler.pendingCount,
                0,
                "iteration \(iteration)"
            )
            XCTAssertEqual(
                releaseEventSource.activeObserverCount,
                0,
                "iteration \(iteration)"
            )
        }
    }

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

        controller.globalHotkeyHoldSetPressedOverride = false
        releaseScheduler.fireNext()

        XCTAssertEqual(activatedTargets.count, 1)
        XCTAssertFalse(controller.hasPendingModifierReleaseConfirmation)
    }
}
