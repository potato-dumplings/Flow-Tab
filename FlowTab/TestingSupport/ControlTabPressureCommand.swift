#if FLOWTAB_TESTING
import Foundation

struct ControlTabPressureCommandEnvelope: Equatable, Sendable {
    enum UserInfoKey {
        static let sequence = "sequence"
        static let action = "action"
    }

    let sequence: UInt64
    let action: ControlTabPressureCommandAction

    init?(notification: Notification) {
        guard let sequence = (
                notification.userInfo?[UserInfoKey.sequence]
                    as? NSNumber
              )?.uint64Value,
              sequence > 0,
              let rawAction = notification.userInfo?[
                UserInfoKey.action
              ] as? String,
              let action = ControlTabPressureCommandAction(
                rawValue: rawAction
              )
        else {
            return nil
        }
        self.sequence = sequence
        self.action = action
    }
}

struct ControlTabPressureCommandSequenceGate {
    private(set) var lastAcceptedSequence: UInt64 = 0

    mutating func accept(_ sequence: UInt64) -> Bool {
        guard sequence > lastAcceptedSequence else {
            return false
        }
        lastAcceptedSequence = sequence
        return true
    }

    mutating func reset() {
        lastAcceptedSequence = 0
    }
}

struct ControlTabPressureRoute: Equatable {
    static let commandEnvironmentKey =
        "FLOWTAB_CONTROL_TAB_COMMAND_NOTIFICATION"
    static let commandAcknowledgementEnvironmentKey =
        "FLOWTAB_CONTROL_TAB_COMMAND_ACK_NOTIFICATION"
    static let evidenceEnvironmentKey =
        "FLOWTAB_CONTROL_TAB_EVIDENCE_NOTIFICATION"
    static let evidenceAcknowledgementEnvironmentKey =
        "FLOWTAB_CONTROL_TAB_EVIDENCE_ACK_NOTIFICATION"

    let commandNotificationName: Notification.Name
    let commandAcknowledgementNotificationName: Notification.Name
    let evidenceNotificationName: Notification.Name
    let evidenceAcknowledgementNotificationName:
        Notification.Name

    init?(environment: [String: String]) {
        guard let command = Self.value(
                Self.commandEnvironmentKey,
                in: environment
              ),
              let commandAcknowledgement = Self.value(
                Self.commandAcknowledgementEnvironmentKey,
                in: environment
              ),
              let evidence = Self.value(
                Self.evidenceEnvironmentKey,
                in: environment
              ),
              let evidenceAcknowledgement = Self.value(
                Self.evidenceAcknowledgementEnvironmentKey,
                in: environment
              )
        else {
            return nil
        }
        commandNotificationName = Notification.Name(command)
        commandAcknowledgementNotificationName =
            Notification.Name(commandAcknowledgement)
        evidenceNotificationName = Notification.Name(evidence)
        evidenceAcknowledgementNotificationName =
            Notification.Name(evidenceAcknowledgement)
    }

    private static func value(
        _ key: String,
        in environment: [String: String]
    ) -> String? {
        guard let value = environment[key]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

@MainActor
final class ControlTabPressureCommandObserver {
    typealias Handler = @MainActor (
        ControlTabPressureCommandAction,
        UInt64
    ) -> Void

    private let route: ControlTabPressureRoute
    private let center: DistributedNotificationCenter
    private let handler: Handler
    private var sequenceGate =
        ControlTabPressureCommandSequenceGate()
    private var token: NSObjectProtocol?

    init(
        route: ControlTabPressureRoute,
        center: DistributedNotificationCenter = .default(),
        handler: @escaping Handler
    ) {
        self.route = route
        self.center = center
        self.handler = handler
    }

    func install() {
        uninstall()
        sequenceGate.reset()
        token = center.addObserver(
            forName: route.commandNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.receive(notification)
            }
        }
    }

    func uninstall() {
        if let token {
            center.removeObserver(token)
            self.token = nil
        }
    }

    private func receive(_ notification: Notification) {
        guard let envelope =
                ControlTabPressureCommandEnvelope(
                    notification: notification
                )
        else {
            return
        }
        let accepted = sequenceGate.accept(envelope.sequence)
        acknowledge(
            sequence: envelope.sequence,
            accepted: accepted
        )
        guard accepted else { return }
        handler(envelope.action, envelope.sequence)
    }

    private func acknowledge(
        sequence: UInt64,
        accepted: Bool
    ) {
        center.postNotificationName(
            route.commandAcknowledgementNotificationName,
            object: nil,
            userInfo: [
                ControlTabPressureCommandEnvelope.UserInfoKey
                    .sequence:
                    NSNumber(value: sequence),
                "accepted": NSNumber(value: accepted)
            ],
            deliverImmediately: true
        )
    }

    deinit {
        if let token {
            center.removeObserver(token)
        }
    }
}
#endif
