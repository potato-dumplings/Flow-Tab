import XCTest
@testable import FlowTab
import FlowTabCore

private enum InitialPresentationTerminalReadbackTestPolicy {
    static let publicationWatchdog: TimeInterval = 5
}

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testUITestInitialPresentationWatchdogPublishesTerminalReadback()
        async throws
    {
        try await withTemporarySearchPreferences(
            enabled: false,
            defaultScope: .app
        ) {
            let previousLaunchArguments =
                FlowTabTestLaunchOptions.argumentsOverrideForTesting
            let previousLaunchEnvironment =
                FlowTabTestLaunchOptions.environmentOverrideForTesting
            let route =
                FlowTabUITestInitialPresentationResolutionRoute(
                    notificationName: Notification.Name(
                        "test.initial-presentation.\(UUID().uuidString)"
                    ),
                    readbackURL:
                        FileManager.default.temporaryDirectory
                            .appendingPathComponent(
                                "flowtab-initial-presentation-\(UUID().uuidString).json",
                                isDirectory: false
                            )
                )
            try? FileManager.default.removeItem(
                at: route.readbackURL
            )
            FlowTabTestLaunchOptions.argumentsOverrideForTesting = [
                "--flowtab-ui-open-switcher-search",
                FlowTabTestLaunchOptions
                    .initialPresentationResolutionNotificationArgument,
                route.notificationName.rawValue,
                FlowTabTestLaunchOptions
                    .initialPresentationResolutionReadbackPathArgument,
                route.readbackURL.path
            ]
            FlowTabTestLaunchOptions.environmentOverrideForTesting = [
                FlowTabTestLaunchOptions.uiTestingEnvironmentKey:
                    FlowTabTestLaunchOptions.uiTestingEnvironmentValue
            ]

            guard let app = searchScenarioApps().first else {
                return XCTFail("Expected launch fixture app")
            }
            let runtimeProjectionService =
                RecordingRuntimeProjectionService(
                    appSwitcherProjection:
                        incompleteInitialPresentationProjection(
                            app: app
                        )
                )
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService:
                        runtimeProjectionService
                )
            )
            let terminalReadbackPublished = expectation(
                description:
                    "unmetCondition=initialPresentationWatchdogPublishedTerminalReadback"
            )
            terminalReadbackPublished.assertForOverFulfill = true
            let center = DistributedNotificationCenter.default()
            let observer = center.addObserver(
                forName: route.notificationName,
                object: nil,
                queue: .main
            ) { _ in
                terminalReadbackPublished.fulfill()
            }
            defer {
                center.removeObserver(observer)
                FlowTabUITestBootstrapper
                    .stopInitialUIPresentationObservation()
                controller.cancelSelectionForTesting()
                FlowTabTestLaunchOptions.argumentsOverrideForTesting =
                    previousLaunchArguments
                FlowTabTestLaunchOptions.environmentOverrideForTesting =
                    previousLaunchEnvironment
                try? FileManager.default.removeItem(
                    at: route.readbackURL
                )
            }

            FlowTabUITestBootstrapper.presentInitialUIIfNeeded(
                panelController: controller
            )

            await fulfillment(
                of: [terminalReadbackPublished],
                timeout:
                    InitialPresentationTerminalReadbackTestPolicy
                        .publicationWatchdog
            )

            guard FileManager.default.fileExists(
                atPath: route.readbackURL.path
            ) else {
                return XCTFail(
                    "Initial presentation watchdog did not write "
                        + "terminal readback"
                )
            }
            let object = try XCTUnwrap(
                try JSONSerialization.jsonObject(
                    with: Data(contentsOf: route.readbackURL)
                ) as? [String: Any]
            )
            XCTAssertEqual(object["schemaVersion"] as? Int, 1)
            XCTAssertEqual(
                object["outcome"] as? String,
                "initialPresentationWatchdogFailure"
            )
            XCTAssertNil(object["resolution"])
            let failure = try XCTUnwrap(
                object["watchdogFailure"] as? [String: Any]
            )
            XCTAssertEqual(
                failure["watchdogInterval"] as? Double,
                3
            )
            XCTAssertEqual(
                failure["unmetConditions"] as? [String],
                ["projectionComplete"]
            )
            XCTAssertTrue(
                try XCTUnwrap(
                    failure["lastEvidence"] as? String
                ).contains("projectionComplete=false")
            )
            XCTAssertTrue(
                try XCTUnwrap(
                    failure["finalEvidence"] as? String
                ).contains("source=watchdogReadback")
            )
        }
    }
}
