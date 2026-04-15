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
    let app: XCUIApplication
    if let appURL = identity.appURL {
        app = XCUIApplication(url: appURL)
    } else {
        app = XCUIApplication()
    }

    if app.state == .runningForeground || app.state == .runningBackground {
        app.terminate()
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
}
