import Foundation
import FlowTabCore

@MainActor
final class HomeWindowActivationController {
    struct ActivationRequest {
        let target: ActivationTarget
        let contextsByID: [String: RuntimeAppContext]
    }

    static let shared = HomeWindowActivationController()

    private let snapshotService: any RuntimeSnapshotServing
    private let preferencesProvider: () -> SwitcherPreferences
    private let activationHandler: (ActivationTarget, [String: RuntimeAppContext]) -> Void

    init(
        snapshotService: any RuntimeSnapshotServing = sharedRuntimeSnapshotService,
        preferencesProvider: @escaping () -> SwitcherPreferences = {
            SwitcherBehaviorPreferencesStore.loadSwitcherPreferences()
        },
        windowRecencyTracker: RuntimeWindowRecencyTracker = .shared,
        activationHandler: ((ActivationTarget, [String: RuntimeAppContext]) -> Void)? = nil
    ) {
        self.snapshotService = snapshotService
        self.preferencesProvider = preferencesProvider

        if let activationHandler {
            self.activationHandler = activationHandler
        } else {
            let runtimeActivator = RuntimeActivator()
            runtimeActivator.windowFocusVerifiedHandler = { appID, windowID, ownerPID, cgWindowID, title, frame in
                windowRecencyTracker.record(
                    appID: appID,
                    windowID: windowID,
                    ownerPID: ownerPID,
                    cgWindowID: cgWindowID,
                    title: title,
                    frame: frame
                )
            }
            self.activationHandler = { target, contextsByID in
                runtimeActivator.activate(target: target, contextsByID: contextsByID)
            }
        }
    }

    func activateWindow(
        appID: String,
        windowID: String,
        snapshot: RuntimeHomeAppSnapshot? = nil
    ) {
        let resolvedSnapshot = snapshot ?? snapshotService.homeAppSnapshotSynchronously(for: appID)
        guard let request = Self.makeActivationRequest(
            snapshot: resolvedSnapshot,
            appID: appID,
            windowID: windowID,
            preferences: preferencesProvider()
        ) else {
            return
        }

        activationHandler(request.target, request.contextsByID)
    }

    static func makeActivationRequest(
        snapshot: RuntimeHomeAppSnapshot?,
        appID: String,
        windowID: String,
        preferences: SwitcherPreferences
    ) -> ActivationRequest? {
        guard let snapshot, snapshot.candidate.id == appID else { return nil }

        var session = SwitcherSession(apps: [snapshot.candidate], preferences: preferences)
        guard session.selectWindow(appID: appID, windowID: windowID) else { return nil }
        guard let target = session.commitSelection() else { return nil }

        return ActivationRequest(
            target: target,
            contextsByID: [snapshot.context.appID: snapshot.context]
        )
    }
}
