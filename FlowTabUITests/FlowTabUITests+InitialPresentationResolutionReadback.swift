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
    let selectedAppID: String
    let inputReadinessObservationGeneration: UInt64
    let inputReadinessSource: String
    let inputReadinessResolved: Bool
    let inputReadinessBaselineSourceGeneration: Generation?
    let inputReadinessSourceGeneration: Generation?
    let inputReadinessPresentationGeneration: Int
    let inputReadinessPanelIsVisibleToUser: Bool
    let inputReadinessPanelIsKey: Bool
    let inputReadinessApplicationIsActive: Bool
    let inputReadinessSessionItemIDs: [String]
    let inputReadinessSelectedAppID: String?
    let inputReadinessPanelPresentationDiagnosticProbePending: Bool
    let inputReadinessInitialVisibilityPending: Bool
    let inputReadinessPanelVisibilityRecoveryPending: Bool
    let inputReadinessActiveSpaceTransitionPending: Bool
    let inputReadinessApplicationActivationSuppressed: Bool
    let inputReadinessTerminateInterruptionProtectionPending: Bool
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
            + "selectedAppID=\(selectedAppID) "
            + "inputGeneration=\(inputReadinessObservationGeneration) "
            + "inputSource=\(inputReadinessSource) "
            + "inputResolved=\(inputReadinessResolved) "
            + "inputPresentationGeneration=\(inputReadinessPresentationGeneration) "
            + "inputPanelVisible=\(inputReadinessPanelIsVisibleToUser) "
            + "inputPanelKey=\(inputReadinessPanelIsKey) "
            + "inputAppActive=\(inputReadinessApplicationIsActive) "
            + "inputSessionItems=[\(inputReadinessSessionItemIDs.joined(separator: ","))] "
            + "inputSelectedAppID=\(inputReadinessSelectedAppID ?? "nil") "
            + "inputPanelDiagnosticPending=\(inputReadinessPanelPresentationDiagnosticProbePending) "
            + "inputInitialVisibilityPending=\(inputReadinessInitialVisibilityPending) "
            + "inputPanelRecoveryPending=\(inputReadinessPanelVisibilityRecoveryPending) "
            + "inputActiveSpacePending=\(inputReadinessActiveSpaceTransitionPending) "
            + "inputActivationSuppressed=\(inputReadinessApplicationActivationSuppressed) "
            + "inputTerminateProtectionPending=\(inputReadinessTerminateInterruptionProtectionPending) "
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
    let excludedItemIDs: Set<String>
    let searchFeatureEnabled: Bool
    let searchIsActive: Bool
    let searchActivationIsPending: Bool

    func isSatisfied(
        by readback:
            FlowTabUITestInitialPresentationResolutionReadback
    ) -> Bool {
        let candidateItemIDs = Set(readback.candidateItemIDs)
        let acceptedSources: Set<String> = [
            "initialReadback",
            "readinessRequestReadback",
            "appSwitcherProjectionDidUpdate"
        ]
        let acceptedInputReadinessSources: Set<String> = [
            "initialReadback",
            "readinessRequestReadback",
            "projectionUpdateReadback",
            "scheduledReadback",
            "watchdogReadback"
        ]
        guard readback.schemaVersion == 3,
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
                of: candidateItemIDs
              ),
              excludedItemIDs.isDisjoint(with: candidateItemIDs),
              readback.didPresent,
              readback.sessionItemIDs
                == readback.candidateItemIDs,
              !readback.selectedAppID.isEmpty,
              candidateItemIDs.contains(readback.selectedAppID),
              readback.inputReadinessObservationGeneration > 0,
              acceptedInputReadinessSources.contains(
                readback.inputReadinessSource
              ),
              readback.inputReadinessResolved,
              let inputBaselineGeneration =
                readback.inputReadinessBaselineSourceGeneration,
              let inputGeneration =
                readback.inputReadinessSourceGeneration,
              inputGeneration.isSameOrLater(
                than: inputBaselineGeneration
              ),
              inputGeneration != inputBaselineGeneration,
              readback.inputReadinessPresentationGeneration > 0,
              readback.inputReadinessPanelIsVisibleToUser,
              readback.inputReadinessSessionItemIDs
                == readback.candidateItemIDs,
              readback.inputReadinessSelectedAppID
                == readback.selectedAppID,
              !readback.inputReadinessPanelPresentationDiagnosticProbePending,
              !readback.inputReadinessInitialVisibilityPending,
              !readback.inputReadinessPanelVisibilityRecoveryPending,
              !readback.inputReadinessActiveSpaceTransitionPending,
              !readback.inputReadinessApplicationActivationSuppressed,
              !readback.inputReadinessTerminateInterruptionProtectionPending,
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

struct FlowTabUITestInitialPresentationResolutionLaunch {
    let application: XCUIApplication
    let resolution:
        FlowTabUITestInitialPresentationResolutionReadback
}

extension FlowTabUITests {
    @discardableResult
    func assertInitialSwitcherPresentationResolution(
        additionalArguments: [String],
        expectation:
            FlowTabUITestInitialPresentationResolutionExpectation,
        targetDescription: String
    ) throws ->
        FlowTabUITestInitialPresentationResolutionReadback?
    {
        guard let launch = try
            launchFlowTabUITestApplicationResolvingInitialPresentation(
                additionalArguments: additionalArguments,
                expectation: expectation,
                targetDescription: targetDescription
            )
        else {
            return nil
        }
        defer { launch.application.terminate() }
        return launch.resolution
    }

    func launchFlowTabUITestApplicationResolvingInitialPresentation(
        additionalArguments: [String],
        expectation:
            FlowTabUITestInitialPresentationResolutionExpectation,
        targetDescription: String
    ) throws ->
        FlowTabUITestInitialPresentationResolutionLaunch?
    {
        let route = FlowTabUITestInitialPresentationResolutionRoute()
        try route.prepareReadback()
        let owner =
            FlowTabUITestInitialPresentationResolutionObservationOwner(
                route: route,
                expectation: expectation
            )
        owner.start()
        defer {
            owner.cancel()
            route.removeReadback()
        }

        let app = makeApp(
            additionalArguments:
                additionalArguments + route.launchArguments
        )
        launchFlowTabUITestApplication(app)

        guard let resolution = owner.waitForResolution(
            timeout:
                FlowTabUITestInitialPresentationResolutionPolicy
                    .watchdog
        ) else {
            XCTFail(
                "Initial Switcher presentation watchdog expired. "
                    + "target=\(targetDescription) "
                    + "required="
                    + "[\(expectation.requiredItemIDs.sorted().joined(separator: ","))] "
                    + "excluded="
                    + "[\(expectation.excludedItemIDs.sorted().joined(separator: ","))] "
                    + owner.diagnosticSummary
            )
            app.terminate()
            return nil
        }

        let candidateItemIDs = Set(resolution.candidateItemIDs)
        XCTAssertTrue(
            expectation.requiredItemIDs.isSubset(of: candidateItemIDs),
            resolution.diagnosticSummary
        )
        XCTAssertTrue(
            expectation.excludedItemIDs.isDisjoint(
                with: candidateItemIDs
            ),
            resolution.diagnosticSummary
        )
        XCTAssertEqual(
            resolution.sessionItemIDs,
            resolution.candidateItemIDs,
            resolution.diagnosticSummary
        )
        XCTAssertTrue(
            resolution.panelIsPresented,
            resolution.diagnosticSummary
        )
        XCTAssertEqual(
            resolution.sessionMode,
            "appCycle",
            resolution.diagnosticSummary
        )
        XCTAssertTrue(
            candidateItemIDs.contains(resolution.selectedAppID),
            resolution.diagnosticSummary
        )
        XCTAssertTrue(
            resolution.inputReadinessResolved,
            resolution.diagnosticSummary
        )
        XCTAssertEqual(
            resolution.inputReadinessSessionItemIDs,
            resolution.candidateItemIDs,
            resolution.diagnosticSummary
        )
        XCTAssertEqual(
            resolution.inputReadinessSelectedAppID,
            resolution.selectedAppID,
            resolution.diagnosticSummary
        )
        return FlowTabUITestInitialPresentationResolutionLaunch(
            application: app,
            resolution: resolution
        )
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
