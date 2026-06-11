import AppKit
import ApplicationServices
import Foundation

final class AXLiveWindowRegistry {
    static let shared = AXLiveWindowRegistry()

    private let lock = NSLock()
    private var windowsByPID: [pid_t: [String: AXUIElement]] = [:]

    private init() {}

    func prune(to runningApps: [NSRunningApplication]) {
        let expectedPIDs = Set(runningApps.map(\.processIdentifier))
        lock.lock()
        windowsByPID = windowsByPID.filter { expectedPIDs.contains($0.key) }
        lock.unlock()
    }

    func remove(pid: pid_t) {
        lock.lock()
        windowsByPID.removeValue(forKey: pid)
        lock.unlock()
    }

    func refreshSnapshot(forPID pid: pid_t, windows: [AXUIElement]) {
        let windowsByID = makeWindowMap(pid: pid, windows: windows)
        lock.lock()
        windowsByPID[pid] = windowsByID
        lock.unlock()
    }

    func window(forWindowID windowID: String, expectedPID: pid_t) -> AXUIElement? {
        lock.lock()
        defer { lock.unlock() }
        return windowsByPID[expectedPID]?[windowID]
    }

    func windowID(forKnownWindow window: AXUIElement, expectedPID: pid_t) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let windowsByID = windowsByPID[expectedPID] else { return nil }
        return windowsByID.keys.sorted().first { windowID in
            guard let knownWindow = windowsByID[windowID] else { return false }
            return CFEqual(knownWindow, window)
        }
    }

    private func makeWindowMap(pid: pid_t, windows: [AXUIElement]) -> [String: AXUIElement] {
        Dictionary(
            uniqueKeysWithValues: windows.enumerated().map { index, window in
                (AXWindowInspector.makeWindowID(pid: pid, index: index), window)
            }
        )
    }
}
