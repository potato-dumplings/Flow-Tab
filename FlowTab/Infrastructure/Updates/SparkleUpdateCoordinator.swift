import Foundation
import Sparkle

@MainActor
protocol FlowTabStandardUpdaterControlling: AnyObject {
    func startUpdater()
    func checkForUpdates(_ sender: Any?)
}

extension SPUStandardUpdaterController: FlowTabStandardUpdaterControlling {}

@MainActor
final class SparkleUpdateCoordinator: NSObject, FlowTabUpdateCoordinating {
    typealias ControllerFactory = @MainActor (
        any SPUUpdaterDelegate,
        any SPUStandardUserDriverDelegate
    ) -> any FlowTabStandardUpdaterControlling

    static let shared = SparkleUpdateCoordinator()

    private let presentationStore: FlowTabUpdatePresentationStore
    private let displayVersionProvider: () -> String
    private let controllerFactory: ControllerFactory
    private var hasStarted = false

    private lazy var updaterController: any FlowTabStandardUpdaterControlling =
        controllerFactory(self, self)

    init(
        presentationStore: FlowTabUpdatePresentationStore? = nil,
        displayVersionProvider: @escaping () -> String = {
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? ""
        },
        controllerFactory: @escaping ControllerFactory = {
            updaterDelegate,
            userDriverDelegate in
            SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: updaterDelegate,
                userDriverDelegate: userDriverDelegate
            )
        }
    ) {
        self.presentationStore = presentationStore ?? .shared
        self.displayVersionProvider = displayVersionProvider
        self.controllerFactory = controllerFactory
        super.init()
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        presentationStore.configurePresentationAction { [weak self] in
            self?.checkForUpdates()
        }
        updaterController.startUpdater()
    }

    func checkForUpdates() {
        startIfNeeded()
        updaterController.checkForUpdates(nil)
    }

    private func publish(_ update: SUAppcastItem) {
        presentationStore.apply(
            .updateFound(
                FlowTabAvailableUpdate(
                    displayVersion: update.displayVersionString,
                    buildVersion: update.versionString
                )
            )
        )
    }
}

extension SparkleUpdateCoordinator: SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        FlowTabUpdateChannelPolicy.allowedChannels(
            for: displayVersionProvider()
        )
    }

    func updater(
        _ updater: SPUUpdater,
        didFindValidUpdate item: SUAppcastItem
    ) {
        publish(item)
    }

    func updaterDidNotFindUpdate(
        _ updater: SPUUpdater,
        error: any Error
    ) {
        presentationStore.apply(.currentVersionIsLatest)
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        switch choice {
        case .skip:
            presentationStore.apply(.userSkipped)
        case .install:
            presentationStore.apply(.installConfirmed)
        case .dismiss:
            presentationStore.apply(.userDismissed)
        @unknown default:
            presentationStore.apply(.transientFailure)
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        presentationStore.apply(.transientFailure)
    }
}

extension SparkleUpdateCoordinator: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        publish(update)
    }
}
