import AppKit
import Foundation

enum RuntimeFactCollectionDiagnostics {
    static func logTiming(_ event: String, fields: [(String, String)]) {
        RuntimeLog.debug(.snapshot, timingLine(event, fields: fields))
    }

    static func timingLine(_ event: String, fields: [(String, String)]) -> String {
        ([event] + fields.map { "\($0.0)=\($0.1)" }).joined(separator: " ")
    }

    static func formatMilliseconds(_ value: Double) -> String {
        RuntimePerformanceClock.formatMilliseconds(value)
    }

    static func logAppName(_ appName: String) -> String {
        "\"\(RuntimePerformanceClock.normalizedLogValue(appName))\""
    }

    static func logAppIdentifier(_ app: NSRunningApplication) -> String {
        RuntimePerformanceClock.normalizedLogValue(
            app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        )
    }
}
