import Darwin
import Foundation
import XCTest

struct SpaceFixtureWindowOpenMutationUITestRoute {
    let evidenceNotificationName: Notification.Name
    let triggerNotificationName: Notification.Name

    var fixtureLaunchArguments: [String] {
        [
            "--window-open-evidence-notification-name",
            evidenceNotificationName.rawValue,
            "--window-open-trigger-notification-name",
            triggerNotificationName.rawValue
        ]
    }
}

enum SpaceFixtureWindowOpenMutationUITestPolicy {
    static let readyEvidenceWatchdog: TimeInterval = 8
    static let appliedEvidenceWatchdog: TimeInterval = 12
    static let fixtureWindowReadbackWatchdog: TimeInterval = 8
    static let panelDismissalWatchdog: TimeInterval = 5
    static let switcherProjectionWatchdog: TimeInterval = 25
}

private enum SpaceFixtureWindowOpenMutationUITestPhase: String {
    case ready
    case applied
}

struct SpaceFixtureWindowOpenMutationUITestEvidence: Equatable {
    let requestGeneration: Int
    fileprivate let phase:
        SpaceFixtureWindowOpenMutationUITestPhase
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let targetWindowPlanIndex: Int
    let targetWindowTitle: String
    let activeWindowPlanIndices: [Int]

    var diagnosticSummary: String {
        "generation=\(requestGeneration) "
            + "phase=\(phase.rawValue) "
            + "bundleID=\(bundleIdentifier) "
            + "pid=\(processIdentifier) "
            + "targetPlanIndex=\(targetWindowPlanIndex) "
            + "targetTitle=\(targetWindowTitle) "
            + "activePlanIndices=["
            + activeWindowPlanIndices.map(String.init).joined(separator: ",")
            + "]"
    }
}

final class SpaceFixtureWindowOpenMutationObservationOwner {
    private enum UserInfoKey {
        static let requestGeneration = "requestGeneration"
        static let phase = "phase"
        static let bundleIdentifier = "bundleIdentifier"
        static let processIdentifier = "processIdentifier"
        static let targetWindowPlanIndex = "targetWindowPlanIndex"
        static let targetWindowTitle = "targetWindowTitle"
        static let activeWindowPlanIndices = "activeWindowPlanIndices"
    }

    private let route: SpaceFixtureWindowOpenMutationUITestRoute
    private let center: DistributedNotificationCenter
    private var observationToken: NSObjectProtocol?
    private var evidence:
        [SpaceFixtureWindowOpenMutationUITestEvidence] = []
    private var requestedGeneration: Int?
    private let readyExpectation = XCTestExpectation(
        description: "fixture window-open ready evidence"
    )
    private let appliedExpectation = XCTestExpectation(
        description: "fixture window-open applied evidence"
    )

    init(
        route: SpaceFixtureWindowOpenMutationUITestRoute,
        center: DistributedNotificationCenter = .default()
    ) {
        self.route = route
        self.center = center
    }

    func start() {
        cancel()
        evidence.removeAll()
        requestedGeneration = nil
        observationToken = center.addObserver(
            forName: route.evidenceNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.observe(notification)
        }
    }

    func waitForReady(
        timeout: TimeInterval
    ) -> SpaceFixtureWindowOpenMutationUITestEvidence? {
        wait(
            for: readyExpectation,
            phase: .ready,
            requestGeneration: nil,
            timeout: timeout
        )
    }

    func requestOpen(
        from readyEvidence:
            SpaceFixtureWindowOpenMutationUITestEvidence
    ) {
        requestedGeneration = readyEvidence.requestGeneration
        center.postNotificationName(
            route.triggerNotificationName,
            object: nil,
            userInfo: [
                UserInfoKey.requestGeneration:
                    NSNumber(value: readyEvidence.requestGeneration),
                UserInfoKey.bundleIdentifier:
                    readyEvidence.bundleIdentifier,
                UserInfoKey.processIdentifier:
                    NSNumber(value: readyEvidence.processIdentifier),
                UserInfoKey.targetWindowPlanIndex:
                    NSNumber(value: readyEvidence.targetWindowPlanIndex)
            ],
            deliverImmediately: true
        )
    }

    func waitForApplied(
        requestGeneration: Int,
        timeout: TimeInterval
    ) -> SpaceFixtureWindowOpenMutationUITestEvidence? {
        wait(
            for: appliedExpectation,
            phase: .applied,
            requestGeneration: requestGeneration,
            timeout: timeout
        )
    }

    var diagnosticSummary: String {
        evidence.isEmpty
            ? "unobserved"
            : evidence.map(\.diagnosticSummary)
                .joined(separator: " | ")
    }

    func cancel() {
        guard let observationToken else { return }
        center.removeObserver(observationToken)
        self.observationToken = nil
    }

    deinit {
        cancel()
    }

    private func observe(_ notification: Notification) {
        guard let evidence = Self.evidence(from: notification),
              !self.evidence.contains(evidence)
        else {
            return
        }
        self.evidence.append(evidence)
        switch evidence.phase {
        case .ready:
            readyExpectation.fulfill()
        case .applied:
            guard requestedGeneration
                    == evidence.requestGeneration
            else {
                return
            }
            appliedExpectation.fulfill()
        }
    }

    private func wait(
        for expectation: XCTestExpectation,
        phase: SpaceFixtureWindowOpenMutationUITestPhase,
        requestGeneration: Int?,
        timeout: TimeInterval
    ) -> SpaceFixtureWindowOpenMutationUITestEvidence? {
        if let match = matchingEvidence(
            phase: phase,
            requestGeneration: requestGeneration
        ) {
            return match
        }
        guard XCTWaiter.wait(
            for: [expectation],
            timeout: timeout
        ) == .completed
        else {
            return nil
        }
        return matchingEvidence(
            phase: phase,
            requestGeneration: requestGeneration
        )
    }

    private func matchingEvidence(
        phase: SpaceFixtureWindowOpenMutationUITestPhase,
        requestGeneration: Int?
    ) -> SpaceFixtureWindowOpenMutationUITestEvidence? {
        evidence.last {
            $0.phase == phase
                && (
                    requestGeneration == nil
                        || $0.requestGeneration
                            == requestGeneration
                )
        }
    }

    private static func evidence(
        from notification: Notification
    ) -> SpaceFixtureWindowOpenMutationUITestEvidence? {
        guard let userInfo = notification.userInfo,
              let requestGeneration = positiveInt(
                userInfo[UserInfoKey.requestGeneration]
              ),
              let phaseValue = userInfo[UserInfoKey.phase] as? String,
              let phase = SpaceFixtureWindowOpenMutationUITestPhase(
                rawValue: phaseValue
              ),
              let bundleIdentifier =
                userInfo[UserInfoKey.bundleIdentifier] as? String,
              !bundleIdentifier.isEmpty,
              let processIdentifier = (
                userInfo[UserInfoKey.processIdentifier] as? NSNumber
              )?.int32Value,
              processIdentifier > 0,
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
        return SpaceFixtureWindowOpenMutationUITestEvidence(
            requestGeneration: requestGeneration,
            phase: phase,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            targetWindowPlanIndex: targetWindowPlanIndex,
            targetWindowTitle: targetWindowTitle,
            activeWindowPlanIndices: activeWindowPlanIndices
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

extension FlowTabUITests {
    func makeSpaceFixtureWindowOpenMutationRoute()
        -> SpaceFixtureWindowOpenMutationUITestRoute
    {
        let token = UUID().uuidString
        return SpaceFixtureWindowOpenMutationUITestRoute(
            evidenceNotificationName: Notification.Name(
                "io.github.potato-dumplings.flowtab."
                    + "ui-test.window-open.evidence.\(token)"
            ),
            triggerNotificationName: Notification.Name(
                "io.github.potato-dumplings.flowtab."
                    + "ui-test.window-open.trigger.\(token)"
            )
        )
    }
}
