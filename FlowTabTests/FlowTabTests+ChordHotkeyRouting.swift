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

    func testChordEventAccessPrefersAccessibilityAndFallsBackToInputMonitoring() {
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
            [.inputMonitoring]
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
            backwardKeys: [.control, .shift, .w, .tab]
        )
        var inAppStateMachine = HotkeyChordStateMachine(
            forwardKeys: [.control, .tab],
            backwardKeys: [.control, .shift, .tab]
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
                    accessibilityTrusted: false,
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
        XCTAssertEqual(accessibilityRequestCount, 1)

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
