import AppKit
import Carbon
import CoreGraphics
import XCTest

private enum FlowTabUITestShortcutEventInjectionTransport {
    static let notificationName = Notification.Name(
        "io.github.potato-dumplings.flowtab.ui-test.shortcut-event-injection"
    )

    enum UserInfoKey {
        static let targetProcessID = "targetProcessID"
        static let keyCodes = "keyCodes"
        static let modifierFlags = "modifierFlags"
        static let mode = "mode"
        static let phase = "phase"
    }
}

enum FlowTabUITestRecorderInput {
    case key(String)
    case shortcut(String, XCUIElement.KeyModifierFlags)
    case modifiers(XCUIElement.KeyModifierFlags)
    case keySet([CGKeyCode], XCUIElement.KeyModifierFlags)
}

struct FlowTabUITestShortcutRecording {
    let controlIdentifier: String
    let input: FlowTabUITestRecorderInput
    let expectedValue: String

    init(
        controlIdentifier: String,
        key: String,
        modifierFlags: XCUIElement.KeyModifierFlags,
        expectedValue: String
    ) {
        self.controlIdentifier = controlIdentifier
        input = .shortcut(key, modifierFlags)
        self.expectedValue = expectedValue
    }

    static func key(
        controlIdentifier: String,
        key: String,
        expectedValue: String
    ) -> FlowTabUITestShortcutRecording {
        FlowTabUITestShortcutRecording(
            controlIdentifier: controlIdentifier,
            input: .key(key),
            expectedValue: expectedValue
        )
    }

    static func modifiers(
        controlIdentifier: String,
        modifierFlags: XCUIElement.KeyModifierFlags,
        expectedValue: String
    ) -> FlowTabUITestShortcutRecording {
        FlowTabUITestShortcutRecording(
            controlIdentifier: controlIdentifier,
            input: .modifiers(modifierFlags),
            expectedValue: expectedValue
        )
    }

    static func keySet(
        controlIdentifier: String,
        keyCodes: [CGKeyCode],
        modifierFlags: XCUIElement.KeyModifierFlags = [],
        expectedValue: String
    ) -> FlowTabUITestShortcutRecording {
        FlowTabUITestShortcutRecording(
            controlIdentifier: controlIdentifier,
            input: .keySet(keyCodes, modifierFlags),
            expectedValue: expectedValue
        )
    }

    private init(
        controlIdentifier: String,
        input: FlowTabUITestRecorderInput,
        expectedValue: String
    ) {
        self.controlIdentifier = controlIdentifier
        self.input = input
        self.expectedValue = expectedValue
    }
}

extension FlowTabUITests {
    func hotkeyRecordings(
        mainModifiers: XCUIElement.KeyModifierFlags,
        mainModifiersText: String,
        mainKey: String,
        quitKey: String,
        inAppModifiers: XCUIElement.KeyModifierFlags,
        inAppShortcutText: String,
        inAppKey: String,
        mainReverseModifiers: XCUIElement.KeyModifierFlags = .shift,
        mainReverseModifiersText: String = "Shift",
        inAppReverseModifiers: XCUIElement.KeyModifierFlags = .shift,
        inAppReverseModifiersText: String = "Shift"
    ) -> [FlowTabUITestShortcutRecording] {
        [
            FlowTabUITestShortcutRecording(
                controlIdentifier: Identifier.settingsHotkeyInAppShortcut,
                key: inAppKey,
                modifierFlags: inAppModifiers,
                expectedValue: inAppShortcutText
            ),
            .modifiers(
                controlIdentifier: Identifier.settingsHotkeyInAppReverseModifiers,
                modifierFlags: inAppReverseModifiers,
                expectedValue: inAppReverseModifiersText
            ),
            .modifiers(
                controlIdentifier: Identifier.settingsHotkeyMainModifiers,
                modifierFlags: mainModifiers,
                expectedValue: mainModifiersText
            ),
            .modifiers(
                controlIdentifier: Identifier.settingsHotkeyMainReverseModifiers,
                modifierFlags: mainReverseModifiers,
                expectedValue: mainReverseModifiersText
            ),
            .key(
                controlIdentifier: Identifier.settingsHotkeyMainKey,
                key: mainKey,
                expectedValue: shortcutKeyDisplayName(mainKey)
            ),
            .key(
                controlIdentifier: Identifier.settingsHotkeyQuitKey,
                key: quitKey,
                expectedValue: shortcutKeyDisplayName(quitKey)
            )
        ]
    }

    func recordShortcut(
        in app: XCUIApplication,
        _ recording: FlowTabUITestShortcutRecording,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let control: XCUIElement
        switch recording.input {
        case let .key(key):
            control = enterShortcut(
                in: app,
                controlIdentifier: recording.controlIdentifier,
                key: key,
                modifierFlags: [],
                file: file,
                line: line
            )
        case let .shortcut(key, modifierFlags):
            control = enterShortcut(
                in: app,
                controlIdentifier: recording.controlIdentifier,
                key: key,
                modifierFlags: modifierFlags,
                file: file,
                line: line
            )
        case let .modifiers(modifierFlags):
            control = enterModifiers(
                in: app,
                controlIdentifier: recording.controlIdentifier,
                modifierFlags: modifierFlags,
                file: file,
                line: line
            )
        case let .keySet(keyCodes, modifierFlags):
            control = enterKeySet(
                in: app,
                controlIdentifier: recording.controlIdentifier,
                keyCodes: keyCodes,
                modifierFlags: modifierFlags,
                file: file,
                line: line
            )
        }
        assertValue(of: control, equals: recording.expectedValue)
    }

    @discardableResult
    func enterKeySet(
        in app: XCUIApplication,
        controlIdentifier: String,
        keyCodes: [CGKeyCode],
        modifierFlags: XCUIElement.KeyModifierFlags = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let control = element(in: app, identifier: controlIdentifier)
        XCTAssertTrue(
            control.waitForExistence(timeout: 5),
            "Missing key-set recorder \(controlIdentifier)",
            file: file,
            line: line
        )
        tapElement(control)

        let bundleIdentifier = FlowTabUITestAppIdentity.configured().bundleIdentifier
        guard let processID = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first(where: \.isActive)?.processIdentifier else {
            XCTFail(
                "Missing active app process for key-set recorder",
                file: file,
                line: line
            )
            return control
        }
        DistributedNotificationCenter.default().postNotificationName(
            FlowTabUITestShortcutEventInjectionTransport.notificationName,
            object: nil,
            userInfo: [
                FlowTabUITestShortcutEventInjectionTransport.UserInfoKey
                    .targetProcessID: NSNumber(value: processID),
                FlowTabUITestShortcutEventInjectionTransport.UserInfoKey
                    .keyCodes: keyCodes.map(NSNumber.init(value:)),
                FlowTabUITestShortcutEventInjectionTransport.UserInfoKey
                    .modifierFlags: NSNumber(
                        value: recorderModifierFlags(for: modifierFlags).rawValue
                    ),
                FlowTabUITestShortcutEventInjectionTransport.UserInfoKey
                    .mode: "recorder"
            ],
            deliverImmediately: true
        )
        return control
    }

    func injectRuntimeKeySet(
        in app: XCUIApplication,
        keyCodes: [CGKeyCode],
        modifierFlags: XCUIElement.KeyModifierFlags,
        phase: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let bundleIdentifier =
            FlowTabUITestAppIdentity.configured().bundleIdentifier
        guard let processID = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first(where: \.isActive)?.processIdentifier else {
            XCTFail(
                "Missing active app process for runtime key injection",
                file: file,
                line: line
            )
            return
        }
        DistributedNotificationCenter.default().postNotificationName(
            FlowTabUITestShortcutEventInjectionTransport.notificationName,
            object: nil,
            userInfo: [
                FlowTabUITestShortcutEventInjectionTransport.UserInfoKey
                    .targetProcessID: NSNumber(value: processID),
                FlowTabUITestShortcutEventInjectionTransport.UserInfoKey
                    .keyCodes: keyCodes.map(NSNumber.init(value:)),
                FlowTabUITestShortcutEventInjectionTransport.UserInfoKey
                    .modifierFlags: NSNumber(
                        value: recorderModifierFlags(for: modifierFlags).rawValue
                    ),
                FlowTabUITestShortcutEventInjectionTransport.UserInfoKey
                    .mode: "runtime",
                FlowTabUITestShortcutEventInjectionTransport.UserInfoKey
                    .phase: phase
            ],
            deliverImmediately: true
        )
    }

    private func recorderModifierFlags(
        for flags: XCUIElement.KeyModifierFlags
    ) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }

    @discardableResult
    func enterModifiers(
        in app: XCUIApplication,
        controlIdentifier: String,
        modifierFlags: XCUIElement.KeyModifierFlags,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let control = element(in: app, identifier: controlIdentifier)
        XCTAssertTrue(
            control.waitForExistence(timeout: 5),
            "Missing modifier recorder \(controlIdentifier)",
            file: file,
            line: line
        )
        tapElement(control)
        XCUIElement.perform(withKeyModifiers: modifierFlags) {}
        return control
    }

    @discardableResult
    func enterShortcut(
        in app: XCUIApplication,
        controlIdentifier: String,
        key: String,
        modifierFlags: XCUIElement.KeyModifierFlags,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let control = element(in: app, identifier: controlIdentifier)
        XCTAssertTrue(
            control.waitForExistence(timeout: 5),
            "Missing shortcut recorder \(controlIdentifier)",
            file: file,
            line: line
        )
        tapElement(control)
        typeShortcutKey(
            in: app,
            key: key,
            modifierFlags: modifierFlags
        )
        return control
    }

    func configureShortcutsThroughSettings(
        recordings: [FlowTabUITestShortcutRecording],
        expectedLogMarkers: [String]
    ) {
        let app = makeApp(additionalArguments: hotkeyEffectArguments(resetDefaults: true))
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        let logSnapshot = makeRuntimeLogFileSnapshot()
        for recording in recordings {
            recordShortcut(in: app, recording)
        }
        waitForRuntimeLogFiles(containing: expectedLogMarkers, since: logSnapshot)
        app.terminate()
    }

    func typeShortcutKey(
        in app: XCUIApplication,
        key: String,
        modifierFlags: XCUIElement.KeyModifierFlags
    ) {
        switch key {
        case "space":
            app.typeKey(.space, modifierFlags: modifierFlags)
        case "tab":
            app.typeKey(.tab, modifierFlags: modifierFlags)
        case "grave":
            app.typeKey("`", modifierFlags: modifierFlags)
        default:
            app.typeKey(key, modifierFlags: modifierFlags)
        }
    }

    private func shortcutKeyDisplayName(_ key: String) -> String {
        switch key {
        case "space":
            return "Space"
        case "tab":
            return "Tab"
        case "grave":
            return "`"
        default:
            return key.uppercased()
        }
    }
}
