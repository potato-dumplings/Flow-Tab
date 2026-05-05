import AppKit
import ApplicationServices
import Foundation
import XCTest

private enum FlowTabUITestAppEnvironmentKey {
    static let appPath = "FLOWTAB_UI_TEST_APP_PATH"
}

private enum FlowTabUITestAppDefaults {
    static let defaultBundleIdentifier = "io.github.potato-dumplings.flowtab"

    static var installedAppURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
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
    environment: [String: String] = ProcessInfo.processInfo.environment
) {
    app.launch()
    if shouldActivateFlowTabUITestApplicationAfterLaunch(environment: environment) {
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 12)
    }
}

func waitForFlowTabUITestApplicationToBecomeReady(
    _ app: XCUIApplication,
    timeout: TimeInterval,
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> Bool {
    if app.wait(for: .runningForeground, timeout: timeout) {
        return true
    }

    guard shouldActivateFlowTabUITestApplicationAfterLaunch(environment: environment) else {
        return false
    }

    app.activate()
    return app.wait(for: .runningForeground, timeout: min(timeout, 4))
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

        let scopedOptionIdentifier = "\(controlIdentifier).option.\(optionIdentifier)"
        let scopedOptionsQuery = app.descendants(matching: .any).matching(identifier: scopedOptionIdentifier)
        if tapFirstHittable(in: scopedOptionsQuery, timeout: 2) {
            return
        }

        let optionsQuery = app.descendants(matching: .any).matching(identifier: optionIdentifier)
        XCTAssertTrue(
            tapFirstHittable(in: optionsQuery, timeout: 6),
            "Missing or non-hittable option: \(optionIdentifier)"
        )
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
        let buttonRows = app.buttons.allElementsBoundByIndex.filter {
            $0.exists && $0.identifier.hasPrefix("flowtab.home.window.")
        }
        if !buttonRows.isEmpty {
            return buttonRows
        }

        return app.descendants(matching: .any).allElementsBoundByIndex.filter {
            $0.exists && $0.identifier.hasPrefix("flowtab.home.window.")
        }
    }
    func homeWindowRow(_ row: XCUIElement, contains title: String) -> Bool {
        [
            row.label,
            elementStringValue(row),
            String(row.debugDescription.prefix(1_200))
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
            .allElementsBoundByIndex
            .compactMap { element in
                guard element.exists else { return nil }
                guard seenIdentifiers.insert(element.identifier).inserted else { return nil }
                let title = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                return SwitcherWindowCardObservation(
                    identifier: element.identifier,
                    title: title
                )
            }
    }
    func waitForSwitcherWindowCards(
        in app: XCUIApplication,
        expectedTitles: [String],
        timeout: TimeInterval
    ) -> [SwitcherWindowCardObservation] {
        let deadline = Date().addingTimeInterval(timeout)
        var latestCards: [SwitcherWindowCardObservation] = []
        let expectedTitleCounts = windowTitleCounts(expectedTitles)

        repeat {
            latestCards = switcherWindowCardObservations(in: app)
            if latestCards.count == expectedTitles.count,
               windowTitleCounts(latestCards.map(\.title)) == expectedTitleCounts {
                return latestCards
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail(
            """
            Expected switcher window cards to expose \(expectedTitles.sorted()), \
            found \(latestCards.map { "\($0.title)=\($0.identifier)" }.sorted()).
            """
        )
        return latestCards
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
    func tapElementAfterScrollingIntoView(
        _ element: XCUIElement,
        in scrollContainer: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var attempt = 0
        repeat {
            if element.exists && element.isHittable {
                element.tap()
                return true
            }

            if scrollContainer.exists {
                let deltaY: CGFloat = attempt < 12 ? 280 : -280
                scrollContainer.scroll(byDeltaX: 0, deltaY: deltaY)
                attempt = (attempt + 1) % 24
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        if element.exists && element.isHittable {
            element.tap()
            return true
        }
        return false
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
               latestFocusedTitle == title {
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
            latestWindowNumber = frontmostCGWindowNumber(
                forBundleIdentifier: workflowApp.identity.bundleIdentifier
            )
            latestFocusedTitle = activeWindowTitle(forBundleIdentifier: workflowApp.identity.bundleIdentifier)
            if latestFrontmostBundleIdentifier == workflowApp.identity.bundleIdentifier,
               latestWindowNumber == windowNumber {
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

    private func activeWindowTitle(forBundleIdentifier bundleIdentifier: String) -> String? {
        guard let runningApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated })
        else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        return windowTitle(
            for: kAXFocusedWindowAttribute as CFString,
            in: appElement
        ) ?? windowTitle(
            for: kAXMainWindowAttribute as CFString,
            in: appElement
        ) ?? frontmostCGWindowTitle(forPID: runningApp.processIdentifier)
    }

    private func frontmostCGWindowNumber(forBundleIdentifier bundleIdentifier: String) -> CGWindowID? {
        guard let runningApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated })
        else {
            return nil
        }

        return frontmostCGWindow(forPID: runningApp.processIdentifier)?.number
    }

    private func frontmostCGWindowTitle(forPID pid: pid_t) -> String? {
        frontmostCGWindow(forPID: pid)?.title
    }

    private func frontmostCGWindow(forPID pid: pid_t) -> (number: CGWindowID, title: String?)? {
        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return nil
        }

        for window in windows {
            guard cgWindowPID(window[kCGWindowOwnerPID as String]) == pid else {
                continue
            }
            guard (window[kCGWindowLayer as String] as? Int) == 0 else {
                continue
            }
            let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            guard alpha > 0 else { continue }
            guard let number = cgWindowNumber(window[kCGWindowNumber as String]) else {
                continue
            }

            let title = (window[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (number: number, title: title?.isEmpty == false ? title : nil)
        }

        return nil
    }

    private func cgWindowPID(_ value: Any?) -> pid_t? {
        if let pid = value as? pid_t {
            return pid
        }
        if let number = value as? NSNumber {
            return pid_t(number.int32Value)
        }
        return nil
    }

    private func cgWindowNumber(_ value: Any?) -> CGWindowID? {
        if let windowNumber = value as? CGWindowID {
            return windowNumber
        }
        if let number = value as? NSNumber {
            return CGWindowID(number.uint32Value)
        }
        return nil
    }

    private func windowTitle(for attribute: CFString, in appElement: AXUIElement) -> String? {
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            attribute,
            &windowValue
        ) == .success,
            let windowValue
        else {
            return nil
        }

        let window = windowValue as! AXUIElement
        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXTitleAttribute as CFString,
            &titleValue
        ) == .success else {
            return nil
        }

        return (titleValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
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
