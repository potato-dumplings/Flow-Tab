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

struct SwitcherWindowCardObservation: Equatable {
    let identifier: String
    let title: String
    let value: String
    let frame: CGRect
    let hasImage: Bool
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

func waitForFrontmostBundleIdentifier(_ bundleIdentifier: String, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier {
            return true
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    return false
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
    func homeWindowRows(in app: XCUIApplication) -> [XCUIElement] {
        let rowIdentifierPrefix = "flowtab.home.window."
        let rowPredicate = NSPredicate(format: "identifier BEGINSWITH %@", rowIdentifierPrefix)
        let buttonRows = app.buttons
            .matching(rowPredicate)
            .allElementsBoundByIndex
        if !buttonRows.isEmpty {
            return buttonRows
        }

        return app.descendants(matching: .any)
            .matching(rowPredicate)
            .allElementsBoundByIndex
    }
    func homeWindowRow(_ row: XCUIElement, contains title: String) -> Bool {
        [
            row.label,
            elementStringValue(row)
        ]
        .contains { source in
            source.localizedCaseInsensitiveContains(title)
        }
    }
    func waitForHomeWindowRow(
        in app: XCUIApplication,
        title: String,
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        var latestRowIdentifiers: [String] = []
        repeat {
            let rows = homeWindowRows(in: app)
            latestRowIdentifiers = rows.map(\.identifier)
            if let row = rows.first(where: { homeWindowRow($0, contains: title) }) {
                return row
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail(
            """
            Expected a Home window row containing \(title), \
            found \(latestRowIdentifiers.sorted()).
            """
        )
        return nil
    }
    func waitForHomeWindowTitle(
        _ title: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.staticTexts[title].exists {
                return true
            }
            if homeWindowRows(in: app).contains(where: { homeWindowRow($0, contains: title) }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }
    func assertHomeWindowTitle(
        _ title: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 12,
        message: String? = nil
    ) {
        XCTAssertTrue(
            waitForHomeWindowTitle(title, in: app, timeout: timeout),
            message ?? "Missing Home window title: \(title)"
        )
    }
    func assertHomeWindowTitlesAbsent(
        _ titles: [String],
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let rows = homeWindowRows(in: app)
            let unexpectedTitles = titles.filter { title in
                app.staticTexts[title].exists
                    || rows.contains(where: { homeWindowRow($0, contains: title) })
            }
            if unexpectedTitles.isEmpty {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        let rows = homeWindowRows(in: app)
        let unexpectedTitles = titles.filter { title in
            app.staticTexts[title].exists
                || rows.contains(where: { homeWindowRow($0, contains: title) })
        }
        XCTFail("Unexpected visible Home window titles: \(unexpectedTitles)")
    }
    func switcherWindowCardObservations(in app: XCUIApplication) -> [SwitcherWindowCardObservation] {
        var seenIdentifiers: Set<String> = []
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "flowtab.switcher.window."))
            .allElementsBoundByAccessibilityElement
            .compactMap { element -> SwitcherWindowCardObservation? in
                guard element.exists else { return nil }
                let identifier = element.identifier
                guard seenIdentifiers.insert(identifier).inserted else { return nil }
                let title = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                let value = elementStringValue(element)
                let frame = element.frame
                let imageMarker = self.element(
                    in: app,
                    identifier: previewImageIdentifier(for: identifier)
                )
                return SwitcherWindowCardObservation(
                    identifier: identifier,
                    title: title,
                    value: value,
                    frame: frame,
                    hasImage: value.contains("preview=image") || imageMarker.exists
                )
            }
    }

    func previewImageIdentifier(for windowIdentifier: String) -> String {
        let windowPrefix = "flowtab.switcher.window."
        let imagePrefix = "flowtab.switcher.window-preview-image."
        guard windowIdentifier.hasPrefix(windowPrefix) else {
            return "\(imagePrefix)\(windowIdentifier)"
        }
        return imagePrefix + windowIdentifier.dropFirst(windowPrefix.count)
    }

    func waitForSwitcherWindowCards(
        in app: XCUIApplication,
        expectedTitles: [String],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let expectedTitleCounts = windowTitleCounts(expectedTitles)
        let cardQuery = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "flowtab.switcher.window."))

        repeat {
            if cardQuery.count == expectedTitles.count,
               expectedTitleCounts.allSatisfy({ title, count in
                   cardQuery.matching(NSPredicate(format: "label == %@", title)).count == count
               }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        let latestTitleCounts = Dictionary(
            uniqueKeysWithValues: expectedTitleCounts.keys.map { title in
                (
                    title,
                    cardQuery.matching(NSPredicate(format: "label == %@", title)).count
                )
            }
        )
        XCTFail(
            """
            Expected switcher window cards to expose \(expectedTitles.sorted()), \
            found cardCount=\(cardQuery.count) matchingTitleCounts=\(latestTitleCounts) \
            expectedTitleCounts=\(expectedTitleCounts).
            """
        )
        return false
    }
    func assertValue(of element: XCUIElement, equals expectedValue: String, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && elementStringValue(element) == expectedValue {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        XCTFail("Expected value '\(expectedValue)' for \(element.identifier), actual: '\(elementStringValue(element))'")
    }
    private func windowTitleCounts(_ titles: [String]) -> [String: Int] {
        titles.reduce(into: [:]) { counts, title in
            counts[title, default: 0] += 1
        }
    }
    func assertValuePrefix(of element: XCUIElement, expectedPrefix: String, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && elementStringValue(element).hasPrefix(expectedPrefix) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        XCTFail(
            "Expected prefix '\(expectedPrefix)' for \(element.identifier), actual: '\(elementStringValue(element))'"
        )
    }
    func waitForLogs(
        in app: XCUIApplication,
        containing markers: [String],
        timeout: TimeInterval = 8
    ) {
        let logsLines = app.descendants(matching: .any)
            .matching(identifier: Identifier.logsLines)
            .firstMatch
        XCTAssertTrue(logsLines.waitForExistence(timeout: timeout), "Missing logs container")

        let deadline = Date().addingTimeInterval(timeout)
        var latestValue = ""
        repeat {
            latestValue = elementStringValue(logsLines)
            if markers.allSatisfy({ latestValue.contains($0) }) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline

        let missingMarkers = markers.filter { !latestValue.contains($0) }
        XCTFail("Missing log markers \(missingMarkers). Latest logs: \(latestValue)")
    }
    func makeRuntimeLogFileSnapshot() -> [String: UInt64] {
        runtimeLogFiles().reduce(into: [:]) { result, url in
            guard let size = runtimeLogFileSize(url) else { return }
            result[url.path] = size
        }
    }
    func waitForRuntimeLogFiles(
        containing markers: [String],
        since snapshot: [String: UInt64],
        timeout: TimeInterval = 8
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        let logsDirectoryURL = runtimeLogsDirectoryURL()
        var latestValue = ""
        repeat {
            latestValue = runtimeLogContents(since: snapshot)
            if markers.allSatisfy({ latestValue.contains($0) }) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline

        let missingMarkers = markers.filter { !latestValue.contains($0) }
        XCTFail(
            "Missing runtime log markers \(missingMarkers) in \(logsDirectoryURL.path). Latest logs: \(latestValue)"
        )
    }

    func waitForRuntimeLogFiles(
        matching pattern: String,
        since snapshot: [String: UInt64],
        timeout: TimeInterval = 8,
        description: String
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        let logsDirectoryURL = runtimeLogsDirectoryURL()
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            return XCTFail("Invalid runtime log regex \(pattern): \(error)")
        }
        var latestValue = ""
        repeat {
            latestValue = runtimeLogContents(since: snapshot)
            let range = NSRange(latestValue.startIndex..<latestValue.endIndex, in: latestValue)
            if regex.firstMatch(in: latestValue, range: range) != nil {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline

        XCTFail(
            "Missing runtime log pattern \(description) / \(pattern) in \(logsDirectoryURL.path). Latest logs: \(latestValue)"
        )
    }

    func waitForRuntimeLogFiles(
        containing requiredMarkers: [String],
        containingOneOf alternativeMarkers: [String],
        since snapshot: [String: UInt64],
        timeout: TimeInterval = 8
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        let logsDirectoryURL = runtimeLogsDirectoryURL()
        var latestValue = ""
        repeat {
            latestValue = runtimeLogContents(since: snapshot)
            if
                requiredMarkers.allSatisfy({ latestValue.contains($0) }),
                alternativeMarkers.contains(where: { latestValue.contains($0) })
            {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline

        let missingRequiredMarkers = requiredMarkers.filter { !latestValue.contains($0) }
        let missingAlternativeMarkers = alternativeMarkers.filter { !latestValue.contains($0) }
        XCTFail(
            "Missing runtime log markers required=\(missingRequiredMarkers) anyOf=\(missingAlternativeMarkers) in \(logsDirectoryURL.path). Latest logs: \(latestValue)"
        )
    }
    func runtimeLogContentsSinceSnapshot(_ snapshot: [String: UInt64]) -> String {
        runtimeLogContents(since: snapshot)
    }
    private func runtimeLogsDirectoryURL() -> URL {
        let fallbackURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fallbackURL
        return baseURL.appendingPathComponent("FlowTab/logs", isDirectory: true)
    }
    private func runtimeLogFiles() -> [URL] {
        let directoryURL = runtimeLogsDirectoryURL()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { $0.pathExtension == "log" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                return lhsDate < rhsDate
            }
    }
    private func runtimeLogFileSize(_ url: URL) -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return (attributes[.size] as? NSNumber)?.uint64Value
    }
    private func runtimeLogContents(since snapshot: [String: UInt64]) -> String {
        runtimeLogFiles()
            .compactMap { url -> String? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                let offset = min(Int(snapshot[url.path] ?? 0), data.count)
                let newData = data.dropFirst(offset)
                return String(data: newData, encoding: .utf8)
            }
            .joined(separator: "\n")
    }
    func replaceText(in field: XCUIElement, with text: String, app: XCUIApplication) {
        tapElement(field)
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        app.typeText(text)
    }
    func commitEditing(in app: XCUIApplication) {
        app.typeKey(.tab, modifierFlags: [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    func tapElement(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
            return
        }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    func assertLogVisibility(
        at logLevel: String,
        visibleIdentifiers: [String],
        hiddenIdentifiers: [String]
    ) {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-seed-logs",
                "4",
                "--flowtab-ui-runtime-log-level",
                logLevel,
                "-showPermissionReminder",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(app)
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }

        XCTAssertTrue(
            tapFirstHittable(in: app.buttons.matching(identifier: Identifier.logsTabButton), timeout: 5),
            "Failed to open logs tab at level \(logLevel)"
        )

        let logsTabContent = app.descendants(matching: .any)
            .matching(identifier: Identifier.logsTabContent)
            .firstMatch
        XCTAssertTrue(logsTabContent.waitForExistence(timeout: 5), "Missing logs tab content at level \(logLevel)")

        let logsLines = app.descendants(matching: .any)
            .matching(identifier: Identifier.logsLines)
            .firstMatch
        XCTAssertTrue(logsLines.waitForExistence(timeout: 8), "Missing logs container at level \(logLevel)")

        for identifier in visibleIdentifiers {
            let line = app.descendants(matching: .any)
                .matching(identifier: identifier)
                .firstMatch
            XCTAssertTrue(
                line.waitForExistence(timeout: 8),
                "Expected visible log row \(identifier) at level \(logLevel)"
            )
        }

        RunLoop.current.run(until: Date().addingTimeInterval(1.2))

        for identifier in hiddenIdentifiers {
            let line = app.descendants(matching: .any)
                .matching(identifier: identifier)
                .firstMatch
            XCTAssertFalse(
                line.exists,
                "Expected hidden log row \(identifier) at level \(logLevel)"
            )
        }
    }
    func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
    func waitForFocusedWorkflowWindow(
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var latestFrontmostBundleIdentifier: String?
        var latestFocusedTitle: String?
        repeat {
            latestFrontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            latestFocusedTitle = activeWindowTitle(forBundleIdentifier: workflowApp.identity.bundleIdentifier)
            if latestFrontmostBundleIdentifier == workflowApp.identity.bundleIdentifier,
               (
                   latestFocusedTitle == title
                       || workflowWindowTitleIsObservable(title, app: workflowApp)
               ) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail(
            """
            Expected frontmost window \(workflowApp.appName) / \(title), \
            found frontmost bundle \(latestFrontmostBundleIdentifier ?? "nil") \
            with active window title \(latestFocusedTitle ?? "nil").
            """
        )
        return false
    }

    func waitForFrontmostWorkflowWindow(
        windowNumber: CGWindowID,
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var latestFrontmostBundleIdentifier: String?
        var latestWindowNumber: CGWindowID?
        var latestFocusedTitle: String?
        repeat {
            latestFrontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let latestCGWindow = frontmostCGWindow(
                forBundleIdentifier: workflowApp.identity.bundleIdentifier,
                expectedTitle: title,
                expectedWindowNumber: windowNumber
            )
            latestWindowNumber = latestCGWindow?.number
            latestFocusedTitle = activeWindowTitle(forBundleIdentifier: workflowApp.identity.bundleIdentifier)
            if latestFrontmostBundleIdentifier == workflowApp.identity.bundleIdentifier,
               (
                   latestCGWindow?.matches(number: windowNumber, title: title) == true
                       || workflowWindowTitleIsObservable(title, app: workflowApp)
               ) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail(
            """
            Expected frontmost window \(workflowApp.appName) / \(title) / \(windowNumber), \
            found frontmost bundle \(latestFrontmostBundleIdentifier ?? "nil") \
            with active window title \(latestFocusedTitle ?? "nil") \
            and window number \(latestWindowNumber.map(String.init) ?? "nil").
            """
        )
        return false
    }

    func assertStaticTextsAbsent(
        _ titles: [String],
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let unexpectedTitles = titles.filter { app.staticTexts[$0].exists }
            if unexpectedTitles.isEmpty {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        let unexpectedTitles = titles.filter { app.staticTexts[$0].exists }
        XCTFail("Unexpected visible window titles: \(unexpectedTitles)")
    }
    func tapFirstHittable(in query: XCUIElementQuery, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let count = query.count
            for index in 0..<count {
                let element = query.element(boundBy: index)
                if element.exists && element.isHittable {
                    element.tap()
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
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
    func hasHittableElement(in query: XCUIElementQuery, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let count = query.count
            for index in 0..<count {
                let element = query.element(boundBy: index)
                if element.exists && element.isHittable {
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
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
