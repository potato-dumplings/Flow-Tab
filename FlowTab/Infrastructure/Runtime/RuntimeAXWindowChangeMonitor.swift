import AppKit
import ApplicationServices
import Foundation
import FlowTabCore

enum RuntimeAXWindowObservationInstallEvidence: Equatable {
    case installed
    case unavailable(error: AXError)
}

@MainActor
protocol RuntimeAXWindowChangeMonitoring: AnyObject {
    var onAppWindowChanged: ((RuntimeAXWindowChangeEvidence) -> Void)? { get set }
    var onAXWindowDestroyed: ((String, pid_t, String) -> Void)? { get set }

    func observe(appID: String, pid: pid_t) -> RuntimeAXWindowObservationInstallEvidence
    func stopObserving(pid: pid_t)
    func stop()
}

@MainActor
final class RuntimeAXWindowChangeMonitor: RuntimeAXWindowChangeMonitoring {
    private final class ObserverContext {
        weak var monitor: RuntimeAXWindowChangeMonitor?
        let appID: String
        let pid: pid_t
        let bindingGeneration: UInt64

        init(
            monitor: RuntimeAXWindowChangeMonitor,
            appID: String,
            pid: pid_t,
            bindingGeneration: UInt64
        ) {
            self.monitor = monitor
            self.appID = appID
            self.pid = pid
            self.bindingGeneration = bindingGeneration
        }
    }

    var onAppWindowChanged: ((RuntimeAXWindowChangeEvidence) -> Void)?
    var onAXWindowDestroyed: ((String, pid_t, String) -> Void)?

    private var observersByPID: [pid_t: AXObserver] = [:]
    private var observerContextByPID: [pid_t: ObserverContext] = [:]
    private var appIDByPID: [pid_t: String] = [:]
    private var destroyedWindowElementsByPID: [pid_t: [String: AXUIElement]] = [:]
    private let deliveryCoordinator: RuntimeAXWindowChangeDeliveryCoordinator
    private let watchedNotifications: [CFString] = [
        kAXWindowCreatedNotification as CFString,
        kAXUIElementDestroyedNotification as CFString,
        kAXFocusedWindowChangedNotification as CFString,
        kAXMainWindowChangedNotification as CFString,
        kAXWindowMiniaturizedNotification as CFString,
        kAXWindowDeminiaturizedNotification as CFString
    ]

    init(
        deliveryPolicy: RuntimeAXWindowChangeDeliveryPolicy = .standardCoalesced,
        deliveryScheduler: (any RuntimeAXWindowChangeDeliveryScheduling)? = nil
    ) {
        deliveryCoordinator = RuntimeAXWindowChangeDeliveryCoordinator(
            policy: deliveryPolicy,
            scheduler: deliveryScheduler
        )
        deliveryCoordinator.onEvidence = { [weak self] evidence in
            self?.onAppWindowChanged?(evidence)
        }
    }

    func rebind(_ appSummaries: [RuntimeHomeAppSummary]) {
        guard AccessibilityPermissionChecker.isTrusted() else {
            stop()
            return
        }

        let expectedByPID = Self.expectedAppIDsByPID(from: appSummaries)

        for pid in Array(observersByPID.keys) {
            guard let expectedAppID = expectedByPID[pid], expectedAppID == appIDByPID[pid] else {
                removeObserver(pid: pid)
                continue
            }
        }

        for (pid, appID) in expectedByPID where observersByPID[pid] == nil {
            guard observe(appID: appID, pid: pid) == .installed,
                  let context = observerContextByPID[pid],
                  let summary = appSummaries.last(where: { $0.pid == pid })
            else {
                continue
            }
            deliveryCoordinator.publishInitialReadback(
                pid: pid,
                bindingGeneration: context.bindingGeneration,
                readback: initialReadbackEvidence(for: summary)
            )
        }
        for pid in expectedByPID.keys {
            syncDestroyedWindowObservers(pid: pid)
        }
    }

    static func expectedAppIDsByPID(
        from appSummaries: [RuntimeHomeAppSummary],
        currentPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> [pid_t: String] {
        appSummaries.reduce(into: [:]) { expectedByPID, summary in
            // Observing FlowTab's own Home window feeds its UI changes back into runtime repair.
            guard summary.pid > 0, summary.pid != currentPID else { return }
            expectedByPID[summary.pid] = summary.appID
        }
    }

    func stop() {
        for pid in Array(observersByPID.keys) {
            removeObserver(pid: pid)
        }
        deliveryCoordinator.stop()
    }

    func observe(
        appID: String,
        pid: pid_t
    ) -> RuntimeAXWindowObservationInstallEvidence {
        if observersByPID[pid] != nil, appIDByPID[pid] == appID {
            return .installed
        }
        if observersByPID[pid] != nil {
            removeObserver(pid: pid)
        }
        return installObserver(pid: pid, appID: appID)
    }

    func stopObserving(pid: pid_t) {
        removeObserver(pid: pid)
    }

    private func installObserver(
        pid: pid_t,
        appID: String
    ) -> RuntimeAXWindowObservationInstallEvidence {
        var observerRef: AXObserver?
        let result = AXObserverCreate(pid, Self.callback, &observerRef)
        guard result == .success, let observerRef else {
            return .unavailable(error: result == .success ? .failure : result)
        }

        let appElement = AXUIElementCreateApplication(pid)
        let bindingGeneration = deliveryCoordinator.bind(appID: appID, pid: pid)
        let context = ObserverContext(
            monitor: self,
            appID: appID,
            pid: pid,
            bindingGeneration: bindingGeneration
        )
        let contextPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(context).toOpaque())
        var registeredNotifications: [CFString] = []
        var lastAddResult: AXError = .notificationUnsupported
        for notification in watchedNotifications {
            let addResult = AXObserverAddNotification(
                observerRef,
                appElement,
                notification,
                contextPointer
            )
            lastAddResult = addResult
            if addResult == .notificationUnsupported {
                continue
            }
            guard addResult == .success || addResult == .notificationAlreadyRegistered else {
                continue
            }
            registeredNotifications.append(notification)
        }
        guard !registeredNotifications.isEmpty else {
            deliveryCoordinator.unbind(
                pid: pid,
                bindingGeneration: bindingGeneration
            )
            return .unavailable(error: lastAddResult)
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observerRef),
            .defaultMode
        )
        observersByPID[pid] = observerRef
        observerContextByPID[pid] = context
        appIDByPID[pid] = appID
        syncDestroyedWindowObservers(pid: pid)
        return .installed
    }

    private func removeObserver(pid: pid_t) {
        guard let observer = observersByPID.removeValue(forKey: pid) else { return }
        let bindingGeneration = observerContextByPID[pid]?.bindingGeneration

        if let observedWindows = destroyedWindowElementsByPID.removeValue(forKey: pid) {
            for windowElement in observedWindows.values {
                AXObserverRemoveNotification(
                    observer,
                    windowElement,
                    kAXUIElementDestroyedNotification as CFString
                )
            }
        }

        let appElement = AXUIElementCreateApplication(pid)
        for notification in watchedNotifications {
            AXObserverRemoveNotification(observer, appElement, notification)
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        observerContextByPID.removeValue(forKey: pid)
        appIDByPID.removeValue(forKey: pid)
        deliveryCoordinator.unbind(
            pid: pid,
            bindingGeneration: bindingGeneration
        )
    }

    private func syncDestroyedWindowObservers(pid: pid_t) {
        guard
            let observer = observersByPID[pid],
            let context = observerContextByPID[pid]
        else { return }

        let currentWindows = AXLiveWindowRegistry.shared.windows(forPID: pid)
        var observedWindows = destroyedWindowElementsByPID[pid] ?? [:]
        for (windowID, observedElement) in observedWindows {
            guard let currentElement = currentWindows[windowID], CFEqual(currentElement, observedElement) else {
                AXObserverRemoveNotification(
                    observer,
                    observedElement,
                    kAXUIElementDestroyedNotification as CFString
                )
                observedWindows.removeValue(forKey: windowID)
                continue
            }
        }

        let contextPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(context).toOpaque())
        for (windowID, windowElement) in currentWindows where observedWindows[windowID] == nil {
            let addResult = AXObserverAddNotification(
                observer,
                windowElement,
                kAXUIElementDestroyedNotification as CFString,
                contextPointer
            )
            guard addResult == .success || addResult == .notificationAlreadyRegistered else {
                continue
            }
            observedWindows[windowID] = windowElement
        }

        destroyedWindowElementsByPID[pid] = observedWindows
    }

    private func initialReadbackEvidence(
        for summary: RuntimeHomeAppSummary
    ) -> RuntimeAXWindowInitialReadbackEvidence {
        let knownWindows = AXLiveWindowRegistry.shared.windows(forPID: summary.pid)
            .values
            .filter(AXWindowInspector.isSwitchable)
        let appElement = AXUIElementCreateApplication(summary.pid)
        var rawWindows: CFTypeRef?
        let fetchError = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &rawWindows
        )
        let rawValueTypeDescription = AXTypedAttributeReader.typeDescription(
            for: rawWindows
        )
        guard fetchError == .success,
              let currentWindows = rawWindows as? [AXUIElement]
        else {
            return RuntimeAXWindowInitialReadbackEvidence.evaluate(
                expectedWindowCount: summary.windowCount,
                knownSwitchableWindowCount: knownWindows.count,
                observedSwitchableWindowCount: nil,
                exactKnownWindowCount: 0,
                fetchErrorRawValue: fetchError.rawValue,
                rawValueTypeDescription: rawValueTypeDescription
            )
        }

        let currentSwitchableWindows = currentWindows.filter(
            AXWindowInspector.isSwitchable
        )
        return RuntimeAXWindowInitialReadbackEvidence.evaluate(
            expectedWindowCount: summary.windowCount,
            knownSwitchableWindowCount: knownWindows.count,
            observedSwitchableWindowCount: currentSwitchableWindows.count,
            exactKnownWindowCount: Self.exactKnownWindowCount(
                currentWindows: currentSwitchableWindows,
                knownWindows: knownWindows
            ),
            fetchErrorRawValue: fetchError.rawValue,
            rawValueTypeDescription: rawValueTypeDescription
        )
    }

    static func exactKnownWindowCount(
        currentWindows: [AXUIElement],
        knownWindows: [AXUIElement]
    ) -> Int {
        var unmatchedKnownWindows = knownWindows
        var matchCount = 0
        for currentWindow in currentWindows {
            guard let matchIndex = unmatchedKnownWindows.firstIndex(where: {
                CFEqual($0, currentWindow)
            }) else {
                continue
            }
            matchCount += 1
            unmatchedKnownWindows.remove(at: matchIndex)
        }
        return matchCount
    }

    func handleAXNotification(
        appID: String,
        pid: pid_t,
        notification: CFString,
        element: AXUIElement,
        bindingGeneration: UInt64
    ) {
        if notification as String == kAXUIElementDestroyedNotification as String {
            if let axWindowID = AXLiveWindowRegistry.shared.windowID(forKnownWindow: element, expectedPID: pid),
               let onAXWindowDestroyed {
                RuntimeLog.debug(
                    .axObserver,
                    "homeAXDestroyed known appID=\(appID) pid=\(pid) axWindowID=\(axWindowID)"
                )
                onAXWindowDestroyed(appID, pid, axWindowID)
                return
            }
            RuntimeLog.debug(.axObserver, "homeAXDestroyed unresolved appID=\(appID) pid=\(pid)")
        }
        deliveryCoordinator.recordObservedTransition(
            pid: pid,
            bindingGeneration: bindingGeneration
        )
    }

    private static let callback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        let context = Unmanaged<ObserverContext>.fromOpaque(refcon).takeUnretainedValue()
        Task { @MainActor in
            context.monitor?.handleAXNotification(
                context: context,
                notification: notification,
                element: element
            )
        }
    }

    private func handleAXNotification(
        context: ObserverContext,
        notification: CFString,
        element: AXUIElement
    ) {
        guard observerContextByPID[context.pid] === context else { return }
        handleAXNotification(
            appID: context.appID,
            pid: context.pid,
            notification: notification,
            element: element,
            bindingGeneration: context.bindingGeneration
        )
    }
}
