import Foundation
import XCTest

extension FlowTabUITests {
    func launchResolvedSpaceFixtureWorkflow(
        _ workflow: SpaceFixtureResolvedWorkflow,
        waitsForFullscreenMarkers: Bool,
        suppressesAppAccessibilityChildren: Bool,
        preservesDesktopAfterFullscreen: Bool,
        applicationAXSuppressionRoutes:
            [SpaceFixtureAXSuppressionUITestRoute],
        workflowAppLaunchArguments:
            (SpaceFixtureResolvedWorkflow.App) -> [String] = {
                _ in []
            }
    ) -> [XCUIApplication] {
        var launchedApps: [XCUIApplication] = []
        let readinessOwner =
            makeSpaceFixtureWorkflowReadinessAggregateOwner(
                for: workflow
            )
        readinessOwner.start()
        defer { readinessOwner.cancel() }

        for workflowApp in workflow.apps {
            let app =
                makeSpaceFixtureWorkflowApplication(
                    for: workflowApp.identity
                )
            app.launchArguments += [
                "--workflow-config",
                workflow.workflowURL.path,
                "--workflow-app-id",
                workflowApp.appID,
                "--staggered-layout",
                "--enter-fullscreen-delay-ms",
                String(
                    SpaceFixtureMultiAppWorkflowDefaults
                        .enterFullscreenDelayMilliseconds
                )
            ]
            if preservesDesktopAfterFullscreen {
                app.launchArguments += [
                    "--preserve-desktop-after-fullscreen"
                ]
            }
            if suppressesAppAccessibilityChildren {
                app.launchArguments += [
                    "--suppress-app-accessibility-children"
                ]
                if let route =
                    applicationAXSuppressionRoutes.first(
                        where: {
                            $0.workflowAppID
                                == workflowApp.appID
                        }
                    )
                {
                    app.launchArguments +=
                        route.fixtureLaunchArguments
                }
            }
            app.launchArguments +=
                workflowAppLaunchArguments(workflowApp)
            app.launchArguments +=
                readinessOwner.fixtureLaunchArguments(
                    for: workflowApp.appID
                )
            if workflowApp.fullscreenWindowIndex != nil {
                logWorkflowSpaceObservation(
                    "workflow.beforeLaunch."
                        + workflowApp.appID,
                    app: workflowApp
                )
            }
            launchSpaceFixtureApplicationAndWaitForForeground(
                app
            )
            if workflowApp.fullscreenWindowIndex != nil {
                logWorkflowSpaceObservation(
                    "workflow.afterForeground."
                        + workflowApp.appID,
                    app: workflowApp
                )
            }
            waitForSpaceFixtureWorkflowMetadata(
                in: app,
                expectedWindowTitles:
                    workflowApp.expectedWindowTitles,
                fullscreenWindowIndex:
                    waitsForFullscreenMarkers
                    ? workflowApp.fullscreenWindowIndex
                    : nil
            )
            if workflowApp.fullscreenWindowIndex != nil {
                logWorkflowSpaceObservation(
                    "workflow.afterStabilize."
                        + workflowApp.appID,
                    app: workflowApp
                )
            }
            launchedApps.append(app)
        }

        guard let readinessSnapshot =
                readinessOwner.waitForReady(
                    timeout: workflow.readinessWatchdog
                )
        else {
            XCTFail(
                "Fixture workflow readiness watchdog expired: "
                    + readinessOwner.diagnosticSummary
            )
            return launchedApps
        }
        assertSpaceFixtureWorkflowReadinessAggregate(
            readinessSnapshot,
            workflow: workflow,
            launchedApps: launchedApps
        )
        logFullscreenWorkflowSpaceObservations(
            "workflow.afterReadiness",
            workflow: workflow
        )
        if preservesDesktopAfterFullscreen,
           let desktopAnchorIndex =
            workflow.apps.firstIndex(
                where: {
                    $0.fullscreenWindowIndex == nil
                }
            )
        {
            let desktopAnchorApp =
                launchedApps[desktopAnchorIndex]
            logFullscreenWorkflowSpaceObservations(
                "workflow.beforeDesktopAnchorActivate",
                workflow: workflow
            )
            desktopAnchorApp.activate()
            _ = desktopAnchorApp.wait(
                for: .runningForeground,
                timeout: 5
            )
            logFullscreenWorkflowSpaceObservations(
                "workflow.afterDesktopAnchorActivate",
                workflow: workflow
            )
        }
        return launchedApps
    }
}
