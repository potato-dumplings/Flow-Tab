import Foundation
import FlowTabCore

@MainActor
protocol SwitcherFocusedWindowSessionStarting: AnyObject {
    func startFocusedAppWindowSession(triggerDirection: CycleDirection) -> FocusedAppWindowSessionStartResult
    func completePendingFocusedAppWindowSession(_ pending: PendingFocusedAppWindowSession) -> Bool
}

@MainActor
protocol SwitcherFocusedWindowProjectionReading {
    var generation: RuntimeReadModelGeneration { get }
    func read() -> RuntimeFocusedCurrentAppWindowProjectionRead?
    func requestRefresh()
}

@MainActor
struct SwitcherFocusedWindowProjectionReader: SwitcherFocusedWindowProjectionReading {
    let service: any RuntimeProjectionServing
    var generation: RuntimeReadModelGeneration { service.runtimeReadModelDiagnostics().generation }
    func read() -> RuntimeFocusedCurrentAppWindowProjectionRead? { service.readFocusedCurrentAppWindowProjection() }
    func requestRefresh() { service.signalFocusedCurrentAppWindowsChanged() }
}

@MainActor
final class SwitcherFocusedWindowSessionCoordinator: SwitcherFocusedWindowSessionStarting {
    unowned let model: LiveSwitcherModel
    let projection: any SwitcherFocusedWindowProjectionReading
    let installation: any SwitcherFocusedWindowSessionInstalling

    init(model: LiveSwitcherModel, projection: (any SwitcherFocusedWindowProjectionReading)? = nil,
         installation: (any SwitcherFocusedWindowSessionInstalling)? = nil) {
        self.model = model
        self.projection = projection ?? SwitcherFocusedWindowProjectionReader(service: model.runtimeProjectionService)
        self.installation = installation ?? SwitcherFocusedWindowSessionInstaller(model: model)
    }

    func startFocusedAppWindowSession(
        triggerDirection: CycleDirection
    ) -> FocusedAppWindowSessionStartResult {
        let startMs = LiveSwitcherModel.monotonicMilliseconds()
        model.invalidateSelectedAppWindowProjection(reason: .startFocusedWindowSession)
        model.clearTerminateSelectedAppAnimation()
        guard let focusedRead = projection.read() else {
            projection.requestRefresh()
            model.logStartFocusedWindowSessionNoFrontmost(startMs: startMs)
            model.resetSessionState()
            return .unavailable
        }
        let frontmostReadyMs = LiveSwitcherModel.monotonicMilliseconds()
        let projectionReadMs = LiveSwitcherModel.monotonicMilliseconds()
        guard let projection = focusedRead.projection,
              projection.freshness.isCompleteForScope
        else {
            let pending = PendingFocusedAppWindowSession(
                appID: focusedRead.appID,
                pid: focusedRead.pid,
                triggerDirection: triggerDirection,
                baselineReadModelGeneration:
                    projection.generation,
                baselineProjectionGeneration:
                    focusedRead.projection?.freshness.sourceGeneration
            )
            projection.requestRefresh()
            let awaitingMs = LiveSwitcherModel.monotonicMilliseconds()
            model.logStartFocusedWindowSession(
                result: "awaitingFreshProjection",
                frontmostAppID: focusedRead.appID,
                frontmostReadyMs: frontmostReadyMs,
                projectionReadMs: projectionReadMs,
                recencyAppliedMs: awaitingMs,
                completeMs: awaitingMs,
                startMs: startMs
            )
            model.resetSessionState()
            return .awaitingFreshProjection(pending)
        }
        let payload = installation.applyRecency(
            projection.currentAppWindowPayload
        )
        let recencyAppliedMs = LiveSwitcherModel.monotonicMilliseconds()
        guard installation.install(
            payload: payload,
            triggerDirection: triggerDirection
        ) else {
            let failedMs = LiveSwitcherModel.monotonicMilliseconds()
            model.logStartFocusedWindowSession(
                result: "noWindows",
                frontmostAppID: focusedRead.appID,
                frontmostReadyMs: frontmostReadyMs,
                projectionReadMs: projectionReadMs,
                recencyAppliedMs: recencyAppliedMs,
                completeMs: failedMs,
                startMs: startMs
            )
            model.resetSessionState()
            return .unavailable
        }
        let completeMs = LiveSwitcherModel.monotonicMilliseconds()
        model.logStartFocusedWindowSession(
            result: "ready",
            frontmostAppID: focusedRead.appID,
            frontmostReadyMs: frontmostReadyMs,
            projectionReadMs: projectionReadMs,
            recencyAppliedMs: recencyAppliedMs,
            completeMs: completeMs,
            startMs: startMs,
            windows: payload.candidate.windows.count
        )
        return .ready
    }

    func completePendingFocusedAppWindowSession(
        _ pending: PendingFocusedAppWindowSession
    ) -> Bool {

        guard model.session == nil,
              let focusedRead = projection.read(),
              pending.accepts(focusedRead),
              let projection = focusedRead.projection
        else { return false }
        let payload = installation.applyRecency(
            projection.currentAppWindowPayload
        )
        return installation.install(
            payload: payload,
            triggerDirection: pending.triggerDirection
        )
    }

}
