import AppKit
import Foundation
import XCTest

enum FlowTabUITestHomeWindowRecencyFlowTabActivationPolicy {
    static let foregroundActivationWatchdog: TimeInterval = 10
}

struct FlowTabUITestFlowTabForegroundSnapshot: Equatable {
    let frontmostBundleIdentifier: String?
    let applicationState: XCUIApplication.State

    func matches(bundleIdentifier: String) -> Bool {
        frontmostBundleIdentifier == bundleIdentifier
            && applicationState == .runningForeground
    }

    var diagnosticSummary: String {
        "frontmostBundle=\(frontmostBundleIdentifier ?? "nil") "
            + "applicationState=\(String(describing: applicationState))"
    }
}

private enum FlowTabUITestFlowTabForegroundPhase: String {
    case initialReadback
    case awaitingActivation
    case activationCompleted
}

private final class FlowTabUITestFlowTabForegroundState {
    var phase: FlowTabUITestFlowTabForegroundPhase = .initialReadback

    var acceptsEvidence: Bool {
        phase == .activationCompleted
    }
}

enum FlowTabUITestFlowTabForegroundObservation {
    static func workspaceActivationRegistration(
        notificationCenter: NotificationCenter =
            NSWorkspace.shared.notificationCenter,
        notificationName: Notification.Name =
            NSWorkspace.didActivateApplicationNotification
    ) -> FlowTabUITestConditionObservationRegistration {
        { readback in
            let token = notificationCenter.addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { _ in
                readback(.notificationReadback)
            }
            return FlowTabUITestObservationCancellation {
                notificationCenter.removeObserver(token)
            }
        }
    }
}

final class FlowTabUITestFlowTabForegroundObservationOwner {
    private let state: FlowTabUITestFlowTabForegroundState
    private let deferredReadbacks:
        FlowTabUITestDeferredConditionReadbackRegistration
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestFlowTabForegroundSnapshot
        >

    init(
        expectedBundleIdentifier: String,
        activationRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                FlowTabUITestFlowTabForegroundObservation
                    .workspaceActivationRegistration(),
        scheduledRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () -> FlowTabUITestFlowTabForegroundSnapshot
    ) {
        let state = FlowTabUITestFlowTabForegroundState()
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration: scheduledRegistration
            )
        self.state = state
        self.deferredReadbacks = deferredReadbacks
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: { callback in
                let activationCancellation =
                    activationRegistration { source in
                        guard state.acceptsEvidence else { return }
                        callback(source)
                    }
                let scheduledCancellation =
                    deferredReadbacks.register(callback)
                return FlowTabUITestObservationCancellation {
                    activationCancellation?.cancel()
                    scheduledCancellation?.cancel()
                }
            },
            readback: readback,
            isSatisfied: { snapshot in
                state.acceptsEvidence
                    && snapshot.matches(
                        bundleIdentifier: expectedBundleIdentifier
                    )
            },
            describe: { snapshot in
                "expectedBundle=\(expectedBundleIdentifier) "
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        state.phase = .initialReadback
        conditionOwner.start()
        state.phase = .awaitingActivation
    }

    func markActivationCompleted() {
        guard conditionOwner.resolvedEvidence == nil else { return }
        state.phase = .activationCompleted
        conditionOwner.requestReadback(source: .triggerReadback)
        if conditionOwner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestFlowTabForegroundSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestFlowTabForegroundSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestFlowTabForegroundSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        "phase=\(state.phase.rawValue) "
            + conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    @discardableResult
    func activateFlowTabAfterHomeWindowRecencyTargetActivation(
        _ app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let bundleIdentifier =
            FlowTabUITestAppIdentity.configured().bundleIdentifier
        let observation =
            FlowTabUITestFlowTabForegroundObservationOwner(
                expectedBundleIdentifier: bundleIdentifier,
                readback: {
                    FlowTabUITestFlowTabForegroundSnapshot(
                        frontmostBundleIdentifier:
                            NSWorkspace.shared
                                .frontmostApplication?
                                .bundleIdentifier,
                        applicationState: app.state
                    )
                }
            )
        observation.start()
        defer { observation.cancel() }

        guard let initialEvidence = observation.latestEvidence,
              initialEvidence.source == .initialReadback,
              !initialEvidence.value.matches(
                  bundleIdentifier: bundleIdentifier
              )
        else {
            XCTFail(
                "Home recency FlowTab activation did not establish "
                    + "its non-foreground baseline. "
                    + "target=\(targetDescription) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return false
        }

        app.activate()
        observation.markActivationCompleted()

        guard observation.waitForResolution(
            timeout:
                FlowTabUITestHomeWindowRecencyFlowTabActivationPolicy
                    .foregroundActivationWatchdog
        ) != nil else {
            XCTFail(
                "Home recency FlowTab foreground activation watchdog "
                    + "expired. target=\(targetDescription) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return false
        }
        return true
    }
}
