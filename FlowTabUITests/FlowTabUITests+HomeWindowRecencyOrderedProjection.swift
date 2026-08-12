import Foundation
import XCTest

enum FlowTabUITestHomeWindowRecencyOrderedProjectionPolicy {
    static let orderedWindowPublicationWatchdog: TimeInterval = 12
}

struct FlowTabUITestHomeWindowRecencyOrderedProjectionExpectation:
    Equatable
{
    static let windowRowIdentifierPrefix = "flowtab.home.window."

    let expectedTitles: [String]
    let targetWindowIdentifier: String

    var hasValidConfiguration: Bool {
        !expectedTitles.isEmpty
            && expectedTitles.allSatisfy { !$0.isEmpty }
            && targetWindowIdentifier.hasPrefix(
                Self.windowRowIdentifierPrefix
            )
    }

    func isSatisfied<Element>(
        by snapshot: FlowTabUITestHomeWindowProjectionSnapshot<Element>
    ) -> Bool {
        guard hasValidConfiguration,
              snapshot.rows.count >= expectedTitles.count
        else {
            return false
        }

        let rows = Array(snapshot.rows.prefix(expectedTitles.count))
        let identifiers = rows.map(\.identifier)
        return rows.map(\.label) == expectedTitles
            && identifiers.first == targetWindowIdentifier
            && Set(identifiers).count == identifiers.count
            && identifiers.allSatisfy {
                $0.hasPrefix(Self.windowRowIdentifierPrefix)
            }
    }

    var diagnosticSummary: String {
        "expectedTitles=\(expectedTitles) "
            + "targetWindowIdentifier=\(targetWindowIdentifier)"
    }
}

private enum
    FlowTabUITestHomeWindowRecencyOrderedProjectionPhase: String
{
    case initialReadback
    case awaitingAppSelection
    case appSelectionCompleted
}

private final class
    FlowTabUITestHomeWindowRecencyOrderedProjectionState
{
    var phase:
        FlowTabUITestHomeWindowRecencyOrderedProjectionPhase =
            .initialReadback

    var acceptsEvidence: Bool {
        phase == .appSelectionCompleted
    }
}

final class
    FlowTabUITestHomeWindowRecencyOrderedProjectionObservationOwner<Element>
{
    private let state:
        FlowTabUITestHomeWindowRecencyOrderedProjectionState
    private let deferredReadbacks:
        FlowTabUITestDeferredConditionReadbackRegistration
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestHomeWindowProjectionSnapshot<Element>
        >

    init(
        expectation:
            FlowTabUITestHomeWindowRecencyOrderedProjectionExpectation,
        scheduledRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestHomeWindowProjectionSnapshot<Element>
    ) {
        let state =
            FlowTabUITestHomeWindowRecencyOrderedProjectionState()
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration: scheduledRegistration
            )
        self.state = state
        self.deferredReadbacks = deferredReadbacks
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: { callback in
                deferredReadbacks.register(callback)
            },
            readback: readback,
            isSatisfied: { snapshot in
                state.acceptsEvidence
                    && expectation.isSatisfied(by: snapshot)
            },
            describe: { snapshot in
                "phase=\(state.phase.rawValue) "
                    + expectation.diagnosticSummary + " "
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        state.phase = .initialReadback
        conditionOwner.start()
        state.phase = .awaitingAppSelection
    }

    func markAppSelectionCompleted() {
        guard conditionOwner.resolvedEvidence == nil else { return }
        state.phase = .appSelectionCompleted
        conditionOwner.requestReadback(source: .triggerReadback)
        if conditionOwner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestHomeWindowProjectionSnapshot<Element>
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestHomeWindowProjectionSnapshot<Element>
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestHomeWindowProjectionSnapshot<Element>
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
        deferredReadbacks.cancel()
    }
}

extension FlowTabUITests {
    @discardableResult
    func waitForHomeWindowRecencyOrderedProjectionAfterSelectingApp(
        _ appRow: XCUIElement,
        appName: String,
        expectedTitles: [String],
        targetWindowIdentifier: String,
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let expectation =
            FlowTabUITestHomeWindowRecencyOrderedProjectionExpectation(
                expectedTitles: expectedTitles,
                targetWindowIdentifier: targetWindowIdentifier
            )
        guard expectation.hasValidConfiguration else {
            XCTFail(
                "Home recency ordered projection has invalid expected "
                    + "window evidence. target=\(targetDescription) "
                    + "app=\(appName) "
                    + expectation.diagnosticSummary,
                file: file,
                line: line
            )
            return false
        }

        let observation =
            FlowTabUITestHomeWindowRecencyOrderedProjectionObservationOwner(
                expectation: expectation,
                readback: {
                    self.homeWindowProjectionSnapshot(
                        in: app,
                        expectation: .rowLabelPrefix(expectedTitles)
                    )
                }
            )
        observation.start()
        defer { observation.cancel() }

        guard observation.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "Home recency ordered projection did not establish its "
                    + "initial readback. target=\(targetDescription) "
                    + "app=\(appName) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return false
        }

        tapElement(appRow)
        observation.markAppSelectionCompleted()

        guard observation.waitForResolution(
            timeout:
                FlowTabUITestHomeWindowRecencyOrderedProjectionPolicy
                    .orderedWindowPublicationWatchdog
        ) != nil else {
            XCTFail(
                "Home recency ordered-window publication watchdog "
                    + "expired. target=\(targetDescription) "
                    + "app=\(appName) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return false
        }
        return true
    }
}
