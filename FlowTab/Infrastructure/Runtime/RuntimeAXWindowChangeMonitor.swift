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
    private final class ObserverContext: @unchecked Sendable {
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

    private struct PendingObserverInstall {
        let appID: String
        let generation: UInt64
        let bindingGeneration: UInt64
        let context: ObserverContext
    }

    private struct ObserverInstallWorkResult: @unchecked Sendable {
        let observer: AXObserver?
        let context: ObserverContext
        let registeredNotifications: [CFString]
        let lastResult: AXError
        let destroyedWindowElements: [String: AXUIElement]
        let initialReadback: RuntimeAXWindowInitialReadbackEvidence?

        var isInstalled: Bool {
            observer != nil && !registeredNotifications.isEmpty
        }
    }

    private struct ObserverInstallWork: @unchecked Sendable {
        let pid: pid_t
        let expectedWindowCount: Int
        let notifications: [CFString]
        let callback: AXObserverCallback
        let context: ObserverContext
    }

    private struct ObserverRemovalWork: @unchecked Sendable {
        let observer: AXObserver
        let context: ObserverContext
        let pid: pid_t
        let registeredNotifications: [CFString]
        let destroyedWindowElements: [String: AXUIElement]
    }

    private struct DestroyedWindowSyncWork: @unchecked Sendable {
        let observer: AXObserver
        let context: ObserverContext
        let currentWindowElements: [String: AXUIElement]
        let observedWindowElements: [String: AXUIElement]
    }

    private struct DestroyedWindowSyncWorkResult: @unchecked Sendable {
        let observedWindowElements: [String: AXUIElement]
    }

    var onAppWindowChanged: ((RuntimeAXWindowChangeEvidence) -> Void)?
    var onAXWindowDestroyed: ((String, pid_t, String) -> Void)?

    private var observersByPID: [pid_t: AXObserver] = [:]
    private var observerContextByPID: [pid_t: ObserverContext] = [:]
    private var appIDByPID: [pid_t: String] = [:]
    private var registeredNotificationsByPID: [pid_t: [CFString]] = [:]
    private var destroyedWindowElementsByPID: [pid_t: [String: AXUIElement]] = [:]
    private var desiredAppIDsByPID: [pid_t: String] = [:]
    private var pendingObserverInstallsByPID: [pid_t: PendingObserverInstall] = [:]
    private var unavailableAppIDsByPID: [pid_t: String] = [:]
    private var pendingDestroyedWindowSyncContextsByPID: [pid_t: ObserverContext] = [:]
    private var nextObserverInstallGeneration: UInt64 = 1
    private let deliveryCoordinator: RuntimeAXWindowChangeDeliveryCoordinator
    private let observationWorkScheduler: any RuntimeAXWindowObservationWorkScheduling
    private let accessibilityTrustProvider: () -> Bool
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
        deliveryScheduler: (any RuntimeAXWindowChangeDeliveryScheduling)? = nil,
        observationWorkScheduler: (any RuntimeAXWindowObservationWorkScheduling)? = nil,
        accessibilityTrustProvider: @escaping () -> Bool = {
            AccessibilityPermissionChecker.isTrusted()
        }
    ) {
        deliveryCoordinator = RuntimeAXWindowChangeDeliveryCoordinator(
            policy: deliveryPolicy,
            scheduler: deliveryScheduler
        )
        self.observationWorkScheduler =
            observationWorkScheduler ?? RuntimeAXWindowObservationWorkScheduler()
        self.accessibilityTrustProvider = accessibilityTrustProvider
        deliveryCoordinator.onEvidence = { [weak self] evidence in
            self?.onAppWindowChanged?(evidence)
        }
    }

    func rebind(_ appSummaries: [RuntimeHomeAppSummary]) {
        guard accessibilityTrustProvider() else {
            stop()
            return
        }

        let expectedByPID = Self.expectedAppIDsByPID(from: appSummaries)
        desiredAppIDsByPID = expectedByPID
        unavailableAppIDsByPID = unavailableAppIDsByPID.filter {
            expectedByPID[$0.key] == $0.value
        }

        for pid in Array(pendingObserverInstallsByPID.keys) {
            guard let pending = pendingObserverInstallsByPID[pid],
                  expectedByPID[pid] == pending.appID
            else {
                invalidatePendingObserverInstall(pid: pid)
                continue
            }
        }

        for pid in Array(observersByPID.keys) {
            guard let expectedAppID = expectedByPID[pid], expectedAppID == appIDByPID[pid] else {
                removeObserver(pid: pid)
                continue
            }
        }

        for (pid, appID) in expectedByPID {
            if observersByPID[pid] != nil {
                syncDestroyedWindowObservers(pid: pid)
                continue
            }
            guard pendingObserverInstallsByPID[pid]?.appID != appID,
                  unavailableAppIDsByPID[pid] != appID,
                  let summary = appSummaries.last(where: { $0.pid == pid })
            else { continue }

            scheduleObserverInstall(
                appID: appID,
                pid: pid,
                expectedWindowCount: summary.windowCount
            )
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
        desiredAppIDsByPID.removeAll()
        unavailableAppIDsByPID.removeAll()
        for pid in Array(pendingObserverInstallsByPID.keys) {
            invalidatePendingObserverInstall(pid: pid)
        }
        for pid in Array(observersByPID.keys) {
            removeObserver(pid: pid)
        }
        pendingDestroyedWindowSyncContextsByPID.removeAll()
        deliveryCoordinator.stop()
    }

    func observe(
        appID: String,
        pid: pid_t
    ) -> RuntimeAXWindowObservationInstallEvidence {
        invalidatePendingObserverInstall(pid: pid)
        unavailableAppIDsByPID.removeValue(forKey: pid)
        if observersByPID[pid] != nil, appIDByPID[pid] == appID {
            return .installed
        }
        if observersByPID[pid] != nil {
            removeObserver(pid: pid)
        }
        return installObserver(pid: pid, appID: appID)
    }

    func stopObserving(pid: pid_t) {
        desiredAppIDsByPID.removeValue(forKey: pid)
        unavailableAppIDsByPID.removeValue(forKey: pid)
        invalidatePendingObserverInstall(pid: pid)
        removeObserver(pid: pid)
    }

    private func scheduleObserverInstall(
        appID: String,
        pid: pid_t,
        expectedWindowCount: Int
    ) {
        let bindingGeneration = deliveryCoordinator.bind(appID: appID, pid: pid)
        let generation = nextObserverInstallGeneration
        nextObserverInstallGeneration &+= 1
        let context = ObserverContext(
            monitor: self,
            appID: appID,
            pid: pid,
            bindingGeneration: bindingGeneration
        )
        pendingObserverInstallsByPID[pid] = PendingObserverInstall(
            appID: appID,
            generation: generation,
            bindingGeneration: bindingGeneration,
            context: context
        )

        let work = ObserverInstallWork(
            pid: pid,
            expectedWindowCount: expectedWindowCount,
            notifications: watchedNotifications,
            callback: Self.callback,
            context: context
        )
        observationWorkScheduler.schedule { [weak self] in
            let result = Self.makeObserverInstallWorkResult(
                pid: work.pid,
                expectedWindowCount: work.expectedWindowCount,
                notifications: work.notifications,
                callback: work.callback,
                context: work.context
            )
            Task { @MainActor [weak self] in
                self?.finishObserverInstall(
                    appID: appID,
                    pid: pid,
                    generation: generation,
                    result: result
                )
            }
        }
    }

    nonisolated private static func makeObserverInstallWorkResult(
        pid: pid_t,
        expectedWindowCount: Int,
        notifications: [CFString],
        callback: AXObserverCallback,
        context: ObserverContext
    ) -> ObserverInstallWorkResult {
        var observerRef: AXObserver?
        let createResult = AXObserverCreate(pid, callback, &observerRef)
        guard createResult == .success, let observerRef else {
            return ObserverInstallWorkResult(
                observer: nil,
                context: context,
                registeredNotifications: [],
                lastResult: createResult == .success ? .failure : createResult,
                destroyedWindowElements: [:],
                initialReadback: nil
            )
        }

        let contextPointer = UnsafeMutableRawPointer(
            Unmanaged.passUnretained(context).toOpaque()
        )
        let appElement = AXUIElementCreateApplication(pid)
        let registration = RuntimeAXWindowObservationRegistrationPolicy.register(
            element: appElement,
            notifications: notifications
        ) { element, notification in
            AXObserverAddNotification(
                observerRef,
                element,
                notification,
                contextPointer
            )
        }
        guard !registration.registeredNotifications.isEmpty else {
            return ObserverInstallWorkResult(
                observer: observerRef,
                context: context,
                registeredNotifications: [],
                lastResult: registration.lastResult,
                destroyedWindowElements: [:],
                initialReadback: nil
            )
        }

        let knownWindowElements = AXLiveWindowRegistry.shared.windows(forPID: pid)
        let destroyedWindowElements = synchronizeDestroyedWindowRegistrations(
            observer: observerRef,
            context: context,
            currentWindows: knownWindowElements,
            observedWindows: [:]
        )
        return ObserverInstallWorkResult(
            observer: observerRef,
            context: context,
            registeredNotifications: registration.registeredNotifications,
            lastResult: registration.lastResult,
            destroyedWindowElements: destroyedWindowElements,
            initialReadback: initialReadbackEvidence(
                pid: pid,
                expectedWindowCount: expectedWindowCount,
                knownWindowElements: Array(knownWindowElements.values)
            )
        )
    }

    private func finishObserverInstall(
        appID: String,
        pid: pid_t,
        generation: UInt64,
        result: ObserverInstallWorkResult
    ) {
        guard let pending = pendingObserverInstallsByPID[pid],
              pending.appID == appID,
              pending.generation == generation
        else {
            scheduleObserverInstallCleanup(pid: pid, result: result)
            return
        }
        pendingObserverInstallsByPID.removeValue(forKey: pid)

        guard desiredAppIDsByPID[pid] == appID,
              result.isInstalled,
              let observer = result.observer
        else {
            if desiredAppIDsByPID[pid] == appID {
                unavailableAppIDsByPID[pid] = appID
                RuntimeLog.debug(
                    .axObserver,
                    "homeAXObserverInstall result=unavailable appID=\(appID) pid=\(pid) axError=\(result.lastResult.rawValue)"
                )
            }
            deliveryCoordinator.unbind(
                pid: pid,
                bindingGeneration: pending.bindingGeneration
            )
            scheduleObserverInstallCleanup(pid: pid, result: result)
            return
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        observersByPID[pid] = observer
        observerContextByPID[pid] = pending.context
        appIDByPID[pid] = appID
        registeredNotificationsByPID[pid] = result.registeredNotifications
        destroyedWindowElementsByPID[pid] = result.destroyedWindowElements
        unavailableAppIDsByPID.removeValue(forKey: pid)

        if let initialReadback = result.initialReadback {
            deliveryCoordinator.publishInitialReadback(
                pid: pid,
                bindingGeneration: pending.bindingGeneration,
                readback: initialReadback
            )
        }
        RuntimeLog.debug(
            .axObserver,
            "homeAXObserverInstall result=installed appID=\(appID) pid=\(pid) notifications=\(result.registeredNotifications.count)"
        )
    }

    private func invalidatePendingObserverInstall(pid: pid_t) {
        guard let pending = pendingObserverInstallsByPID.removeValue(forKey: pid) else {
            return
        }
        deliveryCoordinator.unbind(
            pid: pid,
            bindingGeneration: pending.bindingGeneration
        )
    }

    private func scheduleObserverInstallCleanup(
        pid: pid_t,
        result: ObserverInstallWorkResult
    ) {
        guard let observer = result.observer else { return }
        scheduleObserverRemoval(
            ObserverRemovalWork(
                observer: observer,
                context: result.context,
                pid: pid,
                registeredNotifications: result.registeredNotifications,
                destroyedWindowElements: result.destroyedWindowElements
            )
        )
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
        let registration = RuntimeAXWindowObservationRegistrationPolicy.register(
            element: appElement,
            notifications: watchedNotifications
        ) { element, notification in
            AXObserverAddNotification(
                observerRef,
                element,
                notification,
                contextPointer
            )
        }
        guard !registration.registeredNotifications.isEmpty else {
            deliveryCoordinator.unbind(
                pid: pid,
                bindingGeneration: bindingGeneration
            )
            return .unavailable(error: registration.lastResult)
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observerRef),
            .defaultMode
        )
        observersByPID[pid] = observerRef
        observerContextByPID[pid] = context
        appIDByPID[pid] = appID
        registeredNotificationsByPID[pid] = registration.registeredNotifications
        syncDestroyedWindowObservers(pid: pid)
        return .installed
    }

    private func removeObserver(pid: pid_t) {
        guard let observer = observersByPID.removeValue(forKey: pid) else {
            observerContextByPID.removeValue(forKey: pid)
            appIDByPID.removeValue(forKey: pid)
            registeredNotificationsByPID.removeValue(forKey: pid)
            destroyedWindowElementsByPID.removeValue(forKey: pid)
            pendingDestroyedWindowSyncContextsByPID.removeValue(forKey: pid)
            return
        }
        let context = observerContextByPID.removeValue(forKey: pid)
        let registeredNotifications = registeredNotificationsByPID.removeValue(forKey: pid) ?? []
        let destroyedWindowElements = destroyedWindowElementsByPID.removeValue(forKey: pid) ?? [:]

        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        appIDByPID.removeValue(forKey: pid)
        if pendingDestroyedWindowSyncContextsByPID[pid] === context {
            pendingDestroyedWindowSyncContextsByPID.removeValue(forKey: pid)
        }
        deliveryCoordinator.unbind(
            pid: pid,
            bindingGeneration: context?.bindingGeneration
        )
        if let context {
            scheduleObserverRemoval(
                ObserverRemovalWork(
                    observer: observer,
                    context: context,
                    pid: pid,
                    registeredNotifications: registeredNotifications,
                    destroyedWindowElements: destroyedWindowElements
                )
            )
        }
    }

    private func syncDestroyedWindowObservers(pid: pid_t) {
        guard
            let observer = observersByPID[pid],
            let context = observerContextByPID[pid],
            pendingDestroyedWindowSyncContextsByPID[pid] == nil
        else { return }

        let work = DestroyedWindowSyncWork(
            observer: observer,
            context: context,
            currentWindowElements: AXLiveWindowRegistry.shared.windows(forPID: pid),
            observedWindowElements: destroyedWindowElementsByPID[pid] ?? [:]
        )
        pendingDestroyedWindowSyncContextsByPID[pid] = context
        observationWorkScheduler.schedule { [weak self] in
            let result = DestroyedWindowSyncWorkResult(
                observedWindowElements: Self.synchronizeDestroyedWindowRegistrations(
                    observer: work.observer,
                    context: work.context,
                    currentWindows: work.currentWindowElements,
                    observedWindows: work.observedWindowElements
                )
            )
            Task { @MainActor [weak self] in
                self?.finishDestroyedWindowSync(
                    pid: pid,
                    work: work,
                    result: result
                )
            }
        }
    }

    private func finishDestroyedWindowSync(
        pid: pid_t,
        work: DestroyedWindowSyncWork,
        result: DestroyedWindowSyncWorkResult
    ) {
        if pendingDestroyedWindowSyncContextsByPID[pid] === work.context {
            pendingDestroyedWindowSyncContextsByPID.removeValue(forKey: pid)
        }
        guard observerContextByPID[pid] === work.context else {
            scheduleDestroyedWindowRegistrationCleanup(
                observer: work.observer,
                context: work.context,
                windowElements: result.observedWindowElements
            )
            return
        }
        destroyedWindowElementsByPID[pid] = result.observedWindowElements
    }

    nonisolated private static func synchronizeDestroyedWindowRegistrations(
        observer: AXObserver,
        context: ObserverContext,
        currentWindows: [String: AXUIElement],
        observedWindows: [String: AXUIElement]
    ) -> [String: AXUIElement] {
        var synchronizedWindows = observedWindows
        for (windowID, observedElement) in synchronizedWindows {
            guard let currentElement = currentWindows[windowID],
                  CFEqual(currentElement, observedElement)
            else {
                RuntimeAXMessagingTimeoutPolicy.apply(to: observedElement)
                AXObserverRemoveNotification(
                    observer,
                    observedElement,
                    kAXUIElementDestroyedNotification as CFString
                )
                synchronizedWindows.removeValue(forKey: windowID)
                continue
            }
        }

        let contextPointer = UnsafeMutableRawPointer(
            Unmanaged.passUnretained(context).toOpaque()
        )
        for (windowID, windowElement) in currentWindows
        where synchronizedWindows[windowID] == nil {
            let registration = RuntimeAXWindowObservationRegistrationPolicy.register(
                element: windowElement,
                notifications: [kAXUIElementDestroyedNotification as CFString]
            ) { element, notification in
                AXObserverAddNotification(
                    observer,
                    element,
                    notification,
                    contextPointer
                )
            }
            guard !registration.registeredNotifications.isEmpty else { continue }
            synchronizedWindows[windowID] = windowElement
        }
        return synchronizedWindows
    }

    private func scheduleObserverRemoval(_ work: ObserverRemovalWork) {
        guard !work.registeredNotifications.isEmpty ||
                !work.destroyedWindowElements.isEmpty
        else { return }
        observationWorkScheduler.schedule {
            Self.removeObserverRegistrations(work)
        }
    }

    private func scheduleDestroyedWindowRegistrationCleanup(
        observer: AXObserver,
        context: ObserverContext,
        windowElements: [String: AXUIElement]
    ) {
        guard !windowElements.isEmpty else { return }
        let work = ObserverRemovalWork(
            observer: observer,
            context: context,
            pid: 0,
            registeredNotifications: [],
            destroyedWindowElements: windowElements
        )
        observationWorkScheduler.schedule {
            Self.removeObserverRegistrations(work)
        }
    }

    nonisolated private static func removeObserverRegistrations(
        _ work: ObserverRemovalWork
    ) {
        withExtendedLifetime(work.context) {
            for windowElement in work.destroyedWindowElements.values {
                RuntimeAXMessagingTimeoutPolicy.apply(to: windowElement)
                AXObserverRemoveNotification(
                    work.observer,
                    windowElement,
                    kAXUIElementDestroyedNotification as CFString
                )
            }
            guard !work.registeredNotifications.isEmpty else { return }

            let appElement = AXUIElementCreateApplication(work.pid)
            RuntimeAXMessagingTimeoutPolicy.apply(to: appElement)
            for notification in work.registeredNotifications {
                let result = AXObserverRemoveNotification(
                    work.observer,
                    appElement,
                    notification
                )
                if RuntimeAXWindowObservationRegistrationPolicy
                    .isTerminalRemoteFailure(result)
                {
                    break
                }
            }
        }
    }

    nonisolated private static func initialReadbackEvidence(
        pid: pid_t,
        expectedWindowCount: Int,
        knownWindowElements: [AXUIElement]
    ) -> RuntimeAXWindowInitialReadbackEvidence {
        RuntimeAXMessagingTimeoutPolicy.apply(to: knownWindowElements)
        let knownWindows = knownWindowElements.filter(
            AXWindowInspector.isSwitchable
        )
        let appElement = AXUIElementCreateApplication(pid)
        RuntimeAXMessagingTimeoutPolicy.apply(to: appElement)
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
                expectedWindowCount: expectedWindowCount,
                knownSwitchableWindowCount: knownWindows.count,
                observedSwitchableWindowCount: nil,
                exactKnownWindowCount: 0,
                fetchErrorRawValue: fetchError.rawValue,
                rawValueTypeDescription: rawValueTypeDescription
            )
        }

        RuntimeAXMessagingTimeoutPolicy.apply(to: currentWindows)
        let currentSwitchableWindows = currentWindows.filter(
            AXWindowInspector.isSwitchable
        )
        return RuntimeAXWindowInitialReadbackEvidence.evaluate(
            expectedWindowCount: expectedWindowCount,
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

    nonisolated static func exactKnownWindowCount(
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
