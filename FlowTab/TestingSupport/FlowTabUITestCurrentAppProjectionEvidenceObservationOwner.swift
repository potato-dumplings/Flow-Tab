#if FLOWTAB_TESTING
import Foundation

final class FlowTabUITestCurrentAppProjectionEvidenceObservationOwner:
    @unchecked Sendable
{
    let route:
        FlowTabUITestCurrentAppProjectionEvidenceRoute

    private let evidencePublisher:
        FlowTabUITestCurrentAppProjectionEvidencePublisher
    private let notificationCenter: NotificationCenter
    private let notificationObject: AnyObject
    private let lock = NSLock()
    private var projectionObserver: NSObjectProtocol?

    init(
        route:
            FlowTabUITestCurrentAppProjectionEvidenceRoute,
        notificationObject: AnyObject,
        evidencePublisher:
            FlowTabUITestCurrentAppProjectionEvidencePublisher? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.route = route
        self.notificationObject = notificationObject
        self.notificationCenter = notificationCenter
        self.evidencePublisher = evidencePublisher
            ?? FlowTabUITestCurrentAppProjectionEvidencePublisher(
                route: route
            )
    }

    var isObserving: Bool {
        lock.lock()
        let isObserving = projectionObserver != nil
        lock.unlock()
        return isObserving
    }

    func observes(notificationObject: AnyObject) -> Bool {
        self.notificationObject === notificationObject
    }

    func start() {
        lock.lock()
        guard projectionObserver == nil else {
            lock.unlock()
            return
        }
        projectionObserver =
            notificationCenter.addObserver(
                forName:
                    .runtimeCurrentAppWindowProjectionDidUpdate,
                object: notificationObject,
                queue: .main
            ) { [weak self] notification in
                self?.observeProjectionUpdate(notification)
            }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let observer = projectionObserver
        projectionObserver = nil
        lock.unlock()
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    deinit {
        cancel()
    }

    private func observeProjectionUpdate(
        _ notification: Notification
    ) {
        guard let update = notification.userInfo?[
            RuntimeProjectionNotificationUserInfoKey
                .currentAppWindowProjectionUpdateEvidence
        ] as? RuntimeCurrentAppWindowProjectionUpdateEvidence
        else {
            return
        }
        evidencePublisher.record(update)
    }
}

@MainActor
enum FlowTabUITestCurrentAppProjectionEvidenceBootstrap {
    private static var installedOwner:
        FlowTabUITestCurrentAppProjectionEvidenceObservationOwner?

    static var installedRouteForTesting:
        FlowTabUITestCurrentAppProjectionEvidenceRoute?
    {
        installedOwner?.route
    }

    static var isObservingForTesting: Bool {
        installedOwner?.isObserving == true
    }

    static func prepareIfNeeded(
        service: any RuntimeProjectionServing
    ) {
        let route = FlowTabTestLaunchOptions
            .currentAppProjectionEvidenceRoute
        let notificationObject = service as AnyObject
        if let route,
           let installedOwner,
           installedOwner.route == route,
           installedOwner.observes(
            notificationObject: notificationObject
           ),
           installedOwner.isObserving
        {
            return
        }

        stop()
        guard let route else { return }

        let owner =
            FlowTabUITestCurrentAppProjectionEvidenceObservationOwner(
                route: route,
                notificationObject: notificationObject
            )
        owner.start()
        installedOwner = owner
    }

    static func stop() {
        installedOwner?.cancel()
        installedOwner = nil
    }
}
#endif
