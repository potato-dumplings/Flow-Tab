enum RuntimeFocusRecoveryDiagnostics {
    static func lastObservationLogFields(
        trigger: RuntimeFocusRecoveryTrigger?,
        observation: RuntimeFocusRecoveryObservation?
    ) -> String {
        guard let observation else {
            return "lastTrigger=none lastObservation=none"
        }
        return [
            "lastTrigger=\(trigger?.logValue ?? "none")",
            observationLogFields(observation)
        ].joined(separator: " ")
    }

    static func observationLogFields(
        _ observation: RuntimeFocusRecoveryObservation
    ) -> String {
        [
            "conditionSatisfied=\(observation.conditionSatisfied ? 1 : 0)",
            "processTerminated=\(observation.processIsTerminated ? 1 : 0)",
            "targetVisible=\(observation.targetIsVisible ? 1 : 0)",
            "focusedCG=\(observation.focusedCGWindowID.map(String.init) ?? "nil")",
            "frontmostCG=\(observation.frontmostCGWindowID.map(String.init) ?? "nil")",
            "visibleCG=\(observation.visibleCGWindowIDs.map(String.init).joined(separator: ","))"
        ].joined(separator: " ")
    }
}
