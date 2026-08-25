#if FLOWTAB_TESTING
import Foundation

struct FlowTabUITestUpdateRoute: Equatable {
    let availableUpdate: FlowTabAvailableUpdate
    let notificationName: Notification.Name
    let readbackURL: URL
}

struct FlowTabUITestUpdateActionEvidence: Codable, Equatable {
    let displayVersion: String
    let buildVersion: String
    let requestGeneration: UInt64
}

@MainActor
final class FlowTabUITestUpdateCoordinator: FlowTabUpdateCoordinating {
    static let shared = FlowTabUITestUpdateCoordinator()

    private let presentationStore: FlowTabUpdatePresentationStore
    private var hasStarted = false
    private var requestGeneration: UInt64 = 0

    init(
        presentationStore: FlowTabUpdatePresentationStore? = nil
    ) {
        self.presentationStore = presentationStore ?? .shared
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        presentationStore.configurePresentationAction { [weak self] in
            self?.checkForUpdates()
        }

        guard let route = FlowTabTestLaunchOptions.updateRoute else {
            presentationStore.apply(.currentVersionIsLatest)
            return
        }
        presentationStore.apply(.updateFound(route.availableUpdate))
    }

    func checkForUpdates() {
        guard let route = FlowTabTestLaunchOptions.updateRoute else {
            return
        }
        requestGeneration &+= 1
        let evidence = FlowTabUITestUpdateActionEvidence(
            displayVersion: route.availableUpdate.displayVersion,
            buildVersion: route.availableUpdate.buildVersion,
            requestGeneration: requestGeneration
        )

        do {
            let data = try JSONEncoder().encode(evidence)
            try data.write(to: route.readbackURL, options: .atomic)
        } catch {
            RuntimeLog.error(
                "UITest",
                "update action readback failed error=\(error)"
            )
            return
        }

        DistributedNotificationCenter.default().postNotificationName(
            route.notificationName,
            object: nil,
            userInfo: [
                "displayVersion": evidence.displayVersion,
                "buildVersion": evidence.buildVersion,
                "requestGeneration": NSNumber(
                    value: evidence.requestGeneration
                )
            ],
            deliverImmediately: true
        )
    }
}
#endif
