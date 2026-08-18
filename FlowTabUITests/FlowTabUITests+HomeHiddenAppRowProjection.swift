import XCTest

enum FlowTabUITestHomeHiddenAppRowProjectionPolicy {
    static let rows = [
        FlowTabUITestHomeAppRowProjectionExpectation.Row(
            identifier: FlowTabUITests.Identifier.homeAppMockBrowser,
            value: nil
        ),
        FlowTabUITestHomeAppRowProjectionExpectation.Row(
            identifier: FlowTabUITests.Identifier.homeAppMockMail,
            value: nil
        )
    ]

    static func acceptsHiddenMailState(
        _ snapshot: FlowTabUITestHomeAppRowProjectionSnapshot
    ) -> Bool {
        isHiddenAccessibilityValue(
            snapshot.row(
                identifier: FlowTabUITests.Identifier.homeAppMockMail
            )?.value
        )
    }

    static func isHiddenAccessibilityValue(_ value: String?) -> Bool {
        guard let value else { return false }
        let components = value.split(
            separator: " ",
            omittingEmptySubsequences: false
        )
        guard components.count == 2,
              components[1] == "hidden",
              components[0].last == "w",
              let windowCount = Int(components[0].dropLast()),
              windowCount >= 0,
              value == "\(windowCount)w hidden"
        else {
            return false
        }
        return true
    }

    static var diagnosticSummary: String {
        "identifier=\(FlowTabUITests.Identifier.homeAppMockMail) "
            + "expectedValue=<nonnegative-window-count>w hidden"
    }
}

extension FlowTabUITests {
    func assertHomeAndLogsHiddenAppRowsAfterNavigation(
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> FlowTabUITestHomeAppRowProjectionSnapshot? {
        var acceptsEvidence = false
        let observation = makeHomeAppRowProjectionObservation(
            in: app,
            rows: FlowTabUITestHomeHiddenAppRowProjectionPolicy.rows,
            acceptsEvidence: { acceptsEvidence },
            acceptsSnapshot:
                FlowTabUITestHomeHiddenAppRowProjectionPolicy
                    .acceptsHiddenMailState,
            snapshotExpectationDescription: {
                FlowTabUITestHomeHiddenAppRowProjectionPolicy
                    .diagnosticSummary
            }
        )
        observation.start()
        defer { observation.cancel() }

        let didNavigate =
            assertHomeAndLogsHomeTabProjectionAfterNavigation(
                in: app,
                targetDescription: targetDescription,
                file: file,
                line: line
            )
        acceptsEvidence = true
        observation.requestReadback(source: .triggerReadback)
        guard didNavigate else { return nil }

        guard let evidence = observation.waitForResolution(
            timeout:
                FlowTabUITestHomeAndLogsWatchdogPolicy
                    .hiddenAppRowProjectionReadiness
        ) else {
            XCTFail(
                "Home hidden-App row projection watchdog expired. "
                    + "target=\(targetDescription) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return nil
        }
        return evidence.value
    }
}
