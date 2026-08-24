import Darwin
import Foundation

struct SpaceFixtureWindowOpenMutationRoute: Equatable {
    static let evidenceNotificationArgument =
        "--window-open-evidence-notification-name"
    static let triggerNotificationArgument =
        "--window-open-trigger-notification-name"

    let evidenceNotificationName: Notification.Name
    let triggerNotificationName: Notification.Name
}

struct SpaceFixtureWindowOpenMutationTrigger: Equatable {
    let requestGeneration: Int
    let identity: SpaceFixtureApplicationIdentity
    let targetWindowPlanIndex: Int
}

enum SpaceFixtureWindowOpenMutationPhase: String, Equatable {
    case ready
    case applied
}

struct SpaceFixtureWindowOpenMutationSnapshot: Equatable {
    let targetWindowPlanIndex: Int
    let targetWindowTitle: String
    let activeWindowPlanIndices: [Int]

    var logFields: String {
        "targetPlanIndex=\(targetWindowPlanIndex) "
            + "targetTitle=\(targetWindowTitle) "
            + "activePlanIndices=["
            + activeWindowPlanIndices.map(String.init).joined(separator: ",")
            + "]"
    }
}

struct SpaceFixtureWindowOpenMutationEvidence: Equatable {
    let requestGeneration: Int
    let phase: SpaceFixtureWindowOpenMutationPhase
    let identity: SpaceFixtureApplicationIdentity
    let snapshot: SpaceFixtureWindowOpenMutationSnapshot

    var logFields: String {
        "generation=\(requestGeneration) "
            + "phase=\(phase.rawValue) "
            + "bundleID=\(identity.bundleIdentifier) "
            + "pid=\(identity.processIdentifier) "
            + snapshot.logFields
    }
}

enum SpaceFixtureWindowOpenMutationTransport {
    private enum UserInfoKey {
        static let requestGeneration = "requestGeneration"
        static let phase = "phase"
        static let bundleIdentifier = "bundleIdentifier"
        static let processIdentifier = "processIdentifier"
        static let targetWindowPlanIndex = "targetWindowPlanIndex"
        static let targetWindowTitle = "targetWindowTitle"
        static let activeWindowPlanIndices = "activeWindowPlanIndices"
    }

    static func publish(
        _ evidence: SpaceFixtureWindowOpenMutationEvidence,
        route: SpaceFixtureWindowOpenMutationRoute
    ) {
        DistributedNotificationCenter.default().postNotificationName(
            route.evidenceNotificationName,
            object: nil,
            userInfo: userInfo(for: evidence),
            deliverImmediately: true
        )
        NSLog(
            "SpaceFixture window open mutation %@",
            evidence.logFields
        )
    }

    static func publish(
        _ trigger: SpaceFixtureWindowOpenMutationTrigger,
        route: SpaceFixtureWindowOpenMutationRoute
    ) {
        DistributedNotificationCenter.default().postNotificationName(
            route.triggerNotificationName,
            object: nil,
            userInfo: [
                UserInfoKey.requestGeneration:
                    NSNumber(value: trigger.requestGeneration),
                UserInfoKey.bundleIdentifier:
                    trigger.identity.bundleIdentifier,
                UserInfoKey.processIdentifier:
                    NSNumber(value: trigger.identity.processIdentifier),
                UserInfoKey.targetWindowPlanIndex:
                    NSNumber(value: trigger.targetWindowPlanIndex)
            ],
            deliverImmediately: true
        )
    }

    static func evidence(
        from notification: Notification
    ) -> SpaceFixtureWindowOpenMutationEvidence? {
        guard let userInfo = notification.userInfo,
              let requestGeneration = positiveInt(
                userInfo[UserInfoKey.requestGeneration]
              ),
              let phaseValue = userInfo[UserInfoKey.phase] as? String,
              let phase = SpaceFixtureWindowOpenMutationPhase(
                rawValue: phaseValue
              ),
              let identity = identity(from: userInfo),
              let targetWindowPlanIndex = positiveInt(
                userInfo[UserInfoKey.targetWindowPlanIndex]
              ),
              let targetWindowTitle =
                userInfo[UserInfoKey.targetWindowTitle] as? String,
              !targetWindowTitle.isEmpty,
              let activeWindowPlanIndices = normalizedPlanIndices(
                userInfo[UserInfoKey.activeWindowPlanIndices]
              )
        else {
            return nil
        }
        return SpaceFixtureWindowOpenMutationEvidence(
            requestGeneration: requestGeneration,
            phase: phase,
            identity: identity,
            snapshot: SpaceFixtureWindowOpenMutationSnapshot(
                targetWindowPlanIndex: targetWindowPlanIndex,
                targetWindowTitle: targetWindowTitle,
                activeWindowPlanIndices: activeWindowPlanIndices
            )
        )
    }

    static func trigger(
        from notification: Notification
    ) -> SpaceFixtureWindowOpenMutationTrigger? {
        guard let userInfo = notification.userInfo,
              let requestGeneration = positiveInt(
                userInfo[UserInfoKey.requestGeneration]
              ),
              let identity = identity(from: userInfo),
              let targetWindowPlanIndex = positiveInt(
                userInfo[UserInfoKey.targetWindowPlanIndex]
              )
        else {
            return nil
        }
        return SpaceFixtureWindowOpenMutationTrigger(
            requestGeneration: requestGeneration,
            identity: identity,
            targetWindowPlanIndex: targetWindowPlanIndex
        )
    }

    private static func userInfo(
        for evidence: SpaceFixtureWindowOpenMutationEvidence
    ) -> [String: Any] {
        [
            UserInfoKey.requestGeneration:
                NSNumber(value: evidence.requestGeneration),
            UserInfoKey.phase: evidence.phase.rawValue,
            UserInfoKey.bundleIdentifier:
                evidence.identity.bundleIdentifier,
            UserInfoKey.processIdentifier:
                NSNumber(value: evidence.identity.processIdentifier),
            UserInfoKey.targetWindowPlanIndex:
                NSNumber(value: evidence.snapshot.targetWindowPlanIndex),
            UserInfoKey.targetWindowTitle:
                evidence.snapshot.targetWindowTitle,
            UserInfoKey.activeWindowPlanIndices:
                evidence.snapshot.activeWindowPlanIndices.map(NSNumber.init)
        ]
    }

    private static func identity(
        from userInfo: [AnyHashable: Any]
    ) -> SpaceFixtureApplicationIdentity? {
        guard let bundleIdentifier =
                userInfo[UserInfoKey.bundleIdentifier] as? String,
              !bundleIdentifier.isEmpty,
              let processIdentifier = (
                userInfo[UserInfoKey.processIdentifier] as? NSNumber
              )?.int32Value,
              processIdentifier > 0
        else {
            return nil
        }
        return SpaceFixtureApplicationIdentity(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier
        )
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let value = (value as? NSNumber)?.intValue,
              value > 0
        else {
            return nil
        }
        return value
    }

    private static func normalizedPlanIndices(
        _ value: Any?
    ) -> [Int]? {
        guard let numbers = value as? [NSNumber] else {
            return nil
        }
        let indices = numbers.map(\.intValue)
        guard indices.allSatisfy({ $0 > 0 }),
              indices == Array(Set(indices)).sorted()
        else {
            return nil
        }
        return indices
    }
}

@MainActor
final class SpaceFixtureWindowOpenMutationTriggerObservation:
    SpaceFixtureCancellable
{
    private let center: DistributedNotificationCenter
    private var token: NSObjectProtocol?

    init(
        route: SpaceFixtureWindowOpenMutationRoute,
        center: DistributedNotificationCenter = .default(),
        onTrigger:
            @escaping @MainActor (
                SpaceFixtureWindowOpenMutationTrigger
            ) -> Void
    ) {
        self.center = center
        token = center.addObserver(
            forName: route.triggerNotificationName,
            object: nil,
            queue: .main
        ) { notification in
            guard let trigger =
                    SpaceFixtureWindowOpenMutationTransport
                        .trigger(from: notification)
            else {
                return
            }
            Task { @MainActor in
                onTrigger(trigger)
            }
        }
    }

    func cancel() {
        guard let token else { return }
        center.removeObserver(token)
        self.token = nil
    }

    deinit {
        if let token {
            center.removeObserver(token)
        }
    }
}
