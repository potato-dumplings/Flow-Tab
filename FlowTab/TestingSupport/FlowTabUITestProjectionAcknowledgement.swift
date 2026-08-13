#if FLOWTAB_TESTING
import AppKit
import Foundation

struct FlowTabUITestProjectionAcknowledgementRoute: Equatable {
    let notificationName: Notification.Name
    let bundleIdentifier: String
    let expectedWindowCount: Int
}

struct FlowTabUITestProjectionAcknowledgementSnapshot: Equatable {
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let windowCount: Int
    let sourceGeneration: String
    let isComplete: Bool
}

enum FlowTabUITestProjectionAcknowledgementSource:
    String,
    Equatable
{
    case initialReadback
    case runtimeCurrentAppProjectionDidUpdate
}

struct FlowTabUITestProjectionAcknowledgementEvidence:
    Equatable
{
    let observationGeneration: UInt64
    let acknowledgementGeneration: UInt64
    let source:
        FlowTabUITestProjectionAcknowledgementSource
    let route:
        FlowTabUITestProjectionAcknowledgementRoute
    let snapshot:
        FlowTabUITestProjectionAcknowledgementSnapshot
}

enum FlowTabUITestProjectionAcknowledgementUserInfoKey {
    static let acknowledgementGeneration =
        "acknowledgementGeneration"
    static let bundleIdentifier = "bundleIdentifier"
    static let processIdentifier = "processIdentifier"
    static let windowCount = "windowCount"
    static let sourceGeneration = "sourceGeneration"
}

@MainActor
final class FlowTabUITestProjectionAcknowledgementOwner {
    private struct PublishedSignature: Equatable {
        let processIdentifier: pid_t
        let windowCount: Int
        let sourceGeneration: String
    }

    typealias SnapshotProvider =
        @MainActor () ->
            [FlowTabUITestProjectionAcknowledgementSnapshot]
    typealias AcknowledgementPublisher =
        @MainActor (
            FlowTabUITestProjectionAcknowledgementEvidence
        ) -> Void

    let routes: [FlowTabUITestProjectionAcknowledgementRoute]

    private let notificationCenter: NotificationCenter
    private let snapshotProvider: SnapshotProvider
    private let acknowledgementPublisher:
        AcknowledgementPublisher
    private var publishedSignaturesByNotificationName:
        [String: PublishedSignature] = [:]
    private var notificationToken: NSObjectProtocol?
    private var activeObservationGeneration: UInt64?

    private(set) var observationGeneration: UInt64 = 0
    private(set) var acknowledgementGeneration: UInt64 = 0

    init(
        routes: [FlowTabUITestProjectionAcknowledgementRoute],
        notificationCenter: NotificationCenter = .default,
        snapshotProvider: @escaping SnapshotProvider,
        acknowledgementPublisher:
            @escaping AcknowledgementPublisher
    ) {
        self.routes = routes
        self.notificationCenter = notificationCenter
        self.snapshotProvider = snapshotProvider
        self.acknowledgementPublisher =
            acknowledgementPublisher
    }

    var isObserving: Bool {
        notificationToken != nil
    }

    @discardableResult
    func start() -> UInt64 {
        cancel(invalidate: false)
        observationGeneration &+= 1
        let generation = observationGeneration
        activeObservationGeneration = generation
        publishedSignaturesByNotificationName.removeAll()
        guard !routes.isEmpty else {
            activeObservationGeneration = nil
            return generation
        }

        notificationToken = notificationCenter.addObserver(
            forName: .runtimeCurrentAppWindowProjectionDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.observeCurrentAppProjectionDidUpdate(
                    observationGeneration: generation
                )
            }
        }
        resolveEligibleRoutes(
            source: .initialReadback,
            observationGeneration: generation
        )
        return generation
    }

    deinit {
        if let notificationToken {
            notificationCenter.removeObserver(
                notificationToken
            )
        }
    }

    func refreshFromReadback() {
        guard let generation =
                activeObservationGeneration
        else {
            return
        }
        resolveEligibleRoutes(
            source: .initialReadback,
            observationGeneration: generation
        )
    }

    @discardableResult
    func observeCurrentAppProjectionDidUpdate(
        observationGeneration: UInt64
    ) -> Bool {
        guard activeObservationGeneration
                == observationGeneration
        else {
            return false
        }
        resolveEligibleRoutes(
            source: .runtimeCurrentAppProjectionDidUpdate,
            observationGeneration:
                observationGeneration
        )
        return true
    }

    func cancel() {
        cancel(invalidate: true)
    }

    private func resolveEligibleRoutes(
        source:
            FlowTabUITestProjectionAcknowledgementSource,
        observationGeneration: UInt64
    ) {
        guard activeObservationGeneration
                == observationGeneration
        else {
            return
        }
        let snapshots = snapshotProvider()
        var resolved:
            [FlowTabUITestProjectionAcknowledgementEvidence] = []
        for route in routes {
            guard let snapshot = snapshots.first(where: {
                $0.bundleIdentifier
                    == route.bundleIdentifier
                    && $0.processIdentifier > 0
                    && $0.windowCount
                        == route.expectedWindowCount
                    && $0.isComplete
            }) else {
                continue
            }
            let signature = PublishedSignature(
                processIdentifier:
                    snapshot.processIdentifier,
                windowCount: snapshot.windowCount,
                sourceGeneration:
                    snapshot.sourceGeneration
            )
            guard publishedSignaturesByNotificationName[
                route.notificationName.rawValue
            ] != signature else {
                continue
            }
            publishedSignaturesByNotificationName[
                route.notificationName.rawValue
            ] = signature
            acknowledgementGeneration &+= 1
            resolved.append(
                FlowTabUITestProjectionAcknowledgementEvidence(
                    observationGeneration:
                        observationGeneration,
                    acknowledgementGeneration:
                        acknowledgementGeneration,
                    source: source,
                    route: route,
                    snapshot: snapshot
                )
            )
        }
        guard !resolved.isEmpty else { return }

        for evidence in resolved {
            guard self.observationGeneration
                    == observationGeneration
            else {
                return
            }
            acknowledgementPublisher(evidence)
        }
    }

    private func cancel(invalidate: Bool) {
        stopObservation()
        publishedSignaturesByNotificationName.removeAll()
        activeObservationGeneration = nil
        if invalidate {
            observationGeneration &+= 1
        }
    }

    private func stopObservation() {
        guard let notificationToken else { return }
        notificationCenter.removeObserver(
            notificationToken
        )
        self.notificationToken = nil
    }
}

extension FlowTabUITestProjectionAcknowledgementSnapshot {
    static func makeSnapshot(
        projection: RuntimeCurrentAppWindowProjection?
    ) -> Self? {
        guard let projection else { return nil }
        let payload = projection.currentAppWindowPayload
        guard projection.appID == payload.summary.appID,
              projection.appID == payload.candidate.id,
              projection.appID == payload.context.appID,
              payload.summary.pid == payload.context.ownerPID,
              payload.context.runningApp.processIdentifier
                == payload.context.ownerPID,
              payload.summary.windowCount
                == payload.candidate.windows.count,
              let bundleIdentifier =
                payload.context.runningApp.bundleIdentifier,
              projection.appID == bundleIdentifier,
              payload.summary.bundleIdentifier
                == bundleIdentifier
        else {
            return nil
        }
        let freshness = projection.freshness
        let sourceGeneration = [
            "appLifecycle=\(freshness.sourceGeneration.appLifecycle)",
            "cg=\(freshness.sourceGeneration.cg)",
            "space=\(freshness.sourceGeneration.space)",
            "axDirty=\(freshness.sourceGeneration.axDirty)",
            "projection=\(freshness.sourceGeneration.projection)"
        ].joined(separator: ",")
        return Self(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: payload.context.ownerPID,
            windowCount: payload.candidate.windows.count,
            sourceGeneration: sourceGeneration,
            isComplete: freshness.isCompleteForScope
        )
    }
}

enum FlowTabUITestProjectionAcknowledgementTransport {
    static func post(
        _ evidence:
            FlowTabUITestProjectionAcknowledgementEvidence
    ) {
        DistributedNotificationCenter.default()
            .postNotificationName(
                evidence.route.notificationName,
                object: nil,
                userInfo: [
                    FlowTabUITestProjectionAcknowledgementUserInfoKey
                        .acknowledgementGeneration:
                        NSNumber(
                            value:
                                evidence
                                    .acknowledgementGeneration
                        ),
                    FlowTabUITestProjectionAcknowledgementUserInfoKey
                        .bundleIdentifier:
                        evidence.snapshot.bundleIdentifier,
                    FlowTabUITestProjectionAcknowledgementUserInfoKey
                        .processIdentifier:
                        NSNumber(
                            value:
                                evidence.snapshot
                                    .processIdentifier
                        ),
                    FlowTabUITestProjectionAcknowledgementUserInfoKey
                        .windowCount:
                        NSNumber(
                            value:
                                evidence.snapshot.windowCount
                        ),
                    FlowTabUITestProjectionAcknowledgementUserInfoKey
                        .sourceGeneration:
                        evidence.snapshot.sourceGeneration
                ],
                deliverImmediately: true
            )
        RuntimeLog.info(
            "UITest",
            "projection acknowledgement generation=\(evidence.acknowledgementGeneration) "
                + "bundleID=\(evidence.snapshot.bundleIdentifier) "
                + "pid=\(evidence.snapshot.processIdentifier) "
                + "windows=\(evidence.snapshot.windowCount) "
                + "sourceGeneration=\(evidence.snapshot.sourceGeneration)"
        )
    }
}

@MainActor
enum FlowTabUITestProjectionAcknowledgementBootstrap {
    private static var owner:
        FlowTabUITestProjectionAcknowledgementOwner?

    static func prepareIfNeeded(
        service: any RuntimeProjectionServing
    ) {
        let routes =
            FlowTabTestLaunchOptions
                .projectionAcknowledgementRoutes
        guard !routes.isEmpty else {
            stop()
            return
        }
        if owner?.routes == routes {
            owner?.refreshFromReadback()
            return
        }

        owner?.cancel()
        let appIDs = Set(
            routes.map(\.bundleIdentifier)
        ).sorted()
        let nextOwner =
            FlowTabUITestProjectionAcknowledgementOwner(
                routes: routes,
                snapshotProvider: {
                    appIDs.compactMap { appID in
                        FlowTabUITestProjectionAcknowledgementSnapshot
                            .makeSnapshot(
                                projection:
                                    service
                                        .readCurrentAppWindowProjection(
                                            appID: appID
                                        )
                            )
                    }
                },
                acknowledgementPublisher: {
                    FlowTabUITestProjectionAcknowledgementTransport
                        .post($0)
                }
            )
        owner = nextOwner
        nextOwner.start()
    }

    static func stop() {
        owner?.cancel()
        owner = nil
    }
}
#endif
