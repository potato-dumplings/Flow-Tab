#if FLOWTAB_TESTING
import Foundation

struct FlowTabUITestCurrentAppProjectionEvidenceRoute:
    Equatable
{
    let notificationName: Notification.Name
    let readbackURL: URL
    let bundleIdentifier: String
}

struct FlowTabUITestCurrentAppProjectionSourceGeneration:
    Codable,
    Equatable
{
    let appLifecycle: UInt64
    let cg: UInt64
    let space: UInt64
    let axDirty: UInt64
    let projection: UInt64

    init(_ generation: RuntimeReadModelGeneration) {
        appLifecycle = generation.appLifecycle
        cg = generation.cg
        space = generation.space
        axDirty = generation.axDirty
        projection = generation.projection
    }

    func isStrictlyLater(
        than other:
            FlowTabUITestCurrentAppProjectionSourceGeneration
    ) -> Bool {
        appLifecycle >= other.appLifecycle
            && cg >= other.cg
            && space >= other.space
            && axDirty >= other.axDirty
            && projection >= other.projection
            && self != other
    }
}

struct FlowTabUITestCurrentAppProjectionEvidence:
    Codable,
    Equatable
{
    let evidenceGeneration: UInt64
    let bundleIdentifier: String
    let appID: String
    let processIdentifier: pid_t
    let windowIDs: [String]
    let isCompleteForScope: Bool
    let sourceGeneration:
        FlowTabUITestCurrentAppProjectionSourceGeneration
}

enum FlowTabUITestCurrentAppProjectionEvidenceUserInfoKey {
    static let evidenceGeneration = "evidenceGeneration"
    static let bundleIdentifier = "bundleIdentifier"
    static let appID = "appID"
    static let processIdentifier = "processIdentifier"
    static let windowIDs = "windowIDs"
    static let isCompleteForScope = "isCompleteForScope"
    static let appLifecycleGeneration =
        "appLifecycleGeneration"
    static let cgGeneration = "cgGeneration"
    static let spaceGeneration = "spaceGeneration"
    static let axDirtyGeneration = "axDirtyGeneration"
    static let projectionGeneration = "projectionGeneration"
}

final class FlowTabUITestCurrentAppProjectionEvidencePublisher:
    @unchecked Sendable
{
    typealias Sink = @Sendable (
        FlowTabUITestCurrentAppProjectionEvidence
    ) -> Void

    let route: FlowTabUITestCurrentAppProjectionEvidenceRoute

    private let lock = NSLock()
    private let sink: Sink
    private var nextEvidenceGeneration: UInt64 = 1

    init(
        route: FlowTabUITestCurrentAppProjectionEvidenceRoute,
        sink: Sink? = nil
    ) {
        self.route = route
        self.sink = sink ?? { evidence in
            FlowTabUITestCurrentAppProjectionEvidenceTransport
                .post(evidence, route: route)
        }
    }

    func record(
        _ update:
            RuntimeCurrentAppWindowProjectionUpdateEvidence
    ) {
        guard update.appID == route.bundleIdentifier,
              update.processIdentifier > 0
        else {
            return
        }
        lock.lock()
        let generation = nextEvidenceGeneration
        nextEvidenceGeneration &+= 1
        lock.unlock()
        sink(
            FlowTabUITestCurrentAppProjectionEvidence(
                evidenceGeneration: generation,
                bundleIdentifier: route.bundleIdentifier,
                appID: update.appID,
                processIdentifier:
                    update.processIdentifier,
                windowIDs: update.windowIDs,
                isCompleteForScope:
                    update.isCompleteForScope,
                sourceGeneration:
                    FlowTabUITestCurrentAppProjectionSourceGeneration(
                        update.sourceGeneration
                    )
            )
        )
    }
}

enum FlowTabUITestCurrentAppProjectionEvidenceTransport {
    static func post(
        _ evidence:
            FlowTabUITestCurrentAppProjectionEvidence,
        route:
            FlowTabUITestCurrentAppProjectionEvidenceRoute,
        center:
            DistributedNotificationCenter = .default()
    ) {
        do {
            try writeReadback(evidence, to: route.readbackURL)
        } catch {
            RuntimeLog.error(
                "UITest",
                "current-app projection evidence readback write "
                    + "failed error=\(error)"
            )
            return
        }
        center.postNotificationName(
            route.notificationName,
            object: nil,
            userInfo: userInfo(for: evidence),
            deliverImmediately: true
        )
    }

    static func writeReadback(
        _ evidence:
            FlowTabUITestCurrentAppProjectionEvidence,
        to readbackURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(evidence).write(
            to: readbackURL,
            options: .atomic
        )
    }

    static func userInfo(
        for evidence:
            FlowTabUITestCurrentAppProjectionEvidence
    ) -> [String: Any] {
        [
            FlowTabUITestCurrentAppProjectionEvidenceUserInfoKey
                .evidenceGeneration:
                NSNumber(value: evidence.evidenceGeneration),
            FlowTabUITestCurrentAppProjectionEvidenceUserInfoKey
                .bundleIdentifier:
                evidence.bundleIdentifier,
            FlowTabUITestCurrentAppProjectionEvidenceUserInfoKey
                .appID:
                evidence.appID,
            FlowTabUITestCurrentAppProjectionEvidenceUserInfoKey
                .processIdentifier:
                NSNumber(value: evidence.processIdentifier),
            FlowTabUITestCurrentAppProjectionEvidenceUserInfoKey
                .windowIDs:
                evidence.windowIDs,
            FlowTabUITestCurrentAppProjectionEvidenceUserInfoKey
                .isCompleteForScope:
                NSNumber(value: evidence.isCompleteForScope),
            FlowTabUITestCurrentAppProjectionEvidenceUserInfoKey
                .appLifecycleGeneration:
                NSNumber(
                    value:
                        evidence.sourceGeneration.appLifecycle
                ),
            FlowTabUITestCurrentAppProjectionEvidenceUserInfoKey
                .cgGeneration:
                NSNumber(value: evidence.sourceGeneration.cg),
            FlowTabUITestCurrentAppProjectionEvidenceUserInfoKey
                .spaceGeneration:
                NSNumber(value: evidence.sourceGeneration.space),
            FlowTabUITestCurrentAppProjectionEvidenceUserInfoKey
                .axDirtyGeneration:
                NSNumber(value: evidence.sourceGeneration.axDirty),
            FlowTabUITestCurrentAppProjectionEvidenceUserInfoKey
                .projectionGeneration:
                NSNumber(
                    value:
                        evidence.sourceGeneration.projection
                )
        ]
    }
}
#endif
