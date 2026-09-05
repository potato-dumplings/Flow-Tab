#if FLOWTAB_TESTING
import Foundation

@MainActor
final class ControlTabPressureEvidenceDelivery {
    private struct PendingDelivery {
        let timer: DispatchSourceTimer
    }

    private let route: ControlTabPressureRoute
    private let center: DistributedNotificationCenter
    private let deliveryQueue = DispatchQueue(
        label: "FlowTab.ControlTabPressureEvidence",
        qos: .utility
    )
    private var acknowledgementToken: NSObjectProtocol?
    private var pending: [UInt64: PendingDelivery] = [:]

    init(
        route: ControlTabPressureRoute,
        center: DistributedNotificationCenter = .default()
    ) {
        self.route = route
        self.center = center
        acknowledgementToken = center.addObserver(
            forName:
                route.evidenceAcknowledgementNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let sequence = (
                notification.userInfo?["sequence"]
                    as? NSNumber
            )?.uint64Value else {
                return
            }
            MainActor.assumeIsolated {
                self?.acknowledge(sequence: sequence)
            }
        }
    }

    func publish(_ evidence: ControlTabPressureEvidence) {
        let userInfo = Self.userInfo(evidence)
        pending.removeValue(forKey: evidence.sequence)?
            .timer.cancel()
        post(userInfo)

        let deadline =
            ProcessInfo.processInfo.systemUptime + 5
        let timer = DispatchSource.makeTimerSource(
            queue: deliveryQueue
        )
        timer.schedule(
            deadline: .now() + .milliseconds(50),
            repeating: .milliseconds(50)
        )
        timer.setEventHandler { [weak self, weak timer] in
            guard let self, let timer else { return }
            guard ProcessInfo.processInfo.systemUptime < deadline
            else {
                timer.cancel()
                Task { @MainActor [weak self] in
                    self?.expire(sequence: evidence.sequence)
                }
                return
            }
            self.center.postNotificationName(
                self.route.evidenceNotificationName,
                object: nil,
                userInfo: userInfo,
                deliverImmediately: true
            )
        }
        pending[evidence.sequence] = PendingDelivery(
            timer: timer
        )
        timer.resume()
    }

    func cancel() {
        for delivery in pending.values {
            delivery.timer.cancel()
        }
        pending.removeAll()
        if let acknowledgementToken {
            center.removeObserver(acknowledgementToken)
            self.acknowledgementToken = nil
        }
    }

    private func acknowledge(sequence: UInt64) {
        pending.removeValue(forKey: sequence)?.timer.cancel()
    }

    private func expire(sequence: UInt64) {
        pending.removeValue(forKey: sequence)?.timer.cancel()
    }

    private func post(_ userInfo: [String: Any]) {
        center.postNotificationName(
            route.evidenceNotificationName,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    private static func userInfo(
        _ evidence: ControlTabPressureEvidence
    ) -> [String: Any] {
        [
            "sequence": NSNumber(value: evidence.sequence),
            "phase": evidence.phase.rawValue,
            "startedAtNanoseconds": NSNumber(
                value: evidence.startedAtNanoseconds
            ),
            "completedAtNanoseconds": NSNumber(
                value: evidence.completedAtNanoseconds
            ),
            "wallMilliseconds": NSNumber(
                value: evidence.duration.wallMilliseconds
            ),
            "cpuTimeMilliseconds": NSNumber(
                value: evidence.duration.cpuTimeMilliseconds
            ),
            "cpuPercent": NSNumber(
                value: evidence.duration.cpuPercent
            ),
            "timingValid": NSNumber(
                value: evidence.timingValid
            ),
            "satisfied": NSNumber(value: evidence.satisfied),
            "panelPresented": NSNumber(
                value: evidence.panelPresented
            ),
            "userVisible": NSNumber(value: evidence.userVisible),
            "selectedAppID": evidence.selectedAppID ?? "none",
            "selectedWindowIDBefore":
                evidence.selectedWindowIDBefore ?? "none",
            "selectedWindowIDAfter":
                evidence.selectedWindowIDAfter ?? "none",
            "projectedAppCount": NSNumber(
                value: evidence.projectedAppCount
            ),
            "selectedWindowCount": NSNumber(
                value: evidence.selectedWindowCount
            ),
            "activationRequestIssued": NSNumber(
                value: evidence.activationRequestIssued
            ),
            "activationVerified": NSNumber(
                value: evidence.activationVerified
            ),
            "activationTargetPID": NSNumber(
                value: evidence.activationTargetPID
            ),
            "activationTargetWindowID":
                evidence.activationTargetWindowID ?? "none",
            "activationTargetCGWindowID": NSNumber(
                value: evidence.activationTargetCGWindowID ?? 0
            ),
            "latePresentationObserved": NSNumber(
                value: evidence.latePresentationObserved
            ),
            "projectionGeneration": NSNumber(
                value: evidence.projectionGeneration
            ),
            "accessibilityTrusted": NSNumber(
                value: evidence.accessibilityTrusted
            ),
            "screenCaptureTrusted": NSNumber(
                value: evidence.screenCaptureTrusted
            ),
            "partitions": evidence.partitions.mapValues {
                NSNumber(value: $0)
            },
            "milestones": evidence.milestones.mapValues {
                NSNumber(value: $0)
            },
            "partitionsReconciled": NSNumber(
                value: evidence.partitionsReconciled
            ),
            "spans": evidence.spans.map(Self.spanUserInfo),
            "requiredComponentsPresent": NSNumber(
                value: evidence.requiredComponentsPresent
            ),
            "timelineReconciled": NSNumber(
                value: evidence.timelineReconciled
            ),
            "componentTimingValid": NSNumber(
                value: evidence.componentTimingValid
            ),
            "watchdogExpired": NSNumber(
                value: evidence.watchdogExpired
            )
        ]
    }

    private static func spanUserInfo(
        _ span: ControlTabPressureSpan
    ) -> [String: Any] {
        [
            "phase": span.phase.rawValue,
            "sequence": NSNumber(value: span.sequence),
            "name": span.name,
            "parent": span.parent ?? "none",
            "startedAtNanoseconds": NSNumber(
                value: span.startedAtNanoseconds
            ),
            "completedAtNanoseconds": NSNumber(
                value: span.completedAtNanoseconds
            ),
            "wallMilliseconds": NSNumber(
                value: span.duration.wallMilliseconds
            ),
            "cpuTimeMilliseconds": NSNumber(
                value: span.duration.cpuTimeMilliseconds
            ),
            "cpuPercent": NSNumber(value: span.duration.cpuPercent),
            "timingValid": NSNumber(value: span.duration.isValid),
            "scope": span.scope.rawValue,
            "outcome": span.outcome,
            "workUnits": NSNumber(value: span.workUnits)
        ]
    }

    deinit {
        for delivery in pending.values {
            delivery.timer.cancel()
        }
        if let acknowledgementToken {
            center.removeObserver(acknowledgementToken)
        }
    }
}
#endif
