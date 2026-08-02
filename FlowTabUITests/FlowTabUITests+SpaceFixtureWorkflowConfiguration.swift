import Foundation
import XCTest

private enum SpaceFixtureConfiguredContentUITestPolicy {
    static let publicationWatchdog: TimeInterval = 5
}

private struct SpaceFixtureConfiguredContentExpectation:
    Equatable
{
    let identifier: String
    let label: String
}

private struct SpaceFixtureConfiguredContentObservation:
    Equatable
{
    let expectation:
        SpaceFixtureConfiguredContentExpectation
    let exists: Bool
    let observedLabel: String

    var isSatisfied: Bool {
        exists && observedLabel == expectation.label
    }

    var diagnosticSummary: String {
        "identifier=\(expectation.identifier) "
            + "expectedLabel=\(expectation.label) "
            + "exists=\(exists) "
            + "observedLabel=\(observedLabel)"
    }
}

private struct SpaceFixtureConfiguredContentSnapshot:
    Equatable
{
    let applicationState: String
    let observations:
        [SpaceFixtureConfiguredContentObservation]

    var isSatisfied: Bool {
        !observations.isEmpty
            && observations.allSatisfy(\.isSatisfied)
    }

    var diagnosticSummary: String {
        "applicationState=\(applicationState) observations="
            + observations
            .map { "{\($0.diagnosticSummary)}" }
            .joined(separator: ",")
    }
}

private final class SpaceFixtureConfiguredContentObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            SpaceFixtureConfiguredContentSnapshot
        >

    init(
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            SpaceFixtureConfiguredContentSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: \.isSatisfied,
            describe: \.diagnosticSummary
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(timeout: TimeInterval)
        -> FlowTabUITestConditionEvidence<
            SpaceFixtureConfiguredContentSnapshot
        >?
    {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    func testSpaceFixtureConfiguredContentPolicyCompatibility() {
        XCTAssertEqual(
            SpaceFixtureConfiguredContentUITestPolicy
                .publicationWatchdog,
            5
        )
        XCTAssertTrue(
            SpaceFixtureConfiguredContentUITestPolicy
                .publicationWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            SpaceFixtureConfiguredContentUITestPolicy
                .publicationWatchdog,
            0
        )
    }

    func testSpaceFixtureConfiguredContentRequiresEveryExactLabel() {
        let expectation =
            SpaceFixtureConfiguredContentExpectation(
                identifier: "fixture.title",
                label: "Docs"
            )
        let exact = SpaceFixtureConfiguredContentSnapshot(
            applicationState: "runningForeground",
            observations: [
                SpaceFixtureConfiguredContentObservation(
                    expectation: expectation,
                    exists: true,
                    observedLabel: "Docs"
                )
            ]
        )
        let missing = SpaceFixtureConfiguredContentSnapshot(
            applicationState: "runningForeground",
            observations: [
                SpaceFixtureConfiguredContentObservation(
                    expectation: expectation,
                    exists: false,
                    observedLabel: "<missing>"
                )
            ]
        )
        let wrongLabel = SpaceFixtureConfiguredContentSnapshot(
            applicationState: "runningForeground",
            observations: [
                SpaceFixtureConfiguredContentObservation(
                    expectation: expectation,
                    exists: true,
                    observedLabel: "Mail"
                )
            ]
        )

        XCTAssertTrue(exact.isSatisfied)
        XCTAssertFalse(missing.isSatisfied)
        XCTAssertFalse(wrongLabel.isSatisfied)
        XCTAssertFalse(
            SpaceFixtureConfiguredContentSnapshot(
                applicationState: "notRunning",
                observations: []
            ).isSatisfied
        )
        XCTAssertTrue(
            wrongLabel.diagnosticSummary.contains(
                "expectedLabel=Docs"
            )
        )
        XCTAssertTrue(
            wrongLabel.diagnosticSummary.contains(
                "observedLabel=Mail"
            )
        )
    }

    func testSpaceFixtureAppLoadsWorkflowConfiguredTabbedWindows() throws {
        let identity = spaceFixtureAppIdentity
        terminateSpaceFixtureAppIfRunning()

        let workflowURL = try makeSpaceFixtureWorkflowFile(
            """
            {
              "workflowName": "tabbed-window-rendering",
              "apps": [
                {
                  "appID": "chrome",
                  "appName": "Chrome Fixture",
                  "bundleId": "com.example.fixture.chrome",
                  "launchOrder": 1,
                  "windows": [
                    {
                      "title": "Chrome Window 1",
                      "mode": "standard",
                      "tabs": [
                        { "title": "Docs", "isSelected": true },
                        { "title": "PR", "isSelected": false }
                      ]
                    },
                    {
                      "title": "Chrome Window 2",
                      "mode": "standard",
                      "tabs": [
                        { "title": "Mail", "isSelected": true },
                        { "title": "Calendar", "isSelected": false }
                      ]
                    }
                  ]
                }
              ]
            }
            """
        )

        let app: XCUIApplication
        if let appURL = identity.appURL {
            app = XCUIApplication(url: appURL)
        } else {
            app = XCUIApplication(bundleIdentifier: identity.bundleIdentifier)
        }
        app.launchArguments += [
            "--workflow-config", workflowURL.path,
            "--workflow-app-id", "chrome",
            "--staggered-layout"
        ]
        let contentExpectations = [
            SpaceFixtureConfiguredContentExpectation(
                identifier:
                    "flowtab.spacefixture.window.title.1",
                label: "Docs"
            ),
            SpaceFixtureConfiguredContentExpectation(
                identifier:
                    "flowtab.spacefixture.window.subtitle.1",
                label: "Chrome Window 1"
            ),
            SpaceFixtureConfiguredContentExpectation(
                identifier:
                    "flowtab.spacefixture.window.tab.1.1",
                label: "Docs"
            ),
            SpaceFixtureConfiguredContentExpectation(
                identifier:
                    "flowtab.spacefixture.window.selected-tab.1",
                label: "Selected Tab: Docs"
            ),
            SpaceFixtureConfiguredContentExpectation(
                identifier:
                    "flowtab.spacefixture.window.tab.1.2",
                label: "PR"
            )
        ]
        let contentElements = contentExpectations.map {
            expectation in
            (
                expectation: expectation,
                element: element(
                    in: app,
                    identifier: expectation.identifier
                )
            )
        }
        let contentObservation =
            SpaceFixtureConfiguredContentObservationOwner {
                let applicationState = app.state
                guard applicationState == .runningForeground
                        || applicationState == .runningBackground
                else {
                    return SpaceFixtureConfiguredContentSnapshot(
                        applicationState:
                            String(describing: applicationState),
                        observations: contentExpectations.map {
                            SpaceFixtureConfiguredContentObservation(
                                expectation: $0,
                                exists: false,
                                observedLabel:
                                    "<application-not-running>"
                            )
                        }
                    )
                }
                return SpaceFixtureConfiguredContentSnapshot(
                    applicationState:
                        String(describing: applicationState),
                    observations: contentElements.map { pair in
                        let exists = pair.element.exists
                        return SpaceFixtureConfiguredContentObservation(
                            expectation: pair.expectation,
                            exists: exists,
                            observedLabel:
                                exists
                                ? pair.element.label
                                : "<missing>"
                        )
                    }
                )
            }
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }
        contentObservation.start()
        defer { contentObservation.cancel() }
        launchSpaceFixtureApplicationAndWaitForForeground(app)

        waitForSpaceFixtureWorkflowReadiness(
            in: app,
            expectedWindowTitles: ["Docs", "Mail"],
            fullscreenWindowIndex: nil,
            readinessTimeout:
                SpaceFixtureWorkflowReadinessUITestPolicy
                    .defaultWatchdog
        )
        guard let contentEvidence =
                contentObservation.waitForResolution(
                    timeout:
                        SpaceFixtureConfiguredContentUITestPolicy
                            .publicationWatchdog
                )
        else {
            XCTFail(
                "Configured fixture content publication watchdog expired. "
                    + contentObservation.diagnosticSummary
            )
            return
        }
        XCTAssertTrue(contentEvidence.value.isSatisfied)
    }
}
