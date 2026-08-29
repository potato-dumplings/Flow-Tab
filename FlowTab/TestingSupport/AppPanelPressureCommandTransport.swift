#if FLOWTAB_TESTING
import Foundation

enum AppPanelPressureCommandAction: String, Equatable, Sendable {
    case openGlobal
    case openSearch
    case advanceDown
    case advanceRight
    case searchQuery
    case cancel
}

struct AppPanelPressureCommandEnvelope: Equatable, Sendable {
    enum UserInfoKey {
        static let sequence = "sequence"
        static let action = "action"
    }

    let sequence: UInt64
    let action: AppPanelPressureCommandAction

    init?(notification: Notification) {
        guard
            let sequence = (
                notification.userInfo?[UserInfoKey.sequence]
                    as? NSNumber
            )?.uint64Value,
            sequence > 0,
            let rawAction = notification.userInfo?[
                UserInfoKey.action
            ] as? String,
            let action = AppPanelPressureCommandAction(
                rawValue: rawAction
            )
        else {
            return nil
        }
        self.sequence = sequence
        self.action = action
    }
}

struct AppPanelPressureCommandSequenceGate {
    private(set) var lastAcceptedSequence: UInt64 = 0

    mutating func accept(_ sequence: UInt64) -> Bool {
        guard sequence > lastAcceptedSequence else {
            return false
        }
        lastAcceptedSequence = sequence
        return true
    }
}

@MainActor
final class AppPanelPressureCommandObserver {
    typealias Handler = @MainActor (
        AppPanelPressureCommandAction,
        UInt64,
        UInt64
    ) -> Void

    private let notificationName: Notification.Name
    private let acknowledgementNotificationName:
        Notification.Name
    private let center: DistributedNotificationCenter
    private let handler: Handler
    private var sequenceGate =
        AppPanelPressureCommandSequenceGate()
    private var token: NSObjectProtocol?

    init(
        notificationName: Notification.Name,
        acknowledgementNotificationName:
            Notification.Name,
        center: DistributedNotificationCenter = .default(),
        handler: @escaping Handler
    ) {
        self.notificationName = notificationName
        self.acknowledgementNotificationName =
            acknowledgementNotificationName
        self.center = center
        self.handler = handler
    }

    func install() {
        uninstall()
        token = center.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let receivedAtNanoseconds =
                DispatchTime.now().uptimeNanoseconds
            MainActor.assumeIsolated {
                self?.receive(
                    notification,
                    receivedAtNanoseconds:
                        receivedAtNanoseconds
                )
            }
        }
    }

    func uninstall() {
        if let token {
            center.removeObserver(token)
            self.token = nil
        }
    }

    deinit {
        if let token {
            center.removeObserver(token)
        }
    }

    private func receive(
        _ notification: Notification,
        receivedAtNanoseconds: UInt64
    ) {
        guard
            let envelope = AppPanelPressureCommandEnvelope(
                notification: notification
            )
        else {
            RuntimeLog.info(
                "UITest",
                "ignored invalid app-panel pressure command"
            )
            return
        }
        let accepted = sequenceGate.accept(envelope.sequence)
        guard accepted else {
            publishAcknowledgement(envelope)
            return
        }
        handler(
            envelope.action,
            envelope.sequence,
            receivedAtNanoseconds
        )
        publishAcknowledgement(envelope)
    }

    private func publishAcknowledgement(
        _ envelope: AppPanelPressureCommandEnvelope
    ) {
        center.postNotificationName(
            acknowledgementNotificationName,
            object: nil,
            userInfo: [
                AppPanelPressureCommandEnvelope
                    .UserInfoKey.sequence:
                    NSNumber(value: envelope.sequence),
                AppPanelPressureCommandEnvelope
                    .UserInfoKey.action:
                    envelope.action.rawValue
            ],
            deliverImmediately: true
        )
    }
}
#endif
