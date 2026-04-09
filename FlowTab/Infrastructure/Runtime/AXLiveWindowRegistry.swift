import AppKit
import ApplicationServices
import Foundation

final class AXLiveWindowRegistry {
    static let shared = AXLiveWindowRegistry()

    private final class ObserverContext {
        weak var registry: AXLiveWindowRegistry?
        let pid: pid_t

        init(registry: AXLiveWindowRegistry, pid: pid_t) {
            self.registry = registry
            self.pid = pid
        }
    }

    private let lock = NSLock()
    private var windowsByPID: [pid_t: [String: AXUIElement]] = [:]
    private var observersByPID: [pid_t: AXObserver] = [:]
    private var observerContextsByPID: [pid_t: ObserverContext] = [:]
    private let watchedNotifications: [CFString] = [
        kAXWindowCreatedNotification as CFString,
        kAXWindowMovedNotification as CFString,
        kAXWindowResizedNotification as CFString,
        kAXMainWindowChangedNotification as CFString,
        kAXFocusedWindowChangedNotification as CFString,
        kAXWindowMiniaturizedNotification as CFString,
        kAXWindowDeminiaturizedNotification as CFString,
        kAXUIElementDestroyedNotification as CFString
    ]

    private init() {}

    func rebind(_ runningApps: [NSRunningApplication]) {
        let expectedPIDs = Set(runningApps.map(\.processIdentifier))
        DispatchQueue.main.async { [weak self] in
            self?.rebindOnMainThread(expectedPIDs: expectedPIDs)
        }
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

    private func makeWindowMap(pid: pid_t, windows: [AXUIElement]) -> [String: AXUIElement] {
        Dictionary(
            uniqueKeysWithValues: windows.enumerated().map { index, window in
                (AXWindowInspector.makeWindowID(pid: pid, index: index), window)
            }
        )
    }

    private func rebindOnMainThread(expectedPIDs: Set<pid_t>) {
        if !AccessibilityPermissionChecker.isTrusted() {
            for pid in Array(observersByPID.keys) {
                removeObserver(pid: pid)
            }
            lock.lock()
            windowsByPID.removeAll()
            lock.unlock()
            return
        }

        for pid in Array(observersByPID.keys) where !expectedPIDs.contains(pid) {
            removeObserver(pid: pid)
            lock.lock()
            windowsByPID.removeValue(forKey: pid)
            lock.unlock()
        }

        for pid in expectedPIDs where observersByPID[pid] == nil {
            installObserver(pid: pid)
        }
    }

    private func installObserver(pid: pid_t) {
        var observerRef: AXObserver?
        let createResult = AXObserverCreate(pid, Self.callback, &observerRef)
        guard createResult == .success, let observerRef else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let context = ObserverContext(registry: self, pid: pid)
        let contextPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(context).toOpaque())
        for notification in watchedNotifications {
            let addResult = AXObserverAddNotification(
                observerRef,
                appElement,
                notification,
                contextPointer
            )
            if addResult == .notificationUnsupported {
                continue
            }
            guard addResult == .success || addResult == .notificationAlreadyRegistered else { continue }
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observerRef),
            .defaultMode
        )
        observersByPID[pid] = observerRef
        observerContextsByPID[pid] = context
    }

    private func removeObserver(pid: pid_t) {
        guard let observer = observersByPID.removeValue(forKey: pid) else { return }
        let appElement = AXUIElementCreateApplication(pid)
        for notification in watchedNotifications {
            AXObserverRemoveNotification(observer, appElement, notification)
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        observerContextsByPID.removeValue(forKey: pid)
    }

    private func refreshFromObserver(pid: pid_t, notification: CFString) {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            lock.lock()
            windowsByPID.removeValue(forKey: pid)
            lock.unlock()
            return
        }
        let fetchResult = AXWindowInspector.windowsFetchResult(for: app)
        let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(pid)"
        RuntimeLog.info(
            "AXObserver",
            "\(appName) pid=\(pid) notification=\(notification) rawWindows=\(fetchResult.windows.count) \(fetchResult.logDetails)"
        )
        refreshSnapshot(forPID: pid, windows: fetchResult.windows)
    }

    private static let callback: AXObserverCallback = { _, _, notification, refcon in
        guard let refcon else { return }
        let context = Unmanaged<ObserverContext>.fromOpaque(refcon).takeUnretainedValue()
        Task { @MainActor in
            context.registry?.refreshFromObserver(pid: context.pid, notification: notification)
        }
    }
}
