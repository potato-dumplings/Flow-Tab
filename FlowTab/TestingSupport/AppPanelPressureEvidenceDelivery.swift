#if FLOWTAB_TESTING
import Foundation

enum AppPanelPressureObservationPolicy {
    static let watchdogMilliseconds = 4_000.0
    static let deliveryRetryMilliseconds = 50.0
    static let deliveryWatchdogMilliseconds = 5_000.0
}

private enum AppPanelPressureEvidenceUserInfoKey {
    static let sequence = "sequence"
    static let phase = "phase"
    static let elapsedMilliseconds = "elapsedMilliseconds"
    static let panelPresented = "panelPresented"
    static let userVisible = "userVisible"
    static let selectedAppID = "selectedAppID"
    static let appCount = "appCount"
    static let selectedWindowCount = "selectedWindowCount"
    static let satisfied = "satisfied"
    static let stageMetrics = "stageMetrics"
}

struct AppPanelPressurePendingEvidenceDelivery {
    let timer: DispatchSourceTimer
}

extension AppPanelPressureEvidenceTransport {
    static var notificationName: Notification.Name? {
        guard let rawName =
                FlowTabTestLaunchOptions
                    .appPanelPressureEvidenceNotificationName?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
              !rawName.isEmpty
        else {
            return nil
        }
        return Notification.Name(rawName)
    }

    static func fixedStageMetrics(
        token: AppPanelPressureMeasurementToken,
        completionStartedAtNanoseconds: UInt64,
        panelController: SwitcherPanelController
    ) -> [String: Double] {
        guard token.phase == .opened else { return [:] }
        let sessionLoad = panelController.modelForTesting
            .lastAppSwitcherSessionLoadDiagnostic
        let sessionStart = panelController.modelForTesting
            .lastAppSwitcherSessionStartDiagnostic
        let presentation = panelController
            .lastPanelPresentationBreakdownDiagnostic
        let presentationTotalMilliseconds =
            presentation?.totalMs ?? 0
        let elapsedAtCompletionMilliseconds = milliseconds(
            from: token.startedAtNanoseconds,
            to: completionStartedAtNanoseconds
        )
        var metrics: [String: Double] = [
            StageKey.triggerDispatch: milliseconds(
                from: token.triggerReceivedAtNanoseconds,
                to: token.mainActorEnteredAtNanoseconds
            ),
            StageKey.mainPreparation: milliseconds(
                from: token.mainActorEnteredAtNanoseconds,
                to: token.startedAtNanoseconds
            ),
            StageKey.sessionDirectoryRefresh:
                sessionStart?.directoryRefreshMs ?? 0,
            StageKey.sessionInvalidation:
                sessionStart?.invalidationMs ?? 0,
            StageKey.sessionStateReset:
                sessionStart?.stateResetMs ?? 0,
            StageKey.sessionProjection:
                sessionLoad?.projectionMs ?? 0,
            StageKey.sessionRecency:
                sessionLoad?.recencyMs ?? 0,
            StageKey.sessionBuild:
                sessionLoad?.sessionBuildMs ?? 0,
            StageKey.sessionIndex:
                sessionLoad?.indexMs ?? 0,
            StageKey.sessionPublish:
                sessionLoad?.publishMs ?? 0,
            StageKey.sessionLoadWrapper: max(
                0,
                (sessionStart?.projectionLoadMs ?? 0)
                    - (sessionLoad?.totalMs ?? 0)
            ),
            StageKey.sessionMaintenanceRequest:
                sessionStart?.maintenanceRequestMs ?? 0,
            StageKey.sessionControllerWrapper: max(
                0,
                (presentation?.sessionMs ?? 0)
                    - (sessionStart?.totalMs ?? 0)
            ),
            StageKey.screenResolve:
                presentation?.screenMs ?? 0,
            StageKey.panelSize:
                presentation?.sizeMs ?? 0,
            StageKey.panelCenter:
                presentation?.centerMs ?? 0,
            StageKey.accessibilitySync:
                presentation?.accessibilityMs ?? 0,
            StageKey.presentationLevel:
                presentation?.levelMs ?? 0,
            StageKey.hideNonPanelWindows:
                presentation?.hideMs ?? 0,
            StageKey.initialVisibilityTracking:
                presentation?.initialVisibilityTrackingMs ?? 0,
            StageKey.monitorInstall:
                presentation?.monitorMs ?? 0,
            StageKey.makeKey:
                presentation?.makeKeyMs ?? 0,
            StageKey.orderRegardless:
                presentation?.orderRegardlessMs ?? 0,
            StageKey.firstMakeKey:
                presentation?.firstMakeKeyMs ?? 0,
            StageKey.firstOrderRegardless:
                presentation?.firstOrderRegardlessMs ?? 0,
            StageKey.secondMakeKey:
                presentation?.secondMakeKeyMs ?? 0,
            StageKey.secondOrderRegardless:
                presentation?.secondOrderRegardlessMs ?? 0,
            StageKey.presentationReadback:
                presentation?.presentationReadbackMs ?? 0,
            StageKey.autoEnterSchedule:
                presentation?.autoEnterMs ?? 0,
            StageKey.presentationWrapper: max(
                0,
                elapsedAtCompletionMilliseconds
                    - presentationTotalMilliseconds
            ),
            StageKey.nextMainTurn: 0,
            StageKey.layout: 0,
            StageKey.display: 0,
            StageKey.visibilityPollWait: 0,
            StageKey.visibilityReadback: 0
        ]
        metrics[StageKey.visibilityWait] = 0
        return metrics
    }

    static func milliseconds(
        from start: UInt64?,
        to end: UInt64?
    ) -> Double {
        guard let start, let end, end >= start else { return 0 }
        return Double(end - start) / 1_000_000
    }

    static func publish(
        _ evidence: AppPanelPressureEvidence
    ) {
        guard let notificationName else { return }
        let userInfo: [String: Any] = [
            AppPanelPressureEvidenceUserInfoKey.sequence:
                NSNumber(value: evidence.sequence),
            AppPanelPressureEvidenceUserInfoKey.phase:
                evidence.phase.rawValue,
            AppPanelPressureEvidenceUserInfoKey.elapsedMilliseconds:
                NSNumber(
                    value:
                        evidence.elapsedMilliseconds
                ),
            AppPanelPressureEvidenceUserInfoKey.panelPresented:
                NSNumber(
                    value: evidence.panelPresented
                ),
            AppPanelPressureEvidenceUserInfoKey.userVisible:
                NSNumber(value: evidence.userVisible),
            AppPanelPressureEvidenceUserInfoKey.selectedAppID:
                evidence.selectedAppID ?? "none",
            AppPanelPressureEvidenceUserInfoKey.appCount:
                NSNumber(value: evidence.appCount),
            AppPanelPressureEvidenceUserInfoKey.selectedWindowCount:
                NSNumber(
                    value:
                        evidence.selectedWindowCount
                ),
            AppPanelPressureEvidenceUserInfoKey.satisfied:
                NSNumber(value: evidence.isSatisfied),
            AppPanelPressureEvidenceUserInfoKey.stageMetrics:
                evidence.stageMetrics.mapValues {
                    NSNumber(value: $0)
                }
        ]
        guard evidenceAcknowledgementName != nil else {
            DistributedNotificationCenter.default()
                .postNotificationName(
                    notificationName,
                    object: nil,
                    userInfo: userInfo,
                    deliverImmediately: true
                )
            return
        }

        pendingEvidenceDeliveries[evidence.sequence]?
            .timer.cancel()
        DistributedNotificationCenter.default()
            .postNotificationName(
                notificationName,
                object: nil,
                userInfo: userInfo,
                deliverImmediately: true
            )
        let timer = DispatchSource.makeTimerSource(
            queue: evidenceDeliveryQueue
        )
        let deliveryDeadline =
            ProcessInfo.processInfo.systemUptime
                + AppPanelPressureObservationPolicy
                    .deliveryWatchdogMilliseconds / 1_000
        timer.schedule(
            deadline: .now()
                + .milliseconds(
                    Int(
                        AppPanelPressureObservationPolicy
                            .deliveryRetryMilliseconds
                    )
                ),
            repeating: .milliseconds(
                Int(
                    AppPanelPressureObservationPolicy
                        .deliveryRetryMilliseconds
                )
            )
        )
        timer.setEventHandler {
            guard ProcessInfo.processInfo.systemUptime
                    < deliveryDeadline
            else {
                timer.cancel()
                return
            }
            DistributedNotificationCenter.default()
                .postNotificationName(
                    notificationName,
                    object: nil,
                    userInfo: userInfo,
                    deliverImmediately: true
                )
        }
        pendingEvidenceDeliveries[evidence.sequence] =
            AppPanelPressurePendingEvidenceDelivery(
                timer: timer
            )
        timer.resume()
    }

    static var evidenceAcknowledgementName:
        Notification.Name?
    {
        guard let rawName =
                FlowTabTestLaunchOptions
                    .appPanelPressureEvidenceAcknowledgementNotificationName?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
              !rawName.isEmpty
        else {
            return nil
        }
        return Notification.Name(rawName)
    }

    static func installEvidenceAcknowledgementObserverIfNeeded() {
        let name = evidenceAcknowledgementName
        guard name != installedEvidenceAcknowledgementName else {
            return
        }
        if let evidenceAcknowledgementToken {
            DistributedNotificationCenter.default()
                .removeObserver(evidenceAcknowledgementToken)
            self.evidenceAcknowledgementToken = nil
        }
        for delivery in pendingEvidenceDeliveries.values {
            delivery.timer.cancel()
        }
        pendingEvidenceDeliveries.removeAll()
        installedEvidenceAcknowledgementName = name
        guard let name else { return }
        evidenceAcknowledgementToken =
            DistributedNotificationCenter.default()
                .addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { notification in
                    guard let sequence = (
                        notification.userInfo?[
                            AppPanelPressureEvidenceUserInfoKey
                                .sequence
                        ] as? NSNumber
                    )?.uint64Value
                    else {
                        return
                    }
                    MainActor.assumeIsolated {
                        acknowledgeEvidence(sequence: sequence)
                    }
                }
    }

    static func acknowledgeEvidence(sequence: UInt64) {
        guard let delivery =
                pendingEvidenceDeliveries.removeValue(
                    forKey: sequence
                )
        else {
            return
        }
        delivery.timer.cancel()
    }
}
#endif
