import AppKit
import Foundation
import XCTest
struct SpaceFixtureAXSuppressionUITestRoute:
    Equatable
{
    let workflowAppID: String
    let bundleIdentifier: String
    let expectedWindowCount: Int
    let projectionAcknowledgementNotificationName:
        Notification.Name
    let suppressionCompletionNotificationName:
        Notification.Name

    var flowTabLaunchArguments: [String] {
        [
            "--flowtab-ui-projection-acknowledgement-route",
            projectionAcknowledgementNotificationName.rawValue,
            bundleIdentifier,
            String(expectedWindowCount)
        ]
    }

    var fixtureLaunchArguments: [String] {
        [
            "--projection-acknowledgement-notification-name",
            projectionAcknowledgementNotificationName.rawValue,
            "--accessibility-suppression-notification-name",
            suppressionCompletionNotificationName.rawValue
        ]
    }
}
private struct SpaceFixtureAXSuppressionCompletion:
    Equatable
{
    let suppressionGeneration: UInt64
    let acknowledgementGeneration: UInt64
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let windowCount: Int
    let sourceGeneration: String
    let childWindowCount: Int
    let windowsAttributeCount: Int
}
private struct SpaceFixtureApplicationXCUIWindowEvidence {
    let windowCount: Int

    var isSuppressed: Bool {
        windowCount == 0
    }

    var diagnosticSummary: String {
        "windows=\(windowCount)"
    }
}
final class SpaceFixtureAXSuppressionObservationOwner {
    private enum UserInfoKey {
        static let suppressionGeneration =
            "suppressionGeneration"
        static let acknowledgementGeneration =
            "acknowledgementGeneration"
        static let bundleIdentifier = "bundleIdentifier"
        static let processIdentifier = "processIdentifier"
        static let windowCount = "windowCount"
        static let sourceGeneration = "sourceGeneration"
        static let childWindowCount = "childWindowCount"
        static let windowsAttributeCount =
            "windowsAttributeCount"
    }
    private static let applicationAXReadbackInterval:
        TimeInterval = 0.1

    private let routes:
        [SpaceFixtureAXSuppressionUITestRoute]
    private let center:
        DistributedNotificationCenter
    private var observationTokens: [NSObjectProtocol] = []
    private var latestCompletionByNotificationName:
        [String: SpaceFixtureAXSuppressionCompletion] = [:]

    init(
        routes: [SpaceFixtureAXSuppressionUITestRoute],
        center: DistributedNotificationCenter = .default()
    ) {
        self.routes = routes
        self.center = center
    }
    func start() {
        cancel()
        latestCompletionByNotificationName.removeAll()
        for route in routes {
            let notificationName =
                route.suppressionCompletionNotificationName
            let token = center.addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.observe(
                    notification,
                    for: route
                )
            }
            observationTokens.append(token)
        }
    }

    func cancel() {
        for token in observationTokens {
            center.removeObserver(token)
        }
        observationTokens.removeAll()
    }

    deinit {
        for token in observationTokens {
            center.removeObserver(token)
        }
    }

    func waitForSuppression(
        route: SpaceFixtureAXSuppressionUITestRoute,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var latestExternalEvidence:
            SpaceFixtureApplicationXCUIWindowEvidence?
        repeat {
            if let completion = matchingCompletion(
                for: route
            ) {
                latestExternalEvidence =
                    applicationXCUIWindowEvidence(
                        bundleIdentifier:
                            route.bundleIdentifier
                    )
                if latestExternalEvidence?
                    .isSuppressed == true,
                   isExactRunningApplication(
                    bundleIdentifier:
                        route.bundleIdentifier,
                    processIdentifier:
                        completion.processIdentifier
                )
                {
                    return true
                }
            }
            let nextReadback = min(
                deadline,
                Date().addingTimeInterval(
                    Self.applicationAXReadbackInterval
                )
            )
            RunLoop.current.run(until: nextReadback)
        } while Date() < deadline

        let completion = latestCompletionByNotificationName[
            route.suppressionCompletionNotificationName.rawValue
        ]
        XCTFail(
            "Application AX suppression evidence timed out "
                + "bundleID=\(route.bundleIdentifier) "
                + "expectedWindows=\(route.expectedWindowCount) "
                + "completion=\(completionDiagnostic(completion)) "
                + "externalXCUI={"
                + (latestExternalEvidence?.diagnosticSummary
                    ?? "unobserved")
                + "}."
        )
        return false
    }

    private func observe(
        _ notification: Notification,
        for route: SpaceFixtureAXSuppressionUITestRoute
    ) {
        guard let completion = parse(notification),
              completion.bundleIdentifier
                == route.bundleIdentifier,
              completion.windowCount
                == route.expectedWindowCount,
              completion.childWindowCount == 0,
              completion.windowsAttributeCount == 0
        else {
            return
        }
        let key =
            route.suppressionCompletionNotificationName.rawValue
        guard completion.suppressionGeneration
                > (
                    latestCompletionByNotificationName[key]?
                        .suppressionGeneration ?? 0
                )
        else {
            return
        }
        latestCompletionByNotificationName[key] = completion
    }

    private func matchingCompletion(
        for route: SpaceFixtureAXSuppressionUITestRoute
    ) -> SpaceFixtureAXSuppressionCompletion? {
        latestCompletionByNotificationName[
            route.suppressionCompletionNotificationName.rawValue
        ]
    }

    private func parse(
        _ notification: Notification
    ) -> SpaceFixtureAXSuppressionCompletion? {
        guard let userInfo = notification.userInfo,
              let suppressionGeneration = (
                userInfo[
                    UserInfoKey.suppressionGeneration
                ] as? NSNumber
              )?.uint64Value,
              suppressionGeneration > 0,
              let acknowledgementGeneration = (
                userInfo[
                    UserInfoKey.acknowledgementGeneration
                ] as? NSNumber
              )?.uint64Value,
              acknowledgementGeneration > 0,
              let bundleIdentifier =
                userInfo[
                    UserInfoKey.bundleIdentifier
                ] as? String,
              !bundleIdentifier.isEmpty,
              let processIdentifier = (
                userInfo[
                    UserInfoKey.processIdentifier
                ] as? NSNumber
              )?.int32Value,
              processIdentifier > 0,
              let windowCount = (
                userInfo[
                    UserInfoKey.windowCount
                ] as? NSNumber
              )?.intValue,
              windowCount > 0,
              let sourceGeneration =
                userInfo[
                    UserInfoKey.sourceGeneration
                ] as? String,
              !sourceGeneration.isEmpty,
              let childWindowCount = (
                userInfo[
                    UserInfoKey.childWindowCount
                ] as? NSNumber
              )?.intValue,
              let windowsAttributeCount = (
                userInfo[
                    UserInfoKey.windowsAttributeCount
                ] as? NSNumber
              )?.intValue
        else {
            return nil
        }
        return SpaceFixtureAXSuppressionCompletion(
            suppressionGeneration: suppressionGeneration,
            acknowledgementGeneration:
                acknowledgementGeneration,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            windowCount: windowCount,
            sourceGeneration: sourceGeneration,
            childWindowCount: childWindowCount,
            windowsAttributeCount: windowsAttributeCount
        )
    }

    private func isExactRunningApplication(
        bundleIdentifier: String,
        processIdentifier: pid_t
    ) -> Bool {
        NSRunningApplication
            .runningApplications(
                withBundleIdentifier: bundleIdentifier
            )
            .contains {
                !$0.isTerminated
                    && $0.processIdentifier
                        == processIdentifier
            }
    }

    private func applicationXCUIWindowEvidence(
        bundleIdentifier: String
    ) -> SpaceFixtureApplicationXCUIWindowEvidence {
        let application = XCUIApplication(
            bundleIdentifier: bundleIdentifier
        )
        return SpaceFixtureApplicationXCUIWindowEvidence(
            windowCount: application.windows.count
        )
    }

    private func completionDiagnostic(
        _ completion:
            SpaceFixtureAXSuppressionCompletion?
    ) -> String {
        guard let completion else { return "unobserved" }
        return "generation="
            + "\(completion.suppressionGeneration) "
            + "ackGeneration="
            + "\(completion.acknowledgementGeneration) "
            + "pid=\(completion.processIdentifier) "
            + "windows=\(completion.windowCount) "
            + "sourceGeneration="
            + completion.sourceGeneration
    }
}

extension FlowTabUITests {
    func makeSpaceFixtureAXSuppressionRoutes(
        for workflow: SpaceFixtureResolvedWorkflow
    ) -> [SpaceFixtureAXSuppressionUITestRoute] {
        let routeRoot =
            "io.github.potato-dumplings.flowtab.ui-test."
            + "ax-suppression.\(UUID().uuidString)"
        return workflow.apps.enumerated().map { index, app in
            SpaceFixtureAXSuppressionUITestRoute(
                workflowAppID: app.appID,
                bundleIdentifier:
                    app.identity.bundleIdentifier,
                expectedWindowCount: app.windowCount,
                projectionAcknowledgementNotificationName:
                    Notification.Name(
                        "\(routeRoot).\(index).projection"
                    ),
                suppressionCompletionNotificationName:
                    Notification.Name(
                        "\(routeRoot).\(index).suppressed"
                    )
            )
        }
    }
}
