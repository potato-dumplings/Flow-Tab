import Darwin
import Foundation

struct SpaceFixtureApplicationAXSuppressionRoute: Equatable {
    static let projectionAcknowledgementArgument =
        "--projection-acknowledgement-notification-name"
    static let suppressionCompletionArgument =
        "--accessibility-suppression-notification-name"

    let projectionAcknowledgementNotificationName:
        Notification.Name
    let suppressionCompletionNotificationName:
        Notification.Name
}

struct SpaceFixtureApplicationIdentity: Equatable {
    let bundleIdentifier: String
    let processIdentifier: pid_t
}

struct SpaceFixtureApplicationAXExposure: Equatable {
    let childWindowCount: Int
    let windowsAttributeCount: Int

    var isSuppressed: Bool {
        childWindowCount == 0
            && windowsAttributeCount == 0
    }

    func matchesPublishedWindowCount(
        _ expectedWindowCount: Int
    ) -> Bool {
        childWindowCount == expectedWindowCount
            && windowsAttributeCount == expectedWindowCount
    }

    var logFields: String {
        "children=\(childWindowCount) "
            + "windows=\(windowsAttributeCount)"
    }
}

struct SpaceFixtureProjectionAcknowledgement: Equatable {
    let acknowledgementGeneration: UInt64
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let windowCount: Int
    let sourceGeneration: String
}

enum SpaceFixtureApplicationAXSuppressionEvidenceSource:
    String,
    Equatable
{
    case initialReadback
    case localTopologyStage
    case projectionAcknowledgement
    case suppressionActionReadback
    case retryReadback
    case watchdogReadback
}

struct SpaceFixtureApplicationAXSuppressionEvidence:
    Equatable
{
    let source:
        SpaceFixtureApplicationAXSuppressionEvidenceSource
    let observationGeneration: Int
    let identity: SpaceFixtureApplicationIdentity
    let expectedProjectionWindowCount: Int
    let expectedPublishedAXWindowCount: Int
    let routeIsConfigured: Bool
    let localTopologyStageReached: Bool
    let suppressionRequested: Bool
    let exposure: SpaceFixtureApplicationAXExposure
    let lastAcknowledgement:
        SpaceFixtureProjectionAcknowledgement?
    let matchingAcknowledgement:
        SpaceFixtureProjectionAcknowledgement?

    var unmetConditions: [String] {
        var conditions: [String] = []
        if !localTopologyStageReached {
            conditions.append("localTopologyStageReached")
        }
        if !exposure.matchesPublishedWindowCount(
            expectedPublishedAXWindowCount
        ) && !suppressionRequested {
            conditions.append(
                "applicationAXPublishedWindowCount"
            )
        }
        if routeIsConfigured
            && matchingAcknowledgement == nil
        {
            conditions.append(
                "matchingProjectionAcknowledgement"
            )
        }
        if suppressionRequested && !exposure.isSuppressed {
            conditions.append("applicationAXSuppressedReadback")
        }
        return conditions
    }

    var logFields: String {
        let lastAcknowledgementFields: String
        if let lastAcknowledgement {
            lastAcknowledgementFields =
                "generation=\(lastAcknowledgement.acknowledgementGeneration),"
                + "bundleID=\(lastAcknowledgement.bundleIdentifier),"
                + "pid=\(lastAcknowledgement.processIdentifier),"
                + "windows=\(lastAcknowledgement.windowCount),"
                + "sourceGeneration=\(lastAcknowledgement.sourceGeneration)"
        } else {
            lastAcknowledgementFields = "nil"
        }
        return "source=\(source.rawValue) "
            + "generation=\(observationGeneration) "
            + "bundleID=\(identity.bundleIdentifier) "
            + "pid=\(identity.processIdentifier) "
            + "expectedProjectionWindows="
            + "\(expectedProjectionWindowCount) "
            + "expectedPublishedAXWindows="
            + "\(expectedPublishedAXWindowCount) "
            + "routeConfigured=\(routeIsConfigured) "
            + "localTopology=\(localTopologyStageReached) "
            + "suppressionRequested=\(suppressionRequested) "
            + "\(exposure.logFields) "
            + "lastAcknowledgement={\(lastAcknowledgementFields)}"
    }
}

struct SpaceFixtureApplicationAXSuppressionCompletion:
    Equatable
{
    let observationGeneration: Int
    let suppressionGeneration: UInt64
    let identity: SpaceFixtureApplicationIdentity
    let expectedProjectionWindowCount: Int
    let acknowledgement:
        SpaceFixtureProjectionAcknowledgement
    let exposure: SpaceFixtureApplicationAXExposure
}

struct SpaceFixtureApplicationAXSuppressionWatchdogFailure:
    Equatable
{
    let watchdogMilliseconds: Int
    let lastEvidence:
        SpaceFixtureApplicationAXSuppressionEvidence
    let finalEvidence:
        SpaceFixtureApplicationAXSuppressionEvidence

    var logFields: String {
        "condition=applicationAXSuppression "
            + "watchdogMs=\(watchdogMilliseconds) "
            + "unmet=["
            + finalEvidence.unmetConditions.joined(
                separator: ","
            )
            + "] last{\(lastEvidence.logFields)} "
            + "final{\(finalEvidence.logFields)}"
    }
}
