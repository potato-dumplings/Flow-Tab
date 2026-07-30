import AppKit
import Foundation
import XCTest

private enum FlowTabUITestAppEnvironmentKey {
    static let appPath = "FLOWTAB_UI_TEST_APP_PATH"
    static let uiTesting = "FLOWTAB_UI_TESTING"
}

private enum FlowTabUITestAppDefaults {
    static let defaultBundleIdentifier = "io.github.potato-dumplings.flowtab"

    static var installedAppURL: URL {
        let sandboxHomeURL = installedAppURL(homeDirectory: NSHomeDirectory())
        if FileManager.default.fileExists(atPath: sandboxHomeURL.path) {
            return sandboxHomeURL
        }

        guard let accountHomeDirectory = NSHomeDirectoryForUser(NSUserName()) else {
            return sandboxHomeURL
        }
        let accountHomeURL = installedAppURL(homeDirectory: accountHomeDirectory)
        if FileManager.default.fileExists(atPath: accountHomeURL.path) {
            return accountHomeURL
        }

        return sandboxHomeURL
    }

    private static func installedAppURL(homeDirectory: String) -> URL {
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("Flow Tab UITest.app", isDirectory: true)
    }
}

private enum FlowTabUITestApplicationTarget: Equatable {
    case url(URL)
    case bundleIdentifier(String)
}

struct FlowTabUITestAppIdentity: Equatable {
    let bundleIdentifier: String
    let appURL: URL?

    static func configured(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultInstalledAppURL: URL = FlowTabUITestAppDefaults.installedAppURL,
        fileExistsAtPath: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> FlowTabUITestAppIdentity {
        if let configuredPath = environment[FlowTabUITestAppEnvironmentKey.appPath]?.trimmedFlowTabUITestValue,
           !configuredPath.isEmpty {
            return identity(for: URL(fileURLWithPath: NSString(string: configuredPath).expandingTildeInPath))
        }

        guard fileExistsAtPath(defaultInstalledAppURL.path) else {
            return FlowTabUITestAppIdentity(
                bundleIdentifier: FlowTabUITestAppDefaults.defaultBundleIdentifier,
                appURL: nil
            )
        }

        return identity(for: defaultInstalledAppURL)
    }

    private static func identity(for appURL: URL) -> FlowTabUITestAppIdentity {
        let resolvedURL = appURL.standardizedFileURL
        return FlowTabUITestAppIdentity(
            bundleIdentifier: Bundle(url: resolvedURL)?.bundleIdentifier
                ?? FlowTabUITestAppDefaults.defaultBundleIdentifier,
            appURL: resolvedURL
        )
    }
}

private extension FlowTabUITestAppIdentity {
    var runningApplicationTargets: [FlowTabUITestApplicationTarget] {
        var targets: [FlowTabUITestApplicationTarget] = []
        if let appURL {
            targets.append(.url(appURL))
        }
        targets.append(.bundleIdentifier(bundleIdentifier))
        return targets
    }
}

private extension String {
    var trimmedFlowTabUITestValue: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func makeFlowTabUITestApplication(
    additionalArguments: [String] = [],
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> XCUIApplication {
    let identity = FlowTabUITestAppIdentity.configured(environment: environment)
    let app: XCUIApplication
    if let appURL = identity.appURL {
        app = XCUIApplication(url: appURL)
    } else {
        app = XCUIApplication()
    }
    app.launchEnvironment[FlowTabUITestAppEnvironmentKey.uiTesting] = "1"
    app.launchArguments += additionalArguments
    return app
}

private func shouldActivateFlowTabUITestApplicationAfterLaunch(
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> Bool {
    FlowTabUITestAppIdentity.configured(environment: environment).appURL != nil
}

func launchFlowTabUITestApplication(
    _ app: XCUIApplication,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    traceLabel: String? = nil
) {
    logFlowTabUITestLaunchTrace(traceLabel, phase: "before app.launch")
    app.launch()
    logFlowTabUITestLaunchTrace(traceLabel, phase: "after app.launch")
    if shouldActivateFlowTabUITestApplicationAfterLaunch(environment: environment) {
        logFlowTabUITestLaunchTrace(traceLabel, phase: "before app.activate")
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 12)
        logFlowTabUITestLaunchTrace(traceLabel, phase: "after app.activate")
    }
}

func waitForFlowTabUITestApplicationToBecomeReady(
    _ app: XCUIApplication,
    timeout: TimeInterval,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    traceLabel: String? = nil
) -> Bool {
    logFlowTabUITestLaunchTrace(traceLabel, phase: "before wait runningForeground")
    if app.wait(for: .runningForeground, timeout: timeout) {
        logFlowTabUITestLaunchTrace(traceLabel, phase: "after wait runningForeground")
        return true
    }

    guard shouldActivateFlowTabUITestApplicationAfterLaunch(environment: environment) else {
        logFlowTabUITestLaunchTrace(traceLabel, phase: "wait failed without activation fallback")
        return false
    }

    logFlowTabUITestLaunchTrace(traceLabel, phase: "before fallback app.activate")
    app.activate()
    let becameReady = app.wait(for: .runningForeground, timeout: min(timeout, 4))
    logFlowTabUITestLaunchTrace(traceLabel, phase: "after fallback app.activate")
    return becameReady
}

private func logFlowTabUITestLaunchTrace(_ label: String?, phase: String) {
    guard let label else { return }
    let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
    logFlowTabUITestTrace("[\(label)] \(phase) frontmost=\(frontmost)")
}

func logFlowTabUITestTrace(_ message: String) {
    let line = "[FlowTabUITests][SpaceTrace] \(message)\n"
    if let data = line.data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

enum FlowTabUITestSwitcherTrigger {
    case global
    case inApp
    case search

    var notificationName: Notification.Name {
        switch self {
        case .global:
            return Notification.Name("io.github.potato-dumplings.flowtab.ui-test.open-global-switcher")
        case .inApp:
            return Notification.Name("io.github.potato-dumplings.flowtab.ui-test.open-in-app-window-switcher")
        case .search:
            return Notification.Name("io.github.potato-dumplings.flowtab.ui-test.open-window-search")
        }
    }
}

enum FlowTabUITestSwitcherCommand {
    case inAppForward
    case advanceDown
    case advanceRight
    case searchQuery
    case selectApp
    case selectSearchResult
    case searchConfirm
    case confirm
    case runtimeLogProbe

    var notificationName: Notification.Name {
        switch self {
        case .inAppForward:
            return Notification.Name(
                "io.github.potato-dumplings.flowtab.ui-test.switcher-command.in-app-forward"
            )
        case .advanceDown:
            return Notification.Name(
                "io.github.potato-dumplings.flowtab.ui-test.switcher-command.advance-down"
            )
        case .advanceRight:
            return Notification.Name(
                "io.github.potato-dumplings.flowtab.ui-test.switcher-command.advance-right"
            )
        case .searchQuery:
            return Notification.Name(
                "io.github.potato-dumplings.flowtab.ui-test.switcher-command.search-query"
            )
        case .selectApp:
            return Notification.Name(
                "io.github.potato-dumplings.flowtab.ui-test.switcher-command.select-app"
            )
        case .selectSearchResult:
            return Notification.Name(
                "io.github.potato-dumplings.flowtab.ui-test.switcher-command.select-search-result"
            )
        case .searchConfirm:
            return Notification.Name(
                "io.github.potato-dumplings.flowtab.ui-test.switcher-command.search-confirm"
            )
        case .confirm:
            return Notification.Name(
                "io.github.potato-dumplings.flowtab.ui-test.switcher-command.confirm"
            )
        case .runtimeLogProbe:
            return Notification.Name(
                "io.github.potato-dumplings.flowtab.ui-test.switcher-command.runtime-log-probe"
            )
        }
    }
}

enum FlowTabUITestSwitcherCommandPayload {
    static let url: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("flowtab-uitest-switcher-command-\(UUID().uuidString).txt")

    static var launchArguments: [String] {
        [
            "--flowtab-ui-switcher-command-payload-path",
            url.path
        ]
    }

    static func write(_ value: String) throws {
        try value.write(to: url, atomically: true, encoding: .utf8)
    }
}

func postFlowTabUITestSwitcherTrigger(
    _ trigger: FlowTabUITestSwitcherTrigger,
    traceLabel: String
) {
    logFlowTabUITestLaunchTrace(traceLabel, phase: "before notification \(trigger)")
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(trigger.notificationName.rawValue as CFString),
        nil,
        nil,
        true
    )
    logFlowTabUITestLaunchTrace(traceLabel, phase: "after notification \(trigger)")
}

func postFlowTabUITestSwitcherCommand(
    _ command: FlowTabUITestSwitcherCommand,
    traceLabel: String
) {
    logFlowTabUITestLaunchTrace(traceLabel, phase: "before command notification \(command)")
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(command.notificationName.rawValue as CFString),
        nil,
        nil,
        true
    )
    logFlowTabUITestLaunchTrace(traceLabel, phase: "after command notification \(command)")
}

func terminateFlowTabUITestApplicationIfRunning(
    environment: [String: String] = ProcessInfo.processInfo.environment
) {
    let identity = FlowTabUITestAppIdentity.configured(environment: environment)
    for target in identity.runningApplicationTargets {
        let app: XCUIApplication
        switch target {
        case .url(let appURL):
            app = XCUIApplication(url: appURL)
        case .bundleIdentifier(let bundleIdentifier):
            app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        }

        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
    }
}

extension FlowTabUITests {
    func makeApp(additionalArguments: [String] = []) -> XCUIApplication {
        makeFlowTabUITestApplication(additionalArguments: additionalArguments)
    }
    func postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
        _ trigger: FlowTabUITestSwitcherTrigger,
        traceLabel: String,
        timeout: TimeInterval = 4
    ) {
        let logSnapshot = makeRuntimeLogFileSnapshot()
        postFlowTabUITestSwitcherTrigger(trigger, traceLabel: traceLabel)
        waitForRuntimeLogFiles(
            containing: [
                "completed switcher trigger notification name=\(trigger.notificationName.rawValue) presented=1"
            ],
            since: logSnapshot,
            timeout: timeout
        )
    }

    func postFlowTabUITestSwitcherCommandAndWaitForDelivery(
        _ command: FlowTabUITestSwitcherCommand,
        traceLabel: String,
        timeout: TimeInterval = 4
    ) {
        let logSnapshot = makeRuntimeLogFileSnapshot()
        postFlowTabUITestSwitcherCommand(command, traceLabel: traceLabel)
        waitForRuntimeLogFiles(
            containing: [
                "completed switcher command notification name=\(command.notificationName.rawValue)"
            ],
            since: logSnapshot,
            timeout: timeout
        )
    }

    func postFlowTabUITestSwitcherSearchQueryAndWaitForDelivery(
        _ query: String,
        traceLabel: String,
        timeout: TimeInterval = 4
    ) throws {
        try FlowTabUITestSwitcherCommandPayload.write(query)
        postFlowTabUITestSwitcherCommandAndWaitForDelivery(
            .searchQuery,
            traceLabel: traceLabel,
            timeout: timeout
        )
    }

    func postFlowTabUITestSelectSwitcherAppAndWaitForDelivery(
        bundleIdentifier: String,
        traceLabel: String,
        timeout: TimeInterval = 4
    ) throws {
        try FlowTabUITestSwitcherCommandPayload.write(bundleIdentifier)
        postFlowTabUITestSwitcherCommandAndWaitForDelivery(
            .selectApp,
            traceLabel: traceLabel,
            timeout: timeout
        )
    }

    func postFlowTabUITestSelectSearchResultAndWaitForDelivery(
        resultID: String,
        traceLabel: String,
        timeout: TimeInterval = 4
    ) throws {
        try FlowTabUITestSwitcherCommandPayload.write(resultID)
        postFlowTabUITestSwitcherCommandAndWaitForDelivery(
            .selectSearchResult,
            traceLabel: traceLabel,
            timeout: timeout
        )
    }

    func settingsReminderToggle(in app: XCUIApplication) -> XCUIElement {
        toggleElement(in: app, identifier: Identifier.permissionReminderSwitch)
    }
    func openSettingsTab(in app: XCUIApplication) {
        XCTAssertTrue(
            tapFirstHittable(in: app.buttons.matching(identifier: Identifier.settingsTabButton), timeout: 6)
        )
        XCTAssertTrue(element(in: app, identifier: Identifier.settingsTabContent).waitForExistence(timeout: 6))
    }
    func openLogsTab(in app: XCUIApplication) {
        XCTAssertTrue(
            tapFirstHittable(in: app.buttons.matching(identifier: Identifier.logsTabButton), timeout: 6)
        )
        XCTAssertTrue(element(in: app, identifier: Identifier.logsTabContent).waitForExistence(timeout: 6))
    }
    func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    func toggleElement(in app: XCUIApplication, identifier: String) -> XCUIElement {
        let switchElement = app.switches[identifier]
        if switchElement.exists || switchElement.waitForExistence(timeout: 1) {
            return switchElement
        }
        return app.checkBoxes[identifier]
    }
    func toggleIsOn(_ element: XCUIElement) -> Bool {
        if let stringValue = element.value as? String {
            let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "1" || normalized == "true" || normalized == "on"
        }
        if let numericValue = element.value as? NSNumber {
            return numericValue.intValue != 0
        }
        return element.isSelected
    }
    func setToggle(_ element: XCUIElement, to expectedValue: Bool) {
        if toggleIsOn(element) != expectedValue {
            tapElement(element)
        }
    }
    func selectOption(
        in app: XCUIApplication,
        controlIdentifier: String,
        optionIdentifier: String
    ) {
        let control = element(in: app, identifier: controlIdentifier)
        XCTAssertTrue(control.waitForExistence(timeout: 6), "Missing control: \(controlIdentifier)")
        tapElement(control)

        if control.elementType == .radioGroup {
            let segmentedOptionQuery = control.descendants(matching: .any).matching(identifier: optionIdentifier)
            if tapFirstHittable(in: segmentedOptionQuery, timeout: 1) {
                return
            }
        }

        let scopedOptionIdentifier = "\(controlIdentifier).option.\(optionIdentifier)"
        let scopedOptionsQuery = app.descendants(matching: .any).matching(identifier: scopedOptionIdentifier)
        if tapFirstHittable(in: scopedOptionsQuery, timeout: 2) {
            return
        }
        let scopedScrollContainer = app.scrollViews["\(controlIdentifier).options"]
        if tapFirstHittableAfterScrolling(in: scopedOptionsQuery, scrollContainer: scopedScrollContainer, timeout: 4) {
            return
        }

        let optionsQuery = app.descendants(matching: .any).matching(identifier: optionIdentifier)
        if tapFirstHittable(in: optionsQuery, timeout: 3) {
            return
        }
        if tapFirstHittable(in: app.menuItems.matching(identifier: optionIdentifier), timeout: 1) {
            return
        }

        let titleCandidates = selectOptionTitleCandidates(
            controlIdentifier: controlIdentifier,
            optionIdentifier: optionIdentifier
        )
        for title in titleCandidates {
            let titleQuery = app.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", title)
            )
            if tapFirstHittable(in: titleQuery, timeout: 1) {
                return
            }
            let menuItemQuery = app.menuItems.matching(NSPredicate(format: "label == %@", title))
            if tapFirstHittable(in: menuItemQuery, timeout: 1) {
                return
            }
        }

        XCTFail("Missing or non-hittable option: \(optionIdentifier)")
    }

    func selectOptionTitleCandidates(controlIdentifier: String, optionIdentifier: String) -> [String] {
        if controlIdentifier == Identifier.settingsAppearanceAppLanguage {
            switch optionIdentifier {
            case "zh-Hans":
                return ["简体中文", "Simplified Chinese"]
            case "en":
                return ["English"]
            default:
                return []
            }
        }

        if controlIdentifier == Identifier.settingsSearchDefaultScope {
            switch optionIdentifier {
            case "app":
                return ["应用", "App"]
            case "window":
                return ["窗口", "Window"]
            default:
                return []
            }
        }

        if [
            Identifier.settingsHotkeyMainModifier,
            Identifier.settingsHotkeyInAppModifier
        ].contains(controlIdentifier) {
            switch optionIdentifier {
            case "option":
                return ["Option"]
            case "control":
                return ["Control"]
            case "command":
                return ["Command"]
            default:
                return []
            }
        }

        if [
            Identifier.settingsHotkeyMainKey,
            Identifier.settingsHotkeyQuitKey,
            Identifier.settingsHotkeyInAppKey
        ].contains(controlIdentifier) {
            switch optionIdentifier {
            case "tab":
                return ["Tab"]
            case "space":
                return ["Space"]
            case "grave":
                return ["`"]
            default:
                return [optionIdentifier.uppercased()]
            }
        }

        return []
    }
    func elementStringValue(_ element: XCUIElement) -> String {
        if let value = element.value as? String {
            return value
        }
        if let numberValue = element.value as? NSNumber {
            return numberValue.stringValue
        }
        return element.label
    }
    func replaceText(in field: XCUIElement, with text: String, app: XCUIApplication) {
        tapElement(field)
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        app.typeText(text)
    }
    func tapElement(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
            return
        }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
    func tapFirstHittableAfterScrolling(
        in query: XCUIElementQuery,
        scrollContainer: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let count = query.count
            var sawExistingElement = false
            for index in 0..<count {
                let element = query.element(boundBy: index)
                if element.exists && element.isHittable {
                    element.tap()
                    return true
                }
                if element.exists, scrollContainer.exists {
                    sawExistingElement = true
                    let deltaY = dropdownOptionScrollDeltaY(for: element, in: scrollContainer)
                    scrollContainer.scroll(byDeltaX: 0, deltaY: deltaY)
                    break
                }
            }
            if !sawExistingElement, scrollContainer.exists {
                scrollContainer.scroll(byDeltaX: 0, deltaY: -420)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }
    private func dropdownOptionScrollDeltaY(
        for element: XCUIElement,
        in container: XCUIElement
    ) -> CGFloat {
        let elementFrame = element.frame
        let containerFrame = container.frame
        guard isUsableFrame(elementFrame), isUsableFrame(containerFrame) else {
            return -420
        }
        if elementFrame.maxY > containerFrame.maxY {
            return -min(max(elementFrame.maxY - containerFrame.maxY, 180), 520)
        }
        if elementFrame.minY < containerFrame.minY {
            return min(max(containerFrame.minY - elementFrame.minY, 180), 520)
        }
        return elementFrame.midY >= containerFrame.midY ? -240 : 240
    }
    func terminateAppIfRunning() {
        terminateFlowTabUITestApplicationIfRunning()
    }

    func testFlowTabUITestAppIdentityUsesEnvironmentOverridePath() {
        let identity = FlowTabUITestAppIdentity.configured(
            environment: [
                FlowTabUITestAppEnvironmentKey.appPath: "~/Applications/Flow Tab UITest.app"
            ]
        )

        XCTAssertEqual(
            identity.appURL?.standardizedFileURL.path,
            FlowTabUITestAppDefaults.installedAppURL.standardizedFileURL.path
        )
        XCTAssertEqual(
            identity.bundleIdentifier,
            FlowTabUITestAppDefaults.defaultBundleIdentifier
        )
    }

    func testFlowTabUITestAppIdentityUsesDefaultInstalledAppWhenPresent() {
        let defaultInstalledAppURL = URL(fileURLWithPath: "/tmp/Flow Tab UITest.app")
        let identity = FlowTabUITestAppIdentity.configured(
            environment: [:],
            defaultInstalledAppURL: defaultInstalledAppURL,
            fileExistsAtPath: { $0 == defaultInstalledAppURL.path }
        )

        XCTAssertEqual(identity.appURL?.standardizedFileURL.path, defaultInstalledAppURL.standardizedFileURL.path)
    }

    func testFlowTabUITestAppIdentityRunningApplicationTargetsIncludeInstalledAppURLAndBundleIdentifier() {
        let installedAppURL = URL(fileURLWithPath: "/tmp/Flow Tab UITest.app")
        let identity = FlowTabUITestAppIdentity.configured(
            environment: [:],
            defaultInstalledAppURL: installedAppURL,
            fileExistsAtPath: { $0 == installedAppURL.path }
        )

        XCTAssertEqual(
            identity.runningApplicationTargets,
            [
                .url(installedAppURL.standardizedFileURL),
                .bundleIdentifier(FlowTabUITestAppDefaults.defaultBundleIdentifier)
            ]
        )
    }

    func testFlowTabUITestAppIdentityRunningApplicationTargetsFallBackToBundleIdentifierWithoutInstalledApp() {
        let defaultInstalledAppURL = URL(fileURLWithPath: "/tmp/Flow Tab UITest.app")
        let identity = FlowTabUITestAppIdentity.configured(
            environment: [:],
            defaultInstalledAppURL: defaultInstalledAppURL,
            fileExistsAtPath: { _ in false }
        )

        XCTAssertEqual(
            identity.runningApplicationTargets,
            [.bundleIdentifier(FlowTabUITestAppDefaults.defaultBundleIdentifier)]
        )
    }
}
