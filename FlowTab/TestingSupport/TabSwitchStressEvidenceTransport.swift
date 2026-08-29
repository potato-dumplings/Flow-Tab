#if FLOWTAB_TESTING
import Foundation

enum TabSwitchStressEvidenceTransport {
    private enum UserInfoKey {
        static let ownerGeneration =
            "ownerGeneration"
        static let transitionGeneration =
            "transitionGeneration"
        static let phase = "phase"
        static let durationNanoseconds =
            "durationNanoseconds"
        static let cadenceNanoseconds =
            "cadenceNanoseconds"
        static let requiredSwitches =
            "requiredSwitches"
        static let attempts = "attempts"
        static let switches = "switches"
        static let homeSwitches = "homeSwitches"
        static let logsSwitches = "logsSwitches"
        static let settingsSwitches = "settingsSwitches"
        static let runtimeLogLevel = "runtimeLogLevel"
        static let requested = "requested"
        static let observed = "observed"
        static let elapsedNanoseconds =
            "elapsedNanoseconds"
        static let durationSatisfied =
            "durationSatisfied"
        static let workloadSatisfied =
            "workloadSatisfied"
    }

    static func publish(
        _ evidence: TabSwitchStressEvidence
    ) {
        guard let rawName =
                FlowTabTestLaunchOptions
                    .tabSwitchStressEvidenceNotificationName,
              !rawName.isEmpty
        else {
            return
        }
        DistributedNotificationCenter.default()
            .postNotificationName(
                Notification.Name(rawName),
                object: nil,
                userInfo: [
                    UserInfoKey.ownerGeneration:
                        NSNumber(
                            value:
                                evidence.ownerGeneration
                        ),
                    UserInfoKey.transitionGeneration:
                        NSNumber(
                            value:
                                evidence
                                    .transitionGeneration
                        ),
                    UserInfoKey.phase:
                        evidence.phase.rawValue,
                    UserInfoKey.durationNanoseconds:
                        NSNumber(
                            value:
                                evidence.policy
                                    .durationNanoseconds
                        ),
                    UserInfoKey.cadenceNanoseconds:
                        NSNumber(
                            value:
                                evidence.policy
                                    .cadenceNanoseconds
                        ),
                    UserInfoKey.requiredSwitches:
                        NSNumber(
                            value:
                                evidence.policy
                                    .requiredSwitchCount
                        ),
                    UserInfoKey.attempts:
                        NSNumber(
                            value:
                                evidence.attemptCount
                        ),
                    UserInfoKey.switches:
                        NSNumber(
                            value:
                                evidence.switchCount
                        ),
                    UserInfoKey.homeSwitches:
                        NSNumber(
                            value: evidence.homeSwitchCount
                        ),
                    UserInfoKey.logsSwitches:
                        NSNumber(
                            value: evidence.logsSwitchCount
                        ),
                    UserInfoKey.settingsSwitches:
                        NSNumber(
                            value: evidence.settingsSwitchCount
                        ),
                    UserInfoKey.runtimeLogLevel:
                        RuntimeLogPreferencesStore
                            .loadMinimumLevel()
                            .rawValue,
                    UserInfoKey.requested:
                        evidence.requestedTarget?
                            .rawValue
                            ?? "none",
                    UserInfoKey.observed:
                        evidence.observedTarget?
                            .rawValue
                            ?? "none",
                    UserInfoKey.elapsedNanoseconds:
                        NSNumber(
                            value:
                                evidence.elapsedNanoseconds
                        ),
                    UserInfoKey.durationSatisfied:
                        NSNumber(
                            value:
                                evidence.durationSatisfied
                        ),
                    UserInfoKey.workloadSatisfied:
                        NSNumber(
                            value:
                                evidence.workloadSatisfied
                        )
                ],
                deliverImmediately: true
            )
    }
}
#endif
