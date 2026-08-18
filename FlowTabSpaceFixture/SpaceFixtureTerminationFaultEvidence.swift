import Darwin
import Foundation

struct SpaceFixtureTerminationFaultEvidenceRoute:
    Equatable
{
    static let notificationArgument =
        "--termination-evidence-notification-name"

    let notificationName: Notification.Name
}

struct SpaceFixtureTerminationFaultIdentity: Equatable {
    let bundleIdentifier: String
    let processIdentifier: pid_t
}

enum SpaceFixtureTerminationFaultRequestSource:
    String,
    Equatable
{
    case applicationShouldTerminate
    case terminationSignal
}

enum SpaceFixtureTerminationFaultEvidencePhase:
    String,
    Equatable
{
    case scheduled
    case applied
}

struct SpaceFixtureTerminationFaultEvidence: Equatable {
    let requestGeneration: Int
    let phase: SpaceFixtureTerminationFaultEvidencePhase
    let source: SpaceFixtureTerminationFaultRequestSource
    let delayMilliseconds: Int
    let identity: SpaceFixtureTerminationFaultIdentity

    var logFields: String {
        "generation=\(requestGeneration) "
            + "phase=\(phase.rawValue) "
            + "source=\(source.rawValue) "
            + "delayMs=\(delayMilliseconds) "
            + "bundleID=\(identity.bundleIdentifier) "
            + "pid=\(identity.processIdentifier)"
    }
}

enum SpaceFixtureTerminationFaultEvidenceTransport {
    private enum UserInfoKey {
        static let requestGeneration = "requestGeneration"
        static let phase = "phase"
        static let source = "source"
        static let delayMilliseconds = "delayMilliseconds"
        static let bundleIdentifier = "bundleIdentifier"
        static let processIdentifier = "processIdentifier"
    }

    static func publish(
        _ evidence: SpaceFixtureTerminationFaultEvidence,
        route: SpaceFixtureTerminationFaultEvidenceRoute?
    ) {
        if let route {
            DistributedNotificationCenter.default()
                .postNotificationName(
                    route.notificationName,
                    object: nil,
                    userInfo: [
                        UserInfoKey.requestGeneration:
                            NSNumber(
                                value:
                                    evidence.requestGeneration
                            ),
                        UserInfoKey.phase:
                            evidence.phase.rawValue,
                        UserInfoKey.source:
                            evidence.source.rawValue,
                        UserInfoKey.delayMilliseconds:
                            NSNumber(
                                value:
                                    evidence.delayMilliseconds
                            ),
                        UserInfoKey.bundleIdentifier:
                            evidence.identity.bundleIdentifier,
                        UserInfoKey.processIdentifier:
                            NSNumber(
                                value:
                                    evidence.identity
                                        .processIdentifier
                            )
                    ],
                    deliverImmediately: true
                )
        }
        NSLog(
            "SpaceFixture termination fault %@",
            evidence.logFields
        )
    }

    static func evidence(
        from notification: Notification
    ) -> SpaceFixtureTerminationFaultEvidence? {
        guard let userInfo = notification.userInfo,
              let requestGeneration = (
                userInfo[
                    UserInfoKey.requestGeneration
                ] as? NSNumber
              )?.intValue,
              requestGeneration > 0,
              let phaseValue =
                userInfo[UserInfoKey.phase] as? String,
              let phase =
                SpaceFixtureTerminationFaultEvidencePhase(
                    rawValue: phaseValue
                ),
              let sourceValue =
                userInfo[UserInfoKey.source] as? String,
              let source =
                SpaceFixtureTerminationFaultRequestSource(
                    rawValue: sourceValue
                ),
              let delayMilliseconds = (
                userInfo[
                    UserInfoKey.delayMilliseconds
                ] as? NSNumber
              )?.intValue,
              delayMilliseconds > 0,
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
              processIdentifier > 0
        else {
            return nil
        }
        return SpaceFixtureTerminationFaultEvidence(
            requestGeneration: requestGeneration,
            phase: phase,
            source: source,
            delayMilliseconds: delayMilliseconds,
            identity: SpaceFixtureTerminationFaultIdentity(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: processIdentifier
            )
        )
    }
}
