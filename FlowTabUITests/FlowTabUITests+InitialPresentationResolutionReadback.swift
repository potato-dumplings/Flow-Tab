import Foundation
import XCTest

enum FlowTabUITestInitialPresentationResolutionPolicy {
    static let immediateReadback: TimeInterval = 0
    static let watchdog: TimeInterval = 8
    static let readbackCadence: TimeInterval = 0.1
}

struct FlowTabUITestInitialPresentationResolutionRoute {
    static let notificationArgument =
        "--flowtab-ui-initial-presentation-resolution-notification-name"
    static let readbackPathArgument =
        "--flowtab-ui-initial-presentation-resolution-readback-path"

    let notificationName: Notification.Name
    let readbackURL: URL

    init(
        temporaryDirectory: URL =
            FileManager.default.temporaryDirectory
    ) {
        let identifier = UUID().uuidString
        notificationName = Notification.Name(
            "io.github.potato-dumplings.flowtab.ui-test."
                + "initial-presentation.\(identifier)"
        )
        readbackURL = temporaryDirectory.appendingPathComponent(
            "flowtab-initial-presentation-\(identifier).json",
            isDirectory: false
        )
    }

    var launchArguments: [String] {
        [
            Self.notificationArgument,
            notificationName.rawValue,
            Self.readbackPathArgument,
            readbackURL.path
        ]
    }

    func prepareReadback() throws {
        guard FileManager.default.fileExists(
            atPath: readbackURL.path
        ) else {
            return
        }
        try FileManager.default.removeItem(at: readbackURL)
    }

    func removeReadback() {
        try? FileManager.default.removeItem(at: readbackURL)
    }
}

struct FlowTabUITestInitialPresentationResolutionReadback:
    Codable,
    Equatable
{
    struct Generation: Codable, Equatable {
        let appLifecycle: UInt64
        let cg: UInt64
        let space: UInt64
        let axDirty: UInt64
        let projection: UInt64

        func isSameOrLater(
            than baseline: Generation
        ) -> Bool {
            appLifecycle >= baseline.appLifecycle
                && cg >= baseline.cg
                && space >= baseline.space
                && axDirty >= baseline.axDirty
                && projection >= baseline.projection
        }
    }

    let schemaVersion: Int
    let observationGeneration: UInt64
    let source: String
    let resolution: String
    let baselineMode: String
    let baselineSourceGeneration: Generation?
    let candidateMode: String
    let candidateProjectionIsPresent: Bool
    let candidateProjectionIsComplete: Bool
    let candidateSourceGeneration: Generation?
    let candidateProcessIdentifier: Int32?
    let candidateItemIDs: [String]
    let didPresent: Bool
    let sessionItemIDs: [String]
    let attemptSearchIsActiveOrPending: Bool
    let postPresentationMode: String
    let postPresentationSourceGeneration: Generation?
    let postPresentationProcessIdentifier: Int32?
    let postPresentationItemIDs: [String]
    let panelIsPresented: Bool
    let sessionMode: String?
    let searchFeatureEnabled: Bool
    let searchIsActive: Bool
    let searchActivationIsPending: Bool

    var diagnosticSummary: String {
        "schema=\(schemaVersion) generation=\(observationGeneration) "
            + "source=\(source) resolution=\(resolution) "
            + "baselineMode=\(baselineMode) "
            + "candidateMode=\(candidateMode) "
            + "candidatePresent=\(candidateProjectionIsPresent) "
            + "candidateComplete=\(candidateProjectionIsComplete) "
            + "candidateItems=[\(candidateItemIDs.joined(separator: ","))] "
            + "didPresent=\(didPresent) "
            + "sessionItems=[\(sessionItemIDs.joined(separator: ","))] "
            + "attemptSearch=\(attemptSearchIsActiveOrPending) "
            + "postMode=\(postPresentationMode) "
            + "postItems=[\(postPresentationItemIDs.joined(separator: ","))] "
            + "panel=\(panelIsPresented) "
            + "sessionMode=\(sessionMode ?? "nil") "
            + "searchEnabled=\(searchFeatureEnabled) "
            + "searchActive=\(searchIsActive) "
            + "searchPending=\(searchActivationIsPending)"
    }
}

struct FlowTabUITestInitialPresentationResolutionExpectation {
    let requiredItemIDs: Set<String>
    let searchFeatureEnabled: Bool
    let searchIsActive: Bool
    let searchActivationIsPending: Bool

    func isSatisfied(
        by readback:
            FlowTabUITestInitialPresentationResolutionReadback
    ) -> Bool {
        let acceptedSources: Set<String> = [
            "initialReadback",
            "readinessRequestReadback",
            "appSwitcherProjectionDidUpdate"
        ]
        guard readback.schemaVersion == 1,
              readback.observationGeneration > 0,
              acceptedSources.contains(readback.source),
              readback.resolution == "presented",
              readback.baselineMode == "global",
              readback.candidateMode == "global",
              readback.candidateProjectionIsPresent,
              readback.candidateProjectionIsComplete,
              let candidateGeneration =
                readback.candidateSourceGeneration,
              candidateGeneration.projection > 0,
              requiredItemIDs.isSubset(
                of: Set(readback.candidateItemIDs)
              ),
              readback.didPresent,
              readback.sessionItemIDs
                == readback.candidateItemIDs,
              !readback.attemptSearchIsActiveOrPending,
              readback.postPresentationMode
                == readback.candidateMode,
              let postGeneration =
                readback.postPresentationSourceGeneration,
              postGeneration.isSameOrLater(
                than: candidateGeneration
              ),
              readback.postPresentationProcessIdentifier
                == readback.candidateProcessIdentifier,
              readback.postPresentationItemIDs
                == readback.candidateItemIDs,
              readback.panelIsPresented,
              readback.sessionMode == "appCycle",
              readback.searchFeatureEnabled
                == searchFeatureEnabled,
              readback.searchIsActive == searchIsActive,
              readback.searchActivationIsPending
                == searchActivationIsPending
        else {
            return false
        }
        return true
    }
}

struct FlowTabUITestInitialPresentationResolutionFileReadback {
    let path: String
    let fileExists: Bool
    let resolution:
        FlowTabUITestInitialPresentationResolutionReadback?
    let errorDescription: String?

    static func read(from url: URL) -> Self {
        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return Self(
                path: url.path,
                fileExists: false,
                resolution: nil,
                errorDescription: nil
            )
        }
        do {
            let resolution = try JSONDecoder().decode(
                FlowTabUITestInitialPresentationResolutionReadback
                    .self,
                from: Data(contentsOf: url)
            )
            return Self(
                path: url.path,
                fileExists: true,
                resolution: resolution,
                errorDescription: nil
            )
        } catch {
            return Self(
                path: url.path,
                fileExists: true,
                resolution: nil,
                errorDescription: String(describing: error)
            )
        }
    }

    var diagnosticSummary: String {
        if let resolution {
            return "path=\(path) "
                + resolution.diagnosticSummary
        }
        return "path=\(path) fileExists=\(fileExists) "
            + "error=\(errorDescription ?? "nil")"
    }
}

final class
    FlowTabUITestInitialPresentationResolutionObservationOwner
{
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestInitialPresentationResolutionFileReadback
        >

    init(
        route:
            FlowTabUITestInitialPresentationResolutionRoute,
        expectation:
            FlowTabUITestInitialPresentationResolutionExpectation,
        center: DistributedNotificationCenter = .default(),
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? = nil
    ) {
        let registration = observationRegistration
            ?? Self.defaultRegistration(
                route: route,
                center: center
            )
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: registration,
            readback: {
                FlowTabUITestInitialPresentationResolutionFileReadback
                    .read(from: route.readbackURL)
            },
            isSatisfied: {
                guard let resolution = $0.resolution else {
                    return false
                }
                return expectation.isSatisfied(by: resolution)
            },
            describe: \.diagnosticSummary
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestInitialPresentationResolutionReadback? {
        conditionOwner.waitForResolution(
            timeout: timeout
        )?.value.resolution
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }

    private static func defaultRegistration(
        route:
            FlowTabUITestInitialPresentationResolutionRoute,
        center: DistributedNotificationCenter
    ) -> FlowTabUITestConditionObservationRegistration {
        { readback in
            let token = center.addObserver(
                forName: route.notificationName,
                object: nil,
                queue: .main
            ) { _ in
                readback(.notificationReadback)
            }
            let scheduledCancellation =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestInitialPresentationResolutionPolicy
                                .readbackCadence
                    )(readback)
            return FlowTabUITestObservationCancellation {
                center.removeObserver(token)
                scheduledCancellation?.cancel()
            }
        }
    }
}
