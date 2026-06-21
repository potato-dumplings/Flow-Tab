enum RuntimeProjectionDiagnostics {
    static func logTiming(_ event: String, fields: [(String, String)]) {
        RuntimeLog.debug(.projection, timingLine(event, fields: fields))
    }

    static func timingLine(_ event: String, fields: [(String, String)]) -> String {
        ([event] + fields.map { "\($0.0)=\($0.1)" }).joined(separator: " ")
    }

    static func formatMilliseconds(_ value: Double) -> String {
        RuntimePerformanceClock.formatMilliseconds(value)
    }
}
