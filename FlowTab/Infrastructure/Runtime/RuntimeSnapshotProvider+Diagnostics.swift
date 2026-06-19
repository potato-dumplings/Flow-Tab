import AppKit
import Foundation

extension RuntimeSnapshotProvider {
    func logSnapshotTiming(_ event: String, fields: [(String, String)]) {
        RuntimeLog.debug(.snapshot, Self.snapshotTimingLine(event, fields: fields))
    }

    func logProjectionTiming(_ event: String, fields: [(String, String)]) {
        RuntimeLog.debug(.projection, Self.projectionTimingLine(event, fields: fields))
    }

    static func snapshotTimingLine(_ event: String, fields: [(String, String)]) -> String {
        ([event] + fields.map { "\($0.0)=\($0.1)" }).joined(separator: " ")
    }

    static func projectionTimingLine(_ event: String, fields: [(String, String)]) -> String {
        ([event] + fields.map { "\($0.0)=\($0.1)" }).joined(separator: " ")
    }

    func formatSnapshotMilliseconds(_ value: Double) -> String {
        RuntimePerformanceClock.formatMilliseconds(value)
    }

    func formatProjectionMilliseconds(_ value: Double) -> String {
        RuntimePerformanceClock.formatMilliseconds(value)
    }

    func logAppName(_ appName: String) -> String {
        "\"\(RuntimePerformanceClock.normalizedLogValue(appName))\""
    }

    func logAppIdentifier(_ app: NSRunningApplication) -> String {
        RuntimePerformanceClock.normalizedLogValue(
            app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        )
    }
}
