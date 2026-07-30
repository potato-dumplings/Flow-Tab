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
    let externalReadbackNotificationName:
        Notification.Name

    var flowTabLaunchArguments: [String] {
        [
            "--flowtab-ui-projection-acknowledgement-route",
            projectionAcknowledgementNotificationName.rawValue,
            bundleIdentifier,
            String(expectedWindowCount),
            "--flowtab-ui-ax-suppression-readback-route",
            suppressionCompletionNotificationName.rawValue,
            externalReadbackNotificationName.rawValue,
            bundleIdentifier,
            String(expectedWindowCount),
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
struct SpaceFixtureAXSuppressionCompletion:
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

    var diagnosticSummary: String {
        "generation=\(suppressionGeneration) "
            + "ackGeneration=\(acknowledgementGeneration) "
            + "bundleID=\(bundleIdentifier) "
            + "pid=\(processIdentifier) "
            + "windows=\(windowCount) "
            + "sourceGeneration=\(sourceGeneration) "
            + "childWindows=\(childWindowCount) "
            + "windowsAttribute=\(windowsAttributeCount)"
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
    private let routes:
        [SpaceFixtureAXSuppressionUITestRoute]
    private let center:
        DistributedNotificationCenter
    private var routeOwners:
        [
            String:
                SpaceFixtureAXSuppressionRouteObservationOwner
        ] = [:]

    init(
        routes: [SpaceFixtureAXSuppressionUITestRoute],
        center: DistributedNotificationCenter = .default()
    ) {
        self.routes = routes
        self.center = center
    }

    func start() {
        cancel()
        for route in routes {
            let owner =
                SpaceFixtureAXSuppressionRouteObservationOwner(
                    route: route,
                    completionRegistration:
                        completionRegistration(for: route)
                )
            routeOwners[route.key] = owner
            owner.start()
        }
    }

    func cancel() {
        for owner in routeOwners.values {
            owner.cancel()
        }
        routeOwners.removeAll()
    }

    deinit {
        cancel()
    }

    func waitForSuppression(
        route: SpaceFixtureAXSuppressionUITestRoute,
        timeout: TimeInterval
    ) -> Bool {
        guard let owner = routeOwners[route.key] else {
            XCTFail(
                "Application AX suppression route was not "
                    + "started for \(route.bundleIdentifier)."
            )
            return false
        }
        guard owner.waitForResolution(timeout: timeout)
            != nil
        else {
            XCTFail(
                "Application AX suppression evidence timed "
                    + "out bundleID="
                    + route.bundleIdentifier
                    + " expectedWindows="
                    + "\(route.expectedWindowCount) "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    private func completionRegistration(
        for route: SpaceFixtureAXSuppressionUITestRoute
    ) -> SpaceFixtureAXSuppressionCompletionRegistration {
        { [center] completion in
            let token = center.addObserver(
                forName:
                    route
                        .suppressionCompletionNotificationName,
                object: nil,
                queue: .main
            ) { notification in
                guard let parsedCompletion =
                        Self.parse(notification)
                else {
                    return
                }
                completion(parsedCompletion)
            }
            return FlowTabUITestObservationCancellation {
                center.removeObserver(token)
            }
        }
    }

    private static func parse(
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
}

private extension SpaceFixtureAXSuppressionUITestRoute {
    var key: String {
        suppressionCompletionNotificationName.rawValue
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
                    ),
                externalReadbackNotificationName:
                    Notification.Name(
                        "\(routeRoot).\(index).external-readback"
                    )
            )
        }
    }
}
