#if FLOWTAB_TESTING
import Foundation

struct FlowTabUITestHomeInitialProjectionApplicationRoute:
    Equatable
{
    let notificationName: Notification.Name
    let readbackURL: URL
}

struct FlowTabUITestHomeInitialProjectionApplicationEvidence:
    Codable,
    Equatable
{
    struct AppSummary: Codable, Equatable {
        let appID: String
        let windowCount: Int
    }

    let observationGeneration: UInt64
    let readbackCount: Int
    let source: String
    let transition: String
    let requestReason: String
    let appCount: Int
    let appSummaries: [AppSummary]
    let isCompleteForScope: Bool
    let appLifecycleGeneration: UInt64
    let cgGeneration: UInt64
    let spaceGeneration: UInt64
    let axDirtyGeneration: UInt64
    let projectionGeneration: UInt64

    init?(
        application:
            HomeInitialProjectionObservationApplication
    ) {
        guard
            let freshness =
                application.evidence.projectionRead.freshness
        else {
            return nil
        }
        observationGeneration =
            application.evidence.observationGeneration
        readbackCount = application.evidence.readbackCount
        source = application.evidence.source.rawValue
        transition =
            application.evidence.transition.rawValue
        requestReason = application.requestReason
        appSummaries =
            application.evidence.projectionRead.summaries.map {
                AppSummary(
                    appID: $0.appID,
                    windowCount: $0.windowCount
                )
            }
        appCount = appSummaries.count
        isCompleteForScope = freshness.isCompleteForScope
        appLifecycleGeneration =
            freshness.sourceGeneration.appLifecycle
        cgGeneration = freshness.sourceGeneration.cg
        spaceGeneration = freshness.sourceGeneration.space
        axDirtyGeneration =
            freshness.sourceGeneration.axDirty
        projectionGeneration =
            freshness.sourceGeneration.projection
    }
}

@MainActor
final class
    FlowTabUITestHomeInitialProjectionApplicationForwarder
{
    typealias Publisher =
        @MainActor (
            FlowTabUITestHomeInitialProjectionApplicationEvidence
        ) -> Void

    let route:
        FlowTabUITestHomeInitialProjectionApplicationRoute

    private let notificationCenter: NotificationCenter
    private let notificationObject: AnyObject
    private let publisher: Publisher
    private var token: NSObjectProtocol?

    init(
        route:
            FlowTabUITestHomeInitialProjectionApplicationRoute,
        notificationObject: AnyObject,
        notificationCenter: NotificationCenter = .default,
        publisher: @escaping Publisher
    ) {
        self.route = route
        self.notificationObject = notificationObject
        self.notificationCenter = notificationCenter
        self.publisher = publisher
    }

    var isObserving: Bool {
        token != nil
    }

    func observes(
        notificationObject: AnyObject
    ) -> Bool {
        self.notificationObject === notificationObject
    }

    func start() {
        cancel()
        token = notificationCenter.addObserver(
            forName:
                .homeInitialProjectionObservationDidApply,
            object: notificationObject,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.observe(notification)
            }
        }
    }

    func cancel() {
        guard let token else { return }
        notificationCenter.removeObserver(token)
        self.token = nil
    }

    deinit {
        if let token {
            notificationCenter.removeObserver(token)
        }
    }

    private func observe(
        _ notification: Notification
    ) {
        guard
            let application =
                HomeInitialProjectionObservationApplication(
                    notification: notification
                ),
            let evidence =
                FlowTabUITestHomeInitialProjectionApplicationEvidence(
                    application: application
                )
        else {
            return
        }
        publisher(evidence)
    }
}

enum FlowTabUITestHomeInitialProjectionApplicationTransport {
    enum UserInfoKey {
        static let observationGeneration =
            "observationGeneration"
        static let readbackCount = "readbackCount"
        static let source = "source"
        static let transition = "transition"
        static let requestReason = "requestReason"
        static let appCount = "appCount"
        static let appIDs = "appIDs"
        static let windowCounts = "windowCounts"
        static let isCompleteForScope =
            "isCompleteForScope"
        static let appLifecycleGeneration =
            "appLifecycleGeneration"
        static let cgGeneration = "cgGeneration"
        static let spaceGeneration = "spaceGeneration"
        static let axDirtyGeneration =
            "axDirtyGeneration"
        static let projectionGeneration =
            "projectionGeneration"
    }

    static func post(
        _ evidence:
            FlowTabUITestHomeInitialProjectionApplicationEvidence,
        route:
            FlowTabUITestHomeInitialProjectionApplicationRoute,
        center:
            DistributedNotificationCenter = .default()
    ) {
        do {
            try writeReadback(
                evidence,
                to: route.readbackURL
            )
        } catch {
            RuntimeLog.error(
                "UITest",
                "home initial projection application "
                    + "readback write failed error=\(error)"
            )
            return
        }
        center.postNotificationName(
            route.notificationName,
            object: nil,
            userInfo: [
                UserInfoKey.observationGeneration:
                    NSNumber(
                        value:
                            evidence.observationGeneration
                    ),
                UserInfoKey.readbackCount:
                    NSNumber(value: evidence.readbackCount),
                UserInfoKey.source: evidence.source,
                UserInfoKey.transition: evidence.transition,
                UserInfoKey.requestReason:
                    evidence.requestReason,
                UserInfoKey.appCount:
                    NSNumber(value: evidence.appCount),
                UserInfoKey.appIDs:
                    evidence.appSummaries.map(\.appID),
                UserInfoKey.windowCounts:
                    evidence.appSummaries.map {
                        NSNumber(value: $0.windowCount)
                    },
                UserInfoKey.isCompleteForScope:
                    NSNumber(
                        value: evidence.isCompleteForScope
                    ),
                UserInfoKey.appLifecycleGeneration:
                    NSNumber(
                        value:
                            evidence.appLifecycleGeneration
                    ),
                UserInfoKey.cgGeneration:
                    NSNumber(
                        value: evidence.cgGeneration
                    ),
                UserInfoKey.spaceGeneration:
                    NSNumber(
                        value: evidence.spaceGeneration
                    ),
                UserInfoKey.axDirtyGeneration:
                    NSNumber(
                        value: evidence.axDirtyGeneration
                    ),
                UserInfoKey.projectionGeneration:
                    NSNumber(
                        value: evidence.projectionGeneration
                    )
            ],
            deliverImmediately: true
        )
    }

    static func writeReadback(
        _ evidence:
            FlowTabUITestHomeInitialProjectionApplicationEvidence,
        to readbackURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(evidence)
        try data.write(
            to: readbackURL,
            options: .atomic
        )
    }
}

@MainActor
enum FlowTabUITestHomeInitialProjectionApplicationBootstrap {
    private static var owner:
        FlowTabUITestHomeInitialProjectionApplicationForwarder?

    static func prepareIfNeeded(
        service: any RuntimeProjectionServing
    ) {
        guard let route =
                FlowTabTestLaunchOptions
                    .homeInitialProjectionApplicationRoute
        else {
            stop()
            return
        }

        let notificationObject = service as AnyObject
        if owner?.route == route,
           owner?.observes(
            notificationObject: notificationObject
           ) == true
        {
            return
        }

        owner?.cancel()
        let nextOwner =
            FlowTabUITestHomeInitialProjectionApplicationForwarder(
                route: route,
                notificationObject: notificationObject
            ) {
                FlowTabUITestHomeInitialProjectionApplicationTransport
                    .post(
                        $0,
                        route: route
                    )
            }
        owner = nextOwner
        nextOwner.start()
    }

    static func stop() {
        owner?.cancel()
        owner = nil
    }
}
#endif
