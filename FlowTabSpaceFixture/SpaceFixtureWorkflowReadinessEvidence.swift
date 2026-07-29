import Darwin
import Foundation

struct SpaceFixtureWorkflowReadinessRoute: Equatable {
    static let notificationArgument =
        "--workflow-readiness-notification-name"

    let notificationName: Notification.Name
}

struct SpaceFixtureWorkflowReadinessIdentity: Equatable {
    let bundleIdentifier: String
    let processIdentifier: pid_t
}

enum SpaceFixtureWorkflowReadinessStage:
    String,
    Equatable
{
    case configured
    case windowTopology
    case fullscreenTopology
    case desktopPresentation
    case applicationAXExposure
    case ready
}

struct SpaceFixtureWorkflowReadinessSnapshot:
    Equatable
{
    let expectedWindowPlanIndices: [Int]
    let observedWindowPlanIndices: [Int]
    let expectedFullscreenWindowPlanIndices: [Int]
    let completedFullscreenWindowPlanIndices: [Int]
    let desktopAnchorWindowPlanIndex: Int?
    let desktopPresentationResolved: Bool
    let applicationAXSuppressionRequired: Bool
    let applicationAXExposureResolved: Bool
    let windowTitles: [String]

    var isReady: Bool {
        observedWindowPlanIndices
            == expectedWindowPlanIndices
            && completedFullscreenWindowPlanIndices
                == expectedFullscreenWindowPlanIndices
            && (
                desktopAnchorWindowPlanIndex == nil
                    || desktopPresentationResolved
            )
            && (
                !applicationAXSuppressionRequired
                    || applicationAXExposureResolved
            )
    }

    var unmetConditions: [String] {
        var conditions: [String] = []
        if observedWindowPlanIndices
            != expectedWindowPlanIndices
        {
            conditions.append("windowTopology")
        }
        if completedFullscreenWindowPlanIndices
            != expectedFullscreenWindowPlanIndices
        {
            conditions.append("fullscreenTopology")
        }
        if desktopAnchorWindowPlanIndex != nil,
           !desktopPresentationResolved
        {
            conditions.append("desktopPresentation")
        }
        if applicationAXSuppressionRequired,
           !applicationAXExposureResolved
        {
            conditions.append("applicationAXExposure")
        }
        return conditions
    }

    var logFields: String {
        "expectedWindows=\(list(expectedWindowPlanIndices)) "
            + "observedWindows=\(list(observedWindowPlanIndices)) "
            + "expectedFullscreen="
            + "\(list(expectedFullscreenWindowPlanIndices)) "
            + "completedFullscreen="
            + "\(list(completedFullscreenWindowPlanIndices)) "
            + "desktopAnchor="
            + "\(desktopAnchorWindowPlanIndex.map(String.init) ?? "none") "
            + "desktopResolved=\(desktopPresentationResolved) "
            + "axSuppressionRequired="
            + "\(applicationAXSuppressionRequired) "
            + "axExposureResolved="
            + "\(applicationAXExposureResolved) "
            + "unmet=[\(unmetConditions.joined(separator: ","))]"
    }

    private func list(_ values: [Int]) -> String {
        "[" + values.map(String.init).joined(separator: ",") + "]"
    }
}

struct SpaceFixtureWorkflowReadinessEvidence:
    Equatable
{
    let observationGeneration: Int
    let transitionGeneration: UInt64
    let stage: SpaceFixtureWorkflowReadinessStage
    let identity: SpaceFixtureWorkflowReadinessIdentity
    let snapshot: SpaceFixtureWorkflowReadinessSnapshot

    var logFields: String {
        "observationGeneration=\(observationGeneration) "
            + "transitionGeneration=\(transitionGeneration) "
            + "stage=\(stage.rawValue) "
            + "bundleID=\(identity.bundleIdentifier) "
            + "pid=\(identity.processIdentifier) "
            + snapshot.logFields
    }
}

enum SpaceFixtureWorkflowReadinessTransport {
    private enum UserInfoKey {
        static let observationGeneration =
            "observationGeneration"
        static let transitionGeneration =
            "transitionGeneration"
        static let stage = "stage"
        static let bundleIdentifier = "bundleIdentifier"
        static let processIdentifier = "processIdentifier"
        static let expectedWindowPlanIndices =
            "expectedWindowPlanIndices"
        static let observedWindowPlanIndices =
            "observedWindowPlanIndices"
        static let expectedFullscreenWindowPlanIndices =
            "expectedFullscreenWindowPlanIndices"
        static let completedFullscreenWindowPlanIndices =
            "completedFullscreenWindowPlanIndices"
        static let desktopAnchorWindowPlanIndex =
            "desktopAnchorWindowPlanIndex"
        static let desktopPresentationResolved =
            "desktopPresentationResolved"
        static let applicationAXSuppressionRequired =
            "applicationAXSuppressionRequired"
        static let applicationAXExposureResolved =
            "applicationAXExposureResolved"
        static let windowTitles = "windowTitles"
    }

    static func publish(
        _ evidence: SpaceFixtureWorkflowReadinessEvidence,
        route: SpaceFixtureWorkflowReadinessRoute?
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
            "SpaceFixture workflow readiness %@",
            evidence.logFields
        )
    }

    static func evidence(
        from notification: Notification
    ) -> SpaceFixtureWorkflowReadinessEvidence? {
        guard let userInfo = notification.userInfo,
              let observationGeneration = positiveInt(
                userInfo[UserInfoKey.observationGeneration]
              ),
              let transitionGeneration = positiveUInt64(
                userInfo[UserInfoKey.transitionGeneration]
              ),
              let stageValue =
                userInfo[UserInfoKey.stage] as? String,
              let stage = SpaceFixtureWorkflowReadinessStage(
                rawValue: stageValue
              ),
              let bundleIdentifier =
                userInfo[UserInfoKey.bundleIdentifier]
                    as? String,
              !bundleIdentifier.isEmpty,
              let processIdentifier = (
                userInfo[UserInfoKey.processIdentifier]
                    as? NSNumber
              )?.int32Value,
              processIdentifier > 0,
              let expectedWindowPlanIndices =
                planIndices(
                    userInfo[
                        UserInfoKey
                            .expectedWindowPlanIndices
                    ]
                ),
              !expectedWindowPlanIndices.isEmpty,
              let observedWindowPlanIndices =
                planIndices(
                    userInfo[
                        UserInfoKey
                            .observedWindowPlanIndices
                    ]
                ),
              let expectedFullscreenWindowPlanIndices =
                planIndices(
                    userInfo[
                        UserInfoKey
                            .expectedFullscreenWindowPlanIndices
                    ]
                ),
              let completedFullscreenWindowPlanIndices =
                planIndices(
                    userInfo[
                        UserInfoKey
                            .completedFullscreenWindowPlanIndices
                    ]
                ),
              let desktopAnchorValue =
                userInfo[
                    UserInfoKey
                        .desktopAnchorWindowPlanIndex
                ] as? NSNumber,
              let desktopPresentationResolved = bool(
                userInfo[
                    UserInfoKey
                        .desktopPresentationResolved
                ]
              ),
              let applicationAXSuppressionRequired = bool(
                userInfo[
                    UserInfoKey
                        .applicationAXSuppressionRequired
                ]
              ),
              let applicationAXExposureResolved = bool(
                userInfo[
                    UserInfoKey
                        .applicationAXExposureResolved
                ]
              ),
              let windowTitles =
                userInfo[UserInfoKey.windowTitles]
                    as? [String],
              windowTitles.count
                == expectedWindowPlanIndices.count
        else {
            return nil
        }
        let desktopAnchorWindowPlanIndex =
            desktopAnchorValue.intValue > 0
            ? desktopAnchorValue.intValue
            : nil
        guard observedWindowPlanIndices.allSatisfy(
                expectedWindowPlanIndices.contains
              ),
              completedFullscreenWindowPlanIndices
                .allSatisfy(
                    expectedFullscreenWindowPlanIndices
                        .contains
                ),
              desktopAnchorWindowPlanIndex.map(
                expectedWindowPlanIndices.contains
              ) ?? true
        else {
            return nil
        }
        let snapshot =
            SpaceFixtureWorkflowReadinessSnapshot(
                expectedWindowPlanIndices:
                    expectedWindowPlanIndices,
                observedWindowPlanIndices:
                    observedWindowPlanIndices,
                expectedFullscreenWindowPlanIndices:
                    expectedFullscreenWindowPlanIndices,
                completedFullscreenWindowPlanIndices:
                    completedFullscreenWindowPlanIndices,
                desktopAnchorWindowPlanIndex:
                    desktopAnchorWindowPlanIndex,
                desktopPresentationResolved:
                    desktopPresentationResolved,
                applicationAXSuppressionRequired:
                    applicationAXSuppressionRequired,
                applicationAXExposureResolved:
                    applicationAXExposureResolved,
                windowTitles: windowTitles
            )
        guard stage != .ready || snapshot.isReady else {
            return nil
        }
        return SpaceFixtureWorkflowReadinessEvidence(
            observationGeneration: observationGeneration,
            transitionGeneration: transitionGeneration,
            stage: stage,
            identity: SpaceFixtureWorkflowReadinessIdentity(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: processIdentifier
            ),
            snapshot: snapshot
        )
    }

    private static func userInfo(
        for evidence: SpaceFixtureWorkflowReadinessEvidence
    ) -> [String: Any] {
        [
            UserInfoKey.observationGeneration:
                NSNumber(
                    value: evidence.observationGeneration
                ),
            UserInfoKey.transitionGeneration:
                NSNumber(
                    value: evidence.transitionGeneration
                ),
            UserInfoKey.stage: evidence.stage.rawValue,
            UserInfoKey.bundleIdentifier:
                evidence.identity.bundleIdentifier,
            UserInfoKey.processIdentifier:
                NSNumber(
                    value:
                        evidence.identity.processIdentifier
                ),
            UserInfoKey.expectedWindowPlanIndices:
                numbers(
                    evidence.snapshot
                        .expectedWindowPlanIndices
                ),
            UserInfoKey.observedWindowPlanIndices:
                numbers(
                    evidence.snapshot
                        .observedWindowPlanIndices
                ),
            UserInfoKey.expectedFullscreenWindowPlanIndices:
                numbers(
                    evidence.snapshot
                        .expectedFullscreenWindowPlanIndices
                ),
            UserInfoKey.completedFullscreenWindowPlanIndices:
                numbers(
                    evidence.snapshot
                        .completedFullscreenWindowPlanIndices
                ),
            UserInfoKey.desktopAnchorWindowPlanIndex:
                NSNumber(
                    value:
                        evidence.snapshot
                            .desktopAnchorWindowPlanIndex ?? 0
                ),
            UserInfoKey.desktopPresentationResolved:
                NSNumber(
                    value:
                        evidence.snapshot
                            .desktopPresentationResolved
                ),
            UserInfoKey.applicationAXSuppressionRequired:
                NSNumber(
                    value:
                        evidence.snapshot
                            .applicationAXSuppressionRequired
                ),
            UserInfoKey.applicationAXExposureResolved:
                NSNumber(
                    value:
                        evidence.snapshot
                            .applicationAXExposureResolved
                ),
            UserInfoKey.windowTitles:
                evidence.snapshot.windowTitles
        ]
    }

    private static func numbers(
        _ values: [Int]
    ) -> [NSNumber] {
        values.map { NSNumber(value: $0) }
    }

    private static func planIndices(
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

    private static func positiveInt(_ value: Any?)
        -> Int?
    {
        guard let result = (value as? NSNumber)?
                .intValue,
              result > 0
        else {
            return nil
        }
        return result
    }

    private static func positiveUInt64(_ value: Any?)
        -> UInt64?
    {
        guard let number = value as? NSNumber,
              number.int64Value > 0
        else {
            return nil
        }
        return number.uint64Value
    }

    private static func bool(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }
}
