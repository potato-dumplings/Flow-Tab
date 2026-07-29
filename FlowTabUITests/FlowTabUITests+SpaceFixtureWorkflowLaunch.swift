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
            waitForSpaceFixtureWorkflowToStabilize(
                in: app,
                expectedWindowTitles:
                    workflowApp.expectedWindowTitles,
                fullscreenWindowIndex:
                    waitsForFullscreenMarkers
                    ? workflowApp.fullscreenWindowIndex
                    : nil,
                settleTimeout: 0
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

        let settleDeadline =
            Date().addingTimeInterval(workflow.settleTimeout)
        var settleTick = 0
        while Date() < settleDeadline {
            let nextTick = Date().addingTimeInterval(
                min(
                    1,
                    settleDeadline.timeIntervalSinceNow
                )
            )
            RunLoop.current.run(until: nextTick)
            settleTick += 1
            logFullscreenWorkflowSpaceObservations(
                "workflow.settle.\(settleTick)s",
                workflow: workflow
            )
        }
        logFullscreenWorkflowSpaceObservations(
            "workflow.afterSettle",
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
