import Foundation
import XCTest

enum FlowTabUITestSidebarTabProjectionTarget: String, CaseIterable {
    case home
    case logs
    case settings

    var buttonIdentifier: String {
        switch self {
        case .home:
            return FlowTabUITests.Identifier.homeTabButton
        case .logs:
            return FlowTabUITests.Identifier.logsTabButton
        case .settings:
            return FlowTabUITests.Identifier.settingsTabButton
        }
    }

    var contentIdentifier: String {
        switch self {
        case .home:
            return FlowTabUITests.Identifier.homeTabContent
        case .logs:
            return FlowTabUITests.Identifier.logsTabContent
        case .settings:
            return FlowTabUITests.Identifier.settingsTabContent
        }
    }
}

struct FlowTabUITestSidebarTabProjectionSnapshot: Equatable {
    let applicationState: XCUIApplication.State
    let homeContentExists: Bool
    let logsContentExists: Bool
    let settingsContentExists: Bool

    func contentExists(
        for target: FlowTabUITestSidebarTabProjectionTarget
    ) -> Bool {
        switch target {
        case .home:
            return homeContentExists
        case .logs:
            return logsContentExists
        case .settings:
            return settingsContentExists
        }
    }

    var visibleTargets: [FlowTabUITestSidebarTabProjectionTarget] {
        FlowTabUITestSidebarTabProjectionTarget.allCases.filter {
            contentExists(for: $0)
        }
    }

    var diagnosticSummary: String {
        let visibleTargetDescription = visibleTargets
            .map(\.rawValue)
            .joined(separator: ",")
        return "applicationState=\(String(describing: applicationState)) "
            + "homeContentExists=\(homeContentExists) "
            + "logsContentExists=\(logsContentExists) "
            + "settingsContentExists=\(settingsContentExists) "
            + "visibleTargets=[\(visibleTargetDescription)]"
    }
}

struct FlowTabUITestSidebarTabProjectionExpectation: Equatable {
    let target: FlowTabUITestSidebarTabProjectionTarget

    func isSatisfied(
        by snapshot: FlowTabUITestSidebarTabProjectionSnapshot
    ) -> Bool {
        snapshot.applicationState == .runningForeground
            && snapshot.visibleTargets == [target]
    }
}

final class FlowTabUITestSidebarTabProjectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSidebarTabProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestSidebarTabProjectionExpectation,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        acceptsResolution: @escaping () -> Bool = { true },
        readback: @escaping () ->
            FlowTabUITestSidebarTabProjectionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                acceptsResolution()
                    && expectation.isSatisfied(by: $0)
            },
            describe: { snapshot in
                "target=\(expectation.target.rawValue) "
                    + "acceptsResolution=\(acceptsResolution()) "
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestSidebarTabProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSidebarTabProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSidebarTabProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func requestReadback(
        source: FlowTabUITestConditionObservationSource
    ) {
        conditionOwner.requestReadback(source: source)
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

private struct FlowTabUITestSidebarTabProjectionElements {
    let homeContent: XCUIElement
    let logsContent: XCUIElement
    let settingsContent: XCUIElement
}

extension FlowTabUITests {
    @discardableResult
    func assertSidebarTabProjectionAfterNavigation(
        in app: XCUIApplication,
        target: FlowTabUITestSidebarTabProjectionTarget,
        triggerWatchdog: TimeInterval =
            FlowTabUITestSupportWatchdogPolicy.tabNavigation,
        projectionWatchdog: TimeInterval =
            FlowTabUITestSupportWatchdogPolicy.tabNavigation
    ) -> Bool {
        let elements = sidebarTabProjectionElements(in: app)
        let readback = sidebarTabProjectionReadback(
            in: app,
            elements: elements
        )
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration:
                    FlowTabUITestConditionReadbackScheduler
                        .mainRunLoopRegistration(
                            cadence:
                                FlowTabUITestConditionObservationPolicy
                                    .xcuiReadbackCadence
                        )
            )
        var triggerDidComplete = false
        let owner =
            FlowTabUITestSidebarTabProjectionObservationOwner(
                expectation: .init(target: target),
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                acceptsResolution: { triggerDidComplete },
                readback: readback
            )
        owner.start()
        defer {
            owner.cancel()
            deferredReadbacks.cancel()
        }

        guard owner.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "Sidebar tab initial readback was unavailable. "
                    + owner.diagnosticSummary
            )
            return false
        }
        XCTAssertNil(owner.resolvedEvidence)

        let tabQuery = app.buttons.matching(
            identifier: target.buttonIdentifier
        )
        let triggerSucceeded = tapFirstHittable(
            in: tabQuery,
            timeout: triggerWatchdog
        )
        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        guard triggerSucceeded else {
            XCTFail(
                "Sidebar tab navigation trigger watchdog expired. "
                    + "finalCandidateCount=\(tabQuery.count) "
                    + owner.diagnosticSummary
            )
            return false
        }
        if owner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }

        guard owner.waitForResolution(
            timeout: projectionWatchdog
        ) != nil else {
            XCTFail(
                "Sidebar tab projection watchdog expired. "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    private func sidebarTabProjectionElements(
        in app: XCUIApplication
    ) -> FlowTabUITestSidebarTabProjectionElements {
        FlowTabUITestSidebarTabProjectionElements(
            homeContent: element(
                in: app,
                identifier: Identifier.homeTabContent
            ),
            logsContent: element(
                in: app,
                identifier: Identifier.logsTabContent
            ),
            settingsContent: element(
                in: app,
                identifier: Identifier.settingsTabContent
            )
        )
    }

    private func sidebarTabProjectionReadback(
        in app: XCUIApplication,
        elements: FlowTabUITestSidebarTabProjectionElements
    ) -> () -> FlowTabUITestSidebarTabProjectionSnapshot {
        {
            let applicationState = app.state
            guard applicationState == .runningForeground else {
                return FlowTabUITestSidebarTabProjectionSnapshot(
                    applicationState: applicationState,
                    homeContentExists: false,
                    logsContentExists: false,
                    settingsContentExists: false
                )
            }
            return FlowTabUITestSidebarTabProjectionSnapshot(
                applicationState: applicationState,
                homeContentExists: elements.homeContent.exists,
                logsContentExists: elements.logsContent.exists,
                settingsContentExists: elements.settingsContent.exists
            )
        }
    }
}
