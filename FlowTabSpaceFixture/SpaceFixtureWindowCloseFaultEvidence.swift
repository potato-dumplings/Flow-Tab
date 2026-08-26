import CoreGraphics
import Darwin
import Foundation

struct SpaceFixtureWindowCloseFaultEvidenceRoute:
    Equatable
{
    static let notificationArgument =
        "--window-close-evidence-notification-name"

    let notificationName: Notification.Name
}

struct SpaceFixtureWindowCloseFaultTriggerRoute:
    Equatable
{
    static let notificationArgument =
        "--window-close-trigger-notification-name"

    let notificationName: Notification.Name
}

struct SpaceFixtureWindowCloseFaultIdentity:
    Equatable
{
    let bundleIdentifier: String
    let processIdentifier: pid_t
}

struct SpaceFixtureWindowCloseFaultTrigger:
    Equatable
{
    let requestGeneration: Int
    let identity: SpaceFixtureWindowCloseFaultIdentity
    let targetWindowPlanIndex: Int
}

enum SpaceFixtureWindowCloseFaultEvidencePhase:
    String,
    Equatable
{
    case scheduled
    case applied
}

enum SpaceFixtureWindowCloseFaultEvidenceSource:
    String,
    Equatable
{
    case initialReadback
    case closeActionReadback
    case retryReadback
    case watchdogReadback
}

struct SpaceFixtureWindowCloseTopologySnapshot:
    Equatable
{
    let targetWindowPlanIndex: Int
    let targetWindowNumber: CGWindowID
    let targetWindowIsVisible: Bool
    let targetCGWindowIsOnScreen: Bool
    let remainingWindowPlanIndices: [Int]
    let remainingWindowTitlesByPlanIndex: [Int: String]
    let remainingCGWindowIDsByPlanIndex: [Int: CGWindowID]

    init(
        targetWindowPlanIndex: Int,
        targetWindowNumber: CGWindowID,
        targetWindowIsVisible: Bool,
        targetCGWindowIsOnScreen: Bool,
        remainingWindowPlanIndices: [Int],
        remainingWindowTitlesByPlanIndex: [Int: String] = [:],
        remainingCGWindowIDsByPlanIndex: [Int: CGWindowID] = [:]
    ) {
        self.targetWindowPlanIndex = targetWindowPlanIndex
        self.targetWindowNumber = targetWindowNumber
        self.targetWindowIsVisible = targetWindowIsVisible
        self.targetCGWindowIsOnScreen = targetCGWindowIsOnScreen
        self.remainingWindowPlanIndices = remainingWindowPlanIndices
        self.remainingWindowTitlesByPlanIndex =
            remainingWindowTitlesByPlanIndex
        self.remainingCGWindowIDsByPlanIndex =
            remainingCGWindowIDsByPlanIndex
    }

    func isResolved(
        expectedTargetWindowPlanIndex: Int
    ) -> Bool {
        targetWindowPlanIndex
            == expectedTargetWindowPlanIndex
            && !targetWindowIsVisible
            && !targetCGWindowIsOnScreen
            && !remainingWindowPlanIndices.contains(
                expectedTargetWindowPlanIndex
            )
    }

    func unmetConditions(
        expectedTargetWindowPlanIndex: Int
    ) -> [String] {
        var conditions: [String] = []
        if targetWindowPlanIndex
            != expectedTargetWindowPlanIndex
        {
            conditions.append("targetWindowPlanIdentity")
        }
        if targetWindowIsVisible {
            conditions.append("targetWindowVisibilityReadback")
        }
        if targetCGWindowIsOnScreen {
            conditions.append("targetCGWindowReadback")
        }
        if remainingWindowPlanIndices.contains(
            expectedTargetWindowPlanIndex
        ) {
            conditions.append("coordinatorTopologyReadback")
        }
        return conditions
    }

    var logFields: String {
        "targetPlanIndex=\(targetWindowPlanIndex) "
            + "targetWindowNumber=\(targetWindowNumber) "
            + "targetVisible=\(targetWindowIsVisible) "
            + "targetCGOnScreen=\(targetCGWindowIsOnScreen) "
            + "remainingPlanIndices=["
            + remainingWindowPlanIndices
                .map(String.init)
                .joined(separator: ",")
            + "] titles=\(remainingWindowTitlesByPlanIndex) "
            + "cgWindowIDs=\(remainingCGWindowIDsByPlanIndex)"
    }
}

struct SpaceFixtureWindowCloseFaultObservation:
    Equatable
{
    let requestGeneration: Int
    let source:
        SpaceFixtureWindowCloseFaultEvidenceSource
    let snapshot: SpaceFixtureWindowCloseTopologySnapshot

    var logFields: String {
        "generation=\(requestGeneration) "
            + "source=\(source.rawValue) "
            + snapshot.logFields
    }
}

struct SpaceFixtureWindowCloseFaultEvidence:
    Equatable
{
    let requestGeneration: Int
    let phase:
        SpaceFixtureWindowCloseFaultEvidencePhase
    let source:
        SpaceFixtureWindowCloseFaultEvidenceSource
    let delayMilliseconds: Int
    let awaitsExplicitTrigger: Bool
    let identity: SpaceFixtureWindowCloseFaultIdentity
    let snapshot: SpaceFixtureWindowCloseTopologySnapshot

    var logFields: String {
        "generation=\(requestGeneration) "
            + "phase=\(phase.rawValue) "
            + "source=\(source.rawValue) "
            + "delayMs=\(delayMilliseconds) "
            + "awaitsTrigger=\(awaitsExplicitTrigger) "
            + "bundleID=\(identity.bundleIdentifier) "
            + "pid=\(identity.processIdentifier) "
            + snapshot.logFields
    }
}

enum SpaceFixtureWindowCloseFaultEvidenceTransport {
    private enum UserInfoKey {
        static let requestGeneration = "requestGeneration"
        static let phase = "phase"
        static let source = "source"
        static let delayMilliseconds = "delayMilliseconds"
        static let awaitsExplicitTrigger =
            "awaitsExplicitTrigger"
        static let bundleIdentifier = "bundleIdentifier"
        static let processIdentifier = "processIdentifier"
        static let targetWindowPlanIndex =
            "targetWindowPlanIndex"
        static let targetWindowNumber =
            "targetWindowNumber"
        static let targetWindowIsVisible =
            "targetWindowIsVisible"
        static let targetCGWindowIsOnScreen =
            "targetCGWindowIsOnScreen"
        static let remainingWindowPlanIndices =
            "remainingWindowPlanIndices"
        static let remainingWindowTitlesByPlanIndex =
            "remainingWindowTitlesByPlanIndex"
        static let remainingCGWindowIDsByPlanIndex =
            "remainingCGWindowIDsByPlanIndex"
    }

    static func publish(
        _ evidence: SpaceFixtureWindowCloseFaultEvidence,
        route: SpaceFixtureWindowCloseFaultEvidenceRoute?
    ) {
        if let route {
            DistributedNotificationCenter.default()
                .postNotificationName(
                    route.notificationName,
                    object: nil,
                    userInfo: userInfo(for: evidence),
                    deliverImmediately: true
                )
        }
        NSLog(
            "SpaceFixture window close fault %@",
            evidence.logFields
        )
    }

    static func evidence(
        from notification: Notification
    ) -> SpaceFixtureWindowCloseFaultEvidence? {
        guard let userInfo = notification.userInfo,
              let requestGeneration = positiveInt(
                userInfo[UserInfoKey.requestGeneration]
              ),
              let phaseValue =
                userInfo[UserInfoKey.phase] as? String,
              let phase =
                SpaceFixtureWindowCloseFaultEvidencePhase(
                    rawValue: phaseValue
                ),
              let sourceValue =
                userInfo[UserInfoKey.source] as? String,
              let source =
                SpaceFixtureWindowCloseFaultEvidenceSource(
                    rawValue: sourceValue
                ),
              let delayMilliseconds = nonnegativeInt(
                userInfo[UserInfoKey.delayMilliseconds]
              ),
              let awaitsExplicitTrigger = (
                userInfo[
                    UserInfoKey.awaitsExplicitTrigger
                ] as? NSNumber
              )?.boolValue,
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
              let targetWindowPlanIndex = positiveInt(
                userInfo[
                    UserInfoKey.targetWindowPlanIndex
                ]
              ),
              let targetWindowNumber = (
                userInfo[
                    UserInfoKey.targetWindowNumber
                ] as? NSNumber
              )?.uint32Value,
              targetWindowNumber > 0,
              let targetWindowIsVisible = (
                userInfo[
                    UserInfoKey.targetWindowIsVisible
                ] as? NSNumber
              )?.boolValue,
              let targetCGWindowIsOnScreen = (
                userInfo[
                    UserInfoKey.targetCGWindowIsOnScreen
                ] as? NSNumber
              )?.boolValue,
              let remainingWindowPlanIndices =
                normalizedPlanIndices(
                    userInfo[
                        UserInfoKey
                            .remainingWindowPlanIndices
                    ]
                )
        else {
            return nil
        }

        let snapshot =
            SpaceFixtureWindowCloseTopologySnapshot(
                targetWindowPlanIndex:
                    targetWindowPlanIndex,
                targetWindowNumber:
                    targetWindowNumber,
                targetWindowIsVisible:
                    targetWindowIsVisible,
                targetCGWindowIsOnScreen:
                    targetCGWindowIsOnScreen,
                remainingWindowPlanIndices:
                    remainingWindowPlanIndices,
                remainingWindowTitlesByPlanIndex:
                    stringDictionary(
                        userInfo[
                            UserInfoKey
                                .remainingWindowTitlesByPlanIndex
                        ]
                    ),
                remainingCGWindowIDsByPlanIndex:
                    cgWindowIDDictionary(
                        userInfo[
                            UserInfoKey
                                .remainingCGWindowIDsByPlanIndex
                        ]
                    )
            )
        guard phase != .applied
            || snapshot.isResolved(
                expectedTargetWindowPlanIndex:
                    targetWindowPlanIndex
            )
        else {
            return nil
        }
        return SpaceFixtureWindowCloseFaultEvidence(
            requestGeneration: requestGeneration,
            phase: phase,
            source: source,
            delayMilliseconds: delayMilliseconds,
            awaitsExplicitTrigger: awaitsExplicitTrigger,
            identity: SpaceFixtureWindowCloseFaultIdentity(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: processIdentifier
            ),
            snapshot: snapshot
        )
    }

    private static func userInfo(
        for evidence: SpaceFixtureWindowCloseFaultEvidence
    ) -> [String: Any] {
        [
            UserInfoKey.requestGeneration:
                NSNumber(value: evidence.requestGeneration),
            UserInfoKey.phase: evidence.phase.rawValue,
            UserInfoKey.source: evidence.source.rawValue,
            UserInfoKey.delayMilliseconds:
                NSNumber(value: evidence.delayMilliseconds),
            UserInfoKey.awaitsExplicitTrigger:
                NSNumber(
                    value:
                        evidence.awaitsExplicitTrigger
                ),
            UserInfoKey.bundleIdentifier:
                evidence.identity.bundleIdentifier,
            UserInfoKey.processIdentifier:
                NSNumber(
                    value:
                        evidence.identity.processIdentifier
                ),
            UserInfoKey.targetWindowPlanIndex:
                NSNumber(
                    value:
                        evidence.snapshot
                            .targetWindowPlanIndex
                ),
            UserInfoKey.targetWindowNumber:
                NSNumber(
                    value:
                        evidence.snapshot
                            .targetWindowNumber
                ),
            UserInfoKey.targetWindowIsVisible:
                NSNumber(
                    value:
                        evidence.snapshot
                            .targetWindowIsVisible
                ),
            UserInfoKey.targetCGWindowIsOnScreen:
                NSNumber(
                    value:
                        evidence.snapshot
                            .targetCGWindowIsOnScreen
                ),
            UserInfoKey.remainingWindowPlanIndices:
                evidence.snapshot
                    .remainingWindowPlanIndices
                    .map { NSNumber(value: $0) },
            UserInfoKey.remainingWindowTitlesByPlanIndex:
                Dictionary(
                    uniqueKeysWithValues:
                        evidence.snapshot
                            .remainingWindowTitlesByPlanIndex
                            .map { (String($0.key), $0.value) }
                ),
            UserInfoKey.remainingCGWindowIDsByPlanIndex:
                Dictionary(
                    uniqueKeysWithValues:
                        evidence.snapshot
                            .remainingCGWindowIDsByPlanIndex
                            .map {
                                (
                                    String($0.key),
                                    NSNumber(value: $0.value)
                                )
                            }
                )
        ]
    }

    private static func positiveInt(_ value: Any?)
        -> Int?
    {
        guard let value = (value as? NSNumber)?.intValue,
              value > 0
        else {
            return nil
        }
        return value
    }

    private static func nonnegativeInt(_ value: Any?)
        -> Int?
    {
        guard let value = (value as? NSNumber)?.intValue,
              value >= 0
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
        let planIndices = numbers.map(\.intValue)
        guard planIndices.allSatisfy({ $0 > 0 }),
              planIndices
                == Array(Set(planIndices)).sorted()
        else {
            return nil
        }
        return planIndices
    }

    private static func stringDictionary(
        _ value: Any?
    ) -> [Int: String] {
        guard let values = value as? [String: String] else {
            return [:]
        }
        return Dictionary(
            uniqueKeysWithValues:
                values.compactMap { key, value in
                    guard let index = Int(key), index > 0,
                          !value.isEmpty
                    else {
                        return nil
                    }
                    return (index, value)
                }
        )
    }

    private static func cgWindowIDDictionary(
        _ value: Any?
    ) -> [Int: CGWindowID] {
        guard let values = value as? [String: NSNumber] else {
            return [:]
        }
        return Dictionary(
            uniqueKeysWithValues:
                values.compactMap { key, value in
                    guard let index = Int(key), index > 0,
                          value.uint32Value > 0
                    else {
                        return nil
                    }
                    return (index, value.uint32Value)
                }
        )
    }
}

enum SpaceFixtureWindowCloseFaultTriggerTransport {
    private enum UserInfoKey {
        static let requestGeneration = "requestGeneration"
        static let bundleIdentifier = "bundleIdentifier"
        static let processIdentifier = "processIdentifier"
        static let targetWindowPlanIndex =
            "targetWindowPlanIndex"
    }

    static func publish(
        _ trigger: SpaceFixtureWindowCloseFaultTrigger,
        route: SpaceFixtureWindowCloseFaultTriggerRoute
    ) {
        DistributedNotificationCenter.default()
            .postNotificationName(
                route.notificationName,
                object: nil,
                userInfo: [
                    UserInfoKey.requestGeneration:
                        NSNumber(
                            value:
                                trigger.requestGeneration
                        ),
                    UserInfoKey.bundleIdentifier:
                        trigger.identity.bundleIdentifier,
                    UserInfoKey.processIdentifier:
                        NSNumber(
                            value:
                                trigger.identity
                                    .processIdentifier
                        ),
                    UserInfoKey.targetWindowPlanIndex:
                        NSNumber(
                            value:
                                trigger
                                    .targetWindowPlanIndex
                        )
                ],
                deliverImmediately: true
            )
    }

    static func trigger(
        from notification: Notification
    ) -> SpaceFixtureWindowCloseFaultTrigger? {
        guard let userInfo = notification.userInfo,
              let requestGeneration = (
                userInfo[
                    UserInfoKey.requestGeneration
                ] as? NSNumber
              )?.intValue,
              requestGeneration > 0,
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
              let targetWindowPlanIndex = (
                userInfo[
                    UserInfoKey.targetWindowPlanIndex
                ] as? NSNumber
              )?.intValue,
              targetWindowPlanIndex > 0
        else {
            return nil
        }
        return SpaceFixtureWindowCloseFaultTrigger(
            requestGeneration: requestGeneration,
            identity: SpaceFixtureWindowCloseFaultIdentity(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: processIdentifier
            ),
            targetWindowPlanIndex:
                targetWindowPlanIndex
        )
    }
}
