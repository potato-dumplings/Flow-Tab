import Darwin
import Foundation

@MainActor
private final class SpaceFixtureDistributedObservationToken:
    SpaceFixtureCancellable
{
    private let center: DistributedNotificationCenter
    private var token: NSObjectProtocol?

    init(
        center: DistributedNotificationCenter,
        token: NSObjectProtocol
    ) {
        self.center = center
        self.token = token
    }

    func cancel() {
        guard let token else { return }
        center.removeObserver(token)
        self.token = nil
    }

    deinit {
        if let token {
            center.removeObserver(token)
        }
    }
}

enum SpaceFixtureProjectionAcknowledgementTransport {
    private enum UserInfoKey {
        static let acknowledgementGeneration =
            "acknowledgementGeneration"
        static let bundleIdentifier = "bundleIdentifier"
        static let processIdentifier = "processIdentifier"
        static let windowCount = "windowCount"
        static let sourceGeneration = "sourceGeneration"
    }

    @MainActor
    static func observe(
        notificationName: Notification.Name,
        handler:
            @escaping @MainActor (
                SpaceFixtureProjectionAcknowledgement
            ) -> Void
    ) -> any SpaceFixtureCancellable {
        let center = DistributedNotificationCenter.default()
        let token = center.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { notification in
            guard let acknowledgement = acknowledgement(
                from: notification
            )
            else {
                return
            }
            MainActor.assumeIsolated {
                handler(acknowledgement)
            }
        }
        return SpaceFixtureDistributedObservationToken(
            center: center,
            token: token
        )
    }

    static func acknowledgement(
        from notification: Notification
    ) -> SpaceFixtureProjectionAcknowledgement? {
        guard let userInfo = notification.userInfo,
              let acknowledgementGeneration = (
                userInfo[
                    UserInfoKey.acknowledgementGeneration
                ] as? NSNumber
              )?.uint64Value,
              acknowledgementGeneration > 0,
              let bundleIdentifier =
                userInfo[
                    UserInfoKey.bundleIdentifier
                ] as? String,
              !bundleIdentifier.isEmpty,
              let processIdentifierNumber =
                userInfo[
                    UserInfoKey.processIdentifier
                ] as? NSNumber,
              processIdentifierNumber.int32Value > 0,
              let windowCountNumber =
                userInfo[
                    UserInfoKey.windowCount
                ] as? NSNumber,
              windowCountNumber.intValue > 0,
              let sourceGeneration =
                userInfo[
                    UserInfoKey.sourceGeneration
                ] as? String,
              !sourceGeneration.isEmpty
        else {
            return nil
        }
        return SpaceFixtureProjectionAcknowledgement(
            acknowledgementGeneration:
                acknowledgementGeneration,
            bundleIdentifier: bundleIdentifier,
            processIdentifier:
                processIdentifierNumber.int32Value,
            windowCount: windowCountNumber.intValue,
            sourceGeneration: sourceGeneration
        )
    }
}

enum SpaceFixtureApplicationAXSuppressionTransport {
    enum UserInfoKey {
        static let observationGeneration =
            "observationGeneration"
        static let suppressionGeneration =
            "suppressionGeneration"
        static let acknowledgementGeneration =
            "acknowledgementGeneration"
        static let bundleIdentifier = "bundleIdentifier"
        static let processIdentifier = "processIdentifier"
        static let windowCount = "windowCount"
        static let sourceGeneration = "sourceGeneration"
        static let childWindowCount = "childWindowCount"
        static let windowsAttributeCount =
            "windowsAttributeCount"
    }

    @MainActor
    static func post(
        _ completion:
            SpaceFixtureApplicationAXSuppressionCompletion,
        notificationName: Notification.Name
    ) {
        DistributedNotificationCenter.default()
            .postNotificationName(
                notificationName,
                object: nil,
                userInfo: [
                    UserInfoKey.observationGeneration:
                        NSNumber(
                            value:
                                completion
                                    .observationGeneration
                        ),
                    UserInfoKey.suppressionGeneration:
                        NSNumber(
                            value:
                                completion
                                    .suppressionGeneration
                        ),
                    UserInfoKey.acknowledgementGeneration:
                        NSNumber(
                            value:
                                completion
                                    .acknowledgement
                                    .acknowledgementGeneration
                        ),
                    UserInfoKey.bundleIdentifier:
                        completion.identity.bundleIdentifier,
                    UserInfoKey.processIdentifier:
                        NSNumber(
                            value:
                                completion.identity
                                    .processIdentifier
                        ),
                    UserInfoKey.windowCount:
                        NSNumber(
                            value:
                                completion
                                    .expectedProjectionWindowCount
                        ),
                    UserInfoKey.sourceGeneration:
                        completion.acknowledgement
                            .sourceGeneration,
                    UserInfoKey.childWindowCount:
                        NSNumber(
                            value:
                                completion.exposure
                                    .childWindowCount
                        ),
                    UserInfoKey.windowsAttributeCount:
                        NSNumber(
                            value:
                                completion.exposure
                                    .windowsAttributeCount
                        )
                ],
                deliverImmediately: true
            )
        NSLog(
            "SpaceFixture AX suppression generation=%llu bundleID=%@ pid=%d projectionWindows=%d sourceGeneration=%@",
            completion.suppressionGeneration,
            completion.identity.bundleIdentifier,
            completion.identity.processIdentifier,
            completion.expectedProjectionWindowCount,
            completion.acknowledgement.sourceGeneration
        )
    }
}
