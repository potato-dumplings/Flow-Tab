import Foundation
import FlowTabCore

@MainActor
final class HomeWindowActivationController {
    struct ActivationRequest {
        let target: ActivationTarget
        let contextsByID: [String: RuntimeAppContext]
    }

    static let shared = HomeWindowActivationController()

    private let runtimeProjectionService: any RuntimeProjectionServing
    private let preferencesProvider: () -> SwitcherPreferences
    private let activationHandler: (ActivationTarget, [String: RuntimeAppContext]) -> Void

    init(
        runtimeProjectionService: any RuntimeProjectionServing = sharedRuntimeProjectionService,
        preferencesProvider: @escaping () -> SwitcherPreferences = {
            SwitcherBehaviorPreferencesStore.loadSwitcherPreferences()
        },
        windowRecencyTracker: RuntimeWindowRecencyTracker = .shared,
        activationHandler: ((ActivationTarget, [String: RuntimeAppContext]) -> Void)? = nil
    ) {
        self.runtimeProjectionService = runtimeProjectionService
        self.preferencesProvider = preferencesProvider

        if let activationHandler {
            self.activationHandler = activationHandler
        } else {
            let runtimeActivator = RuntimeActivator()
            runtimeActivator.windowFocusVerifiedHandler = { verification in
                windowRecencyTracker.recordVerifiedFocus(
                    appID: verification.appID,
                    windowID: verification.windowID,
                    ownerPID: verification.ownerPID,
                    cgWindowID: verification.targetCGWindowID,
                    title: verification.title,
                    frame: verification.frame,
                    allowedActions: verification.allowedActions
                )
                runtimeProjectionService.signalWindowFocusVerified(verification)
            }
            self.activationHandler = { target, contextsByID in
                runtimeActivator.activate(target: target, contextsByID: contextsByID)
            }
        }
    }

    func activateWindow(
        appID: String,
        windowID: String,
        detailProjection: RuntimeHomeAppDetailProjection? = nil
    ) {
        let resolvedDetailProjection = detailProjection ?? HomeRuntimeProjectionReader.appDetailProjection(
            for: appID,
            from: runtimeProjectionService
        )
        guard let request = Self.makeActivationRequest(
            detailProjection: resolvedDetailProjection,
            appID: appID,
            windowID: windowID,
            preferences: preferencesProvider()
        ) else {
            signalActivationProjectionMissing(appID: appID)
            return
        }

        activationHandler(request.target, request.contextsByID)
    }

    private func signalActivationProjectionMissing(appID: String) {
        let pid = HomeRuntimeProjectionReader.appSummary(for: appID, from: runtimeProjectionService)?.pid
            ?? runtimeProjectionService.readAppSwitcherProjection()?.contextsByID[appID]?.runningApp.processIdentifier
        guard let pid, pid != 0 else { return }
        runtimeProjectionService.signalAppWindowsChanged(appID: appID, pid: pid)
    }

    static func makeActivationRequest(
        detailProjection: RuntimeHomeAppDetailProjection?,
        appID: String,
        windowID: String,
        preferences: SwitcherPreferences
    ) -> ActivationRequest? {
        guard let detailProjection, detailProjection.candidate.id == appID else { return nil }

        var session = SwitcherSession(apps: [detailProjection.candidate], preferences: preferences)
        guard session.selectWindow(appID: appID, windowID: windowID) else { return nil }
        guard let target = session.commitSelection() else { return nil }

        return ActivationRequest(
            target: target,
            contextsByID: [detailProjection.context.appID: detailProjection.context]
        )
    }
}
