import AppKit
import Carbon
import CoreGraphics
import FlowTabCore
import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testChordEventMonitorRearmsAfterSystemDisablesTapBeforeKeyUp() {
        let configuration = SwitcherHotkeyConfiguration(
            baseKeys: [.option, .w],
            reverseKeys: [.shift],
            mainKeys: [.tab],
            quitKeys: [.q]
        )
        let monitor = HotkeyChordEventMonitor(
            configuration: configuration,
            transitionDispatcher: { $0() }
        )
        var transitions: [HotkeyChordTransition] = []
        monitor.onTransition = { transitions.append($0) }

        monitor.consume(
            type: .keyDown,
            event: makeChordKeyboardEvent(
                keyCode: UInt16(kVK_ANSI_W),
                flags: .maskAlternate
            )
        )
        monitor.consume(
            type: .keyDown,
            event: makeChordKeyboardEvent(
                keyCode: UInt16(kVK_Tab),
                flags: .maskAlternate
            )
        )
        monitor.consume(
            type: .tapDisabledByTimeout,
            event: makeChordKeyboardEvent(
                keyCode: UInt16(kVK_Tab),
                flags: []
            )
        )
        monitor.consume(
            type: .keyDown,
            event: makeChordKeyboardEvent(
                keyCode: UInt16(kVK_ANSI_W),
                flags: .maskAlternate
            )
        )
        monitor.consume(
            type: .keyDown,
            event: makeChordKeyboardEvent(
                keyCode: UInt16(kVK_Tab),
                flags: .maskAlternate
            )
        )

        XCTAssertEqual(
            transitions,
            [
                HotkeyChordTransition(
                    phase: .pressed,
                    isBackward: false
                ),
                HotkeyChordTransition(
                    phase: .pressed,
                    isBackward: false
                )
            ]
        )
    }

    func testChordEventMonitorDefersTransitionOutsideEventTapCallback() {
        let configuration = SwitcherHotkeyConfiguration(
            baseKeys: [.option, .w],
            reverseKeys: [.shift],
            mainKeys: [.tab],
            quitKeys: [.q]
        )
        var pendingDeliveries: [() -> Void] = []
        let monitor = HotkeyChordEventMonitor(
            configuration: configuration,
            transitionDispatcher: { pendingDeliveries.append($0) }
        )
        var transitions: [HotkeyChordTransition] = []
        monitor.onTransition = { transitions.append($0) }

        monitor.consume(
            type: .keyDown,
            event: makeChordKeyboardEvent(
                keyCode: UInt16(kVK_ANSI_W),
                flags: .maskAlternate
            )
        )
        monitor.consume(
            type: .keyDown,
            event: makeChordKeyboardEvent(
                keyCode: UInt16(kVK_Tab),
                flags: .maskAlternate
            )
        )

        XCTAssertTrue(transitions.isEmpty)
        XCTAssertEqual(pendingDeliveries.count, 1)

        pendingDeliveries.removeFirst()()

        XCTAssertEqual(
            transitions,
            [
                HotkeyChordTransition(
                    phase: .pressed,
                    isBackward: false
                )
            ]
        )
    }

    func testChordEventAccessRequiresAccessibilityBeforeInputMonitoringFallback() {
        XCTAssertEqual(
            HotkeyChordEventAccessSnapshot(
                accessibilityTrusted: true,
                inputMonitoringTrusted: true
            ).availableTapModes,
            [.accessibility, .inputMonitoring]
        )
        XCTAssertEqual(
            HotkeyChordEventAccessSnapshot(
                accessibilityTrusted: false,
                inputMonitoringTrusted: true
            ).availableTapModes,
            []
        )
        XCTAssertFalse(
            HotkeyChordEventAccessSnapshot(
                accessibilityTrusted: false,
                inputMonitoringTrusted: false
            ).hasAvailableTapMode
        )
    }

    func testChordStateMachinesMatchExactRouteWhenChordsShareKeys() {
        let pressedKeys: SwitcherHotkeyKeySet = [
            .control,
            .w,
            .tab
        ]
        var globalStateMachine = HotkeyChordStateMachine(
            forwardKeys: [.control, .w, .tab],
            backwardKeys: [.control, .shift, .w, .tab],
            holdKeys: [.control, .w]
        )
        var inAppStateMachine = HotkeyChordStateMachine(
            forwardKeys: [.control, .tab],
            backwardKeys: [.control, .shift, .tab],
            holdKeys: [.control, .tab]
        )

        XCTAssertEqual(
            globalStateMachine.update(pressedKeys: pressedKeys),
            [HotkeyChordTransition(phase: .pressed, isBackward: false)]
        )
        XCTAssertEqual(
            inAppStateMachine.update(pressedKeys: pressedKeys),
            []
        )
        XCTAssertEqual(
            inAppStateMachine.update(
                pressedKeys: [.control, .tab]
            ),
            [
                HotkeyChordTransition(
                    phase: .pressed,
                    isBackward: false
                )
            ]
        )
    }

    func testHotkeyBackendPolicyCoordinatesBothRoutesWhenEitherNeedsChordMonitoring() {
        let simpleMain = SwitcherHotkeyConfiguration(
            baseKeys: [.option],
            reverseKeys: [.shift],
            mainKeys: [.tab],
            quitKeys: [.q]
        )
        let simpleInApp = SwitcherHotkeyConfiguration.inApp(
            shortcutKeys: [.control, .tab],
            reverseKeys: [.shift]
        )
        let multiKeyMain = SwitcherHotkeyConfiguration(
            baseKeys: [.control, .w],
            reverseKeys: [.shift],
            mainKeys: [.tab],
            quitKeys: [.q]
        )
        let multiKeyInApp = SwitcherHotkeyConfiguration.inApp(
            shortcutKeys: [.control, .w, .tab],
            reverseKeys: [.shift]
        )

        XCTAssertFalse(
            HotkeyMonitoringBackendPolicy
                .requiresCoordinatedChordEventMonitoring(
                    mainConfiguration: simpleMain,
                    inAppWindowConfiguration: simpleInApp
                )
        )
        XCTAssertTrue(
            HotkeyMonitoringBackendPolicy
                .requiresCoordinatedChordEventMonitoring(
                    mainConfiguration: multiKeyMain,
                    inAppWindowConfiguration: simpleInApp
                )
        )
        XCTAssertTrue(
            HotkeyMonitoringBackendPolicy
                .requiresCoordinatedChordEventMonitoring(
                    mainConfiguration: simpleMain,
                    inAppWindowConfiguration: multiKeyInApp
                )
        )
    }

    func testHotkeyMonitoringAccessPolicySeparatesPermissionlessMainRoute() {
        let simpleMain = SwitcherHotkeyConfiguration(
            baseKeys: [.option],
            reverseKeys: [.shift],
            mainKeys: [.tab],
            quitKeys: [.q]
        )
        let multiKeyMain = SwitcherHotkeyConfiguration(
            baseKeys: [.control, .w],
            reverseKeys: [.shift],
            mainKeys: [.tab],
            quitKeys: [.q]
        )
        let simpleInApp = SwitcherHotkeyConfiguration.inApp(
            shortcutKeys: [.control, .tab],
            reverseKeys: [.shift]
        )
        let multiKeyInApp = SwitcherHotkeyConfiguration.inApp(
            shortcutKeys: [.control, .w, .space],
            reverseKeys: [.shift]
        )

        XCTAssertEqual(
            HotkeyMonitoringAccessPolicy.plan(
                mainConfiguration: simpleMain,
                inAppWindowConfiguration: multiKeyInApp,
                accessibilityTrusted: false
            ),
            HotkeyMonitoringAccessPlan(
                mainRouteState: .carbon,
                inAppWindowRouteState: .pausedAccessibility
            )
        )
        XCTAssertEqual(
            HotkeyMonitoringAccessPolicy.plan(
                mainConfiguration: multiKeyMain,
                inAppWindowConfiguration: simpleInApp,
                accessibilityTrusted: false
            ),
            HotkeyMonitoringAccessPlan(
                mainRouteState: .pausedAccessibility,
                inAppWindowRouteState: .pausedAccessibility
            )
        )
        XCTAssertEqual(
            HotkeyMonitoringAccessPolicy.plan(
                mainConfiguration: simpleMain,
                inAppWindowConfiguration: multiKeyInApp,
                accessibilityTrusted: true
            ),
            HotkeyMonitoringAccessPlan(
                mainRouteState: .accessibilityChord,
                inAppWindowRouteState: .accessibilityChord
            )
        )
        XCTAssertEqual(
            HotkeyMonitoringAccessPolicy.plan(
                mainConfiguration: simpleMain,
                inAppWindowConfiguration: simpleInApp,
                accessibilityTrusted: true
            ),
            HotkeyMonitoringAccessPlan(
                mainRouteState: .carbon,
                inAppWindowRouteState: .carbon
            )
        )
    }

    func testCommandTabDetectionIncludesExtraOrdinaryKeysWithExactModifiers() {
        let commandWTab = SwitcherHotkeyConfiguration(
            baseKeys: [.command, .w],
            reverseKeys: [.shift],
            mainKeys: [.tab],
            quitKeys: [.q]
        )
        let commandOptionWTab = SwitcherHotkeyConfiguration(
            baseKeys: [.command, .option, .w],
            reverseKeys: [.shift],
            mainKeys: [.tab],
            quitKeys: [.q]
        )

        XCTAssertTrue(commandWTab.usesCommandTab)
        XCTAssertFalse(commandOptionWTab.usesCommandTab)
    }

    @MainActor
    func testAppDelegateCoordinatesChordBackendForOverlappingRouteKeys() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousAXTrusted =
            AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest =
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        var accessibilityRequestCount = 0
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(
                    name: NSApplication.willTerminateNotification
                )
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AccessibilityPermissionChecker.isTrustedOverrideForTesting =
                previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting =
                previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = {
            true
        }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = {
            accessibilityRequestCount += 1
            return true
        }
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makeHotkeyMonitor: {
                configuration,
                signature,
                forwardHotkeyID,
                backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            hotkeyChordEventAccessSnapshotProvider: {
                HotkeyChordEventAccessSnapshot(
                    accessibilityTrusted: true,
                    inputMonitoringTrusted: false
                )
            },
            commandTabTakeoverController:
                SpyCommandTabTakeoverController(),
            stressRunner: SpyStressRunner()
        )
        userDefaults.set(
            SwitcherHotkeyKeySet([.control, .w]).rawValue,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        )
        userDefaults.set(
            SwitcherHotkeyKeySet([.shift]).rawValue,
            forKey: AppPreferenceKeys.hotkeyReverseModifiers
        )
        userDefaults.set(
            SwitcherHotkeyKeySet([.tab]).rawValue,
            forKey: AppPreferenceKeys.hotkeyMainKey
        )
        userDefaults.set(
            SwitcherHotkeyKeySet([.q]).rawValue,
            forKey: AppPreferenceKeys.hotkeyQuitKey
        )
        userDefaults.set(
            SwitcherHotkeyKeySet([.control, .tab]).rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyShortcutKeys
        )
        userDefaults.set(
            SwitcherHotkeyKeySet([.shift]).rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyReverseKeys
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )

        XCTAssertEqual(hotkeyFactory.records.count, 2)
        XCTAssertTrue(
            hotkeyFactory.records.allSatisfy {
                $0.monitor.requireChordEventMonitoringCallCount == 1
                    && $0.monitor.startCallCount == 1
            }
        )
        XCTAssertEqual(accessibilityRequestCount, 0)

        appDelegate.applicationDidBecomeActive(
            Notification(
                name: NSApplication.didBecomeActiveNotification
            )
        )

        XCTAssertTrue(
            hotkeyFactory.records.allSatisfy {
                $0.monitor.startCallCount == 2
            }
        )
    }

    @MainActor
    func testAppDelegateReconcilesPermissionTierWithoutRewritingPreferences() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousAXTrusted =
            AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest =
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let takeoverController = SpyCommandTabTakeoverController()
        var accessibilityTrusted = false
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AccessibilityPermissionChecker.isTrustedOverrideForTesting =
                previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting =
                previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = {
            accessibilityTrusted
        }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = {
            accessibilityTrusted
        }
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makeHotkeyMonitor: {
                configuration,
                signature,
                forwardHotkeyID,
                backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            hotkeyChordEventAccessSnapshotProvider: {
                HotkeyChordEventAccessSnapshot(
                    accessibilityTrusted: accessibilityTrusted,
                    inputMonitoringTrusted: true
                )
            },
            commandTabTakeoverController: takeoverController,
            stressRunner: SpyStressRunner()
        )
        userDefaults.set(false, forKey: AppPreferenceKeys.showPermissionReminder)
        userDefaults.set(
            "control+w+space",
            forKey: AppPreferenceKeys.inAppWindowHotkeyShortcutKeys
        )
        userDefaults.set(
            "shift",
            forKey: AppPreferenceKeys.inAppWindowHotkeyReverseKeys
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        XCTAssertEqual(hotkeyFactory.records.count, 1)
        XCTAssertEqual(hotkeyFactory.records[0].signature, 0x46544142)
        XCTAssertEqual(
            hotkeyFactory.records[0].monitor
                .requireChordEventMonitoringCallCount,
            0
        )
        XCTAssertEqual(
            appDelegate.latestHotkeyRegistrationEvidence?.mainRouteState,
            .carbon
        )
        XCTAssertEqual(
            appDelegate.latestHotkeyRegistrationEvidence?
                .inAppWindowRouteState,
            .pausedAccessibility
        )

        let arbitraryMain = SwitcherHotkeyConfiguration(
            baseKeys: [.control, .w],
            reverseKeys: [.shift],
            mainKeys: [.tab],
            quitKeys: [.q]
        )
        userDefaults.set(
            arbitraryMain.baseKeys.rawValue,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        )
        let arbitraryRequest = HotkeyRegistrationRequest(
            mainConfiguration: arbitraryMain,
            inAppWindowConfiguration: .inApp(
                shortcutKeys: [.control, .w, .space],
                reverseKeys: [.shift]
            )
        )
        appDelegate.requestHotkeyReload(
            using: arbitraryRequest,
            source: "permission_tier_test"
        )

        XCTAssertFalse(appDelegate.hasMainHotkeyMonitorForTesting)
        XCTAssertFalse(appDelegate.hasInAppHotkeyMonitorForTesting)
        XCTAssertEqual(
            appDelegate.latestHotkeyRegistrationEvidence?.mainRouteState,
            .pausedAccessibility
        )
        XCTAssertEqual(hotkeyFactory.records.count, 1)

        accessibilityTrusted = true
        appDelegate.applicationDidBecomeActive(
            Notification(name: NSApplication.didBecomeActiveNotification)
        )

        XCTAssertEqual(hotkeyFactory.records.count, 3)
        XCTAssertTrue(
            hotkeyFactory.records.suffix(2).allSatisfy {
                $0.monitor.requireChordEventMonitoringCallCount == 1
                    && $0.monitor.startCallCount == 1
            }
        )
        XCTAssertEqual(
            appDelegate.latestHotkeyRegistrationEvidence?.mainRouteState,
            .accessibilityChord
        )
        XCTAssertEqual(
            appDelegate.latestHotkeyRegistrationEvidence?
                .inAppWindowRouteState,
            .accessibilityChord
        )

        accessibilityTrusted = false
        appDelegate.applicationDidBecomeActive(
            Notification(name: NSApplication.didBecomeActiveNotification)
        )

        XCTAssertFalse(appDelegate.hasMainHotkeyMonitorForTesting)
        XCTAssertFalse(appDelegate.hasInAppHotkeyMonitorForTesting)
        XCTAssertEqual(
            appDelegate.latestHotkeyRegistrationEvidence?.mainRouteState,
            .pausedAccessibility
        )
        XCTAssertEqual(
            userDefaults.string(
                forKey: AppPreferenceKeys.hotkeyPrimaryModifier
            ),
            "control+w"
        )
        XCTAssertEqual(takeoverController.reconcileCalls.last, false)
    }

    @MainActor
    func testDeniedFieldRepairsPersistIndependentlyBeforeCarbonResumes() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousAXTrusted =
            AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest =
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AccessibilityPermissionChecker.isTrustedOverrideForTesting =
                previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting =
                previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { false }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = {
            false
        }
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makeHotkeyMonitor: {
                configuration,
                signature,
                forwardHotkeyID,
                backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            hotkeyChordEventAccessSnapshotProvider: {
                HotkeyChordEventAccessSnapshot(
                    accessibilityTrusted: false,
                    inputMonitoringTrusted: true
                )
            },
            commandTabTakeoverController:
                SpyCommandTabTakeoverController(),
            stressRunner: SpyStressRunner()
        )
        let screenshotQuitKeys = SwitcherHotkeyKeySet([
            .r,
            .t,
            SwitcherHotkeyKey(keyCode: UInt16(kVK_ANSI_4))
        ])
        userDefaults.set(false, forKey: AppPreferenceKeys.showPermissionReminder)
        userDefaults.set(
            "option+w",
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        )
        userDefaults.set(
            "shift+c",
            forKey: AppPreferenceKeys.hotkeyReverseModifiers
        )
        userDefaults.set("e+tab", forKey: AppPreferenceKeys.hotkeyMainKey)
        userDefaults.set(
            screenshotQuitKeys.rawValue,
            forKey: AppPreferenceKeys.hotkeyQuitKey
        )
        userDefaults.set(
            "control+space",
            forKey: AppPreferenceKeys.inAppWindowHotkeyShortcutKeys
        )
        userDefaults.set(
            "command",
            forKey: AppPreferenceKeys.inAppWindowHotkeyReverseKeys
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        XCTAssertEqual(
            appDelegate.latestHotkeyRegistrationEvidence?.mainRouteState,
            .pausedAccessibility
        )
        XCTAssertTrue(hotkeyFactory.records.isEmpty)

        @discardableResult
        func apply(
            field: HotkeySettingsField,
            values: AppKitSettingsHotkeyRawValues
        ) -> HotkeySettingsChangeResult {
            HotkeySettingsChangeTransaction.apply(
                HotkeySettingsChangeCandidate(field: field, values: values),
                accessibilityTrusted: false
            ) { request in
                userDefaults.set(
                    request.mainConfiguration.baseKeys.rawValue,
                    forKey: AppPreferenceKeys.hotkeyPrimaryModifier
                )
                userDefaults.set(
                    request.mainConfiguration.reverseKeys.rawValue,
                    forKey: AppPreferenceKeys.hotkeyReverseModifiers
                )
                userDefaults.set(
                    request.mainConfiguration.mainKeys.rawValue,
                    forKey: AppPreferenceKeys.hotkeyMainKey
                )
                userDefaults.set(
                    request.mainConfiguration.quitKeys.rawValue,
                    forKey: AppPreferenceKeys.hotkeyQuitKey
                )
                appDelegate.requestHotkeyReload(
                    using: request,
                    source: "denied_field_repair_test"
                )
            }
        }

        let mainKeyRepair = AppKitSettingsHotkeyRawValues(
            hotkeyPrimaryModifierRaw: "option+w",
            hotkeyReverseModifiersRaw: "shift+c",
            hotkeyMainKeyRaw: "tab",
            hotkeyQuitKeyRaw: screenshotQuitKeys.rawValue,
            inAppWindowHotkeyShortcutKeysRaw: "control+space",
            inAppWindowHotkeyReverseKeysRaw: "command"
        )
        guard case .applied = apply(field: .mainKey, values: mainKeyRepair)
        else {
            return XCTFail("Expected the main key repair to be applied")
        }
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyMainKey),
            "tab"
        )
        XCTAssertEqual(
            appDelegate.latestHotkeyRegistrationEvidence?.mainRouteState,
            .pausedAccessibility
        )

        let mainModifierRepair = AppKitSettingsHotkeyRawValues(
            hotkeyPrimaryModifierRaw: "option",
            hotkeyReverseModifiersRaw: "shift+c",
            hotkeyMainKeyRaw: "tab",
            hotkeyQuitKeyRaw: screenshotQuitKeys.rawValue,
            inAppWindowHotkeyShortcutKeysRaw: "control+space",
            inAppWindowHotkeyReverseKeysRaw: "command"
        )
        guard case .applied = apply(
            field: .mainModifiers,
            values: mainModifierRepair
        ) else {
            return XCTFail("Expected the main modifier repair to be applied")
        }
        XCTAssertEqual(
            userDefaults.string(
                forKey: AppPreferenceKeys.hotkeyPrimaryModifier
            ),
            "option"
        )
        XCTAssertEqual(
            appDelegate.latestHotkeyRegistrationEvidence?.mainRouteState,
            .pausedAccessibility
        )

        let reverseModifierRepair = AppKitSettingsHotkeyRawValues(
            hotkeyPrimaryModifierRaw: "option",
            hotkeyReverseModifiersRaw: "shift",
            hotkeyMainKeyRaw: "tab",
            hotkeyQuitKeyRaw: screenshotQuitKeys.rawValue,
            inAppWindowHotkeyShortcutKeysRaw: "control+space",
            inAppWindowHotkeyReverseKeysRaw: "command"
        )
        guard case .applied = apply(
            field: .mainReverseModifiers,
            values: reverseModifierRepair
        ) else {
            return XCTFail("Expected the reverse modifier repair to be applied")
        }
        XCTAssertEqual(
            userDefaults.string(
                forKey: AppPreferenceKeys.hotkeyReverseModifiers
            ),
            "shift"
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyQuitKey),
            screenshotQuitKeys.rawValue
        )
        XCTAssertEqual(
            appDelegate.latestHotkeyRegistrationEvidence?.mainRouteState,
            .carbon
        )
        XCTAssertEqual(hotkeyFactory.records.map(\.signature), [0x46544142])
    }

    private func makeChordKeyboardEvent(
        keyCode: UInt16,
        flags: CGEventFlags
    ) -> CGEvent {
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(keyCode),
            keyDown: true
        )!
        event.flags = flags
        return event
    }
}
