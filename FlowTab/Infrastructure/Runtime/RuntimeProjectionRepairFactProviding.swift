import AppKit
import CoreGraphics
import Foundation

protocol RuntimeProjectionRepairFactProviding: AnyObject {
    func collectAXWindowData(
        for runningApps: [NSRunningApplication],
        cgWindowsByPID: [pid_t: [RuntimeCGWindowEntry]],
        allCGWindowsByPID: [pid_t: [RuntimeCGWindowEntry]]
    ) -> [pid_t: [RuntimeWindowListEntry]]

    func collectCGWindowsWithSpaceTopologyDiff(
        options: CGWindowListOption,
        now: TimeInterval
    ) -> RuntimeCGWindowCollection
}

extension RuntimeSnapshotProvider: RuntimeProjectionRepairFactProviding {}
