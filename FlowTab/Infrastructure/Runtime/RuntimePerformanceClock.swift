import Foundation

enum RuntimePerformanceClock {
    static func monotonicMilliseconds() -> Double {
        ProcessInfo.processInfo.systemUptime * 1_000
    }

    static func formatMilliseconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    static func normalizedLogValue(_ value: String?) -> String {
        guard let value else { return "nil" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "empty" }
        return trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
