import AppKit
import ApplicationServices
import Foundation
import FlowTabCore

enum RuntimeAXWindowObservationInstallEvidence: Equatable {
    case installed
    case unavailable(error: AXError)
}

struct RuntimeAXWindowElementRegistrationDiff {
    let retained: [AXUIElement]
    let removed: [AXUIElement]
    let added: [AXUIElement]

    static func resolve(
        currentWindows: [AXUIElement],
        observedWindows: [AXUIElement]
    ) -> RuntimeAXWindowElementRegistrationDiff {
        var unmatchedCurrentWindows = currentWindows
        var retained: [AXUIElement] = []
        var removed: [AXUIElement] = []
        for observedElement in observedWindows {
            guard let currentIndex = unmatchedCurrentWindows.firstIndex(
                where: { CFEqual($0, observedElement) }
            ) else {
                removed.append(observedElement)
                continue
            }
            retained.append(observedElement)
            unmatchedCurrentWindows.remove(at: currentIndex)
        }
        return RuntimeAXWindowElementRegistrationDiff(
            retained: retained,
            removed: removed,
            added: unmatchedCurrentWindows
        )
    }
}

@MainActor
protocol RuntimeAXWindowChangeMonitoring: AnyObject {
    var onAppWindowChanged: ((RuntimeAXWindowChangeEvidence) -> Void)? { get set }

    func observe(appID: String, pid: pid_t) -> RuntimeAXWindowObservationInstallEvidence
    func stopObserving(pid: pid_t)
    func stop()
}

@MainActor
final class RuntimeAXWindowChangeMonitor: RuntimeAXWindowChangeMonitoring {
    final class ObserverContext: @unchecked Sendable {
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
        let expectedWindowCount: Int
        let context: ObserverContext
    }

    private struct ObserverRemovalWork: @unchecked Sendable {
        let observer: AXObserver
        let context: ObserverContext
        let pid: pid_t
        let registeredNotifications: [CFString]
        let destroyedWindowElements: [AXUIElement]
    }

    private struct DestroyedWindowSyncWork: @unchecked Sendable {
        let observer: AXObserver
        let context: ObserverContext
        let observedWindowElements: [AXUIElement]
    }

    private struct DestroyedWindowSyncWorkResult: @unchecked Sendable {
        let observedWindowElements: [AXUIElement]
    }

    var onAppWindowChanged: ((RuntimeAXWindowChangeEvidence) -> Void)?

    private var observersByPID: [pid_t: AXObserver] = [:]
    private var observerContextByPID: [pid_t: ObserverContext] = [:]
    private var appIDByPID: [pid_t: String] = [:]
    private var registeredNotificationsByPID: [pid_t: [CFString]] = [:]
    private var destroyedWindowElementsByPID: [pid_t: [AXUIElement]] = [:]
    private var desiredAppIDsByPID: [pid_t: String] = [:]
    private var desiredWindowCountsByPID: [pid_t: Int] = [:]
    private var pendingObserverInstallsByPID: [pid_t: PendingObserverInstall] = [:]
    private var terminalUnavailableAppIDsByPID: [pid_t: String] = [:]
    private var pendingDestroyedWindowSyncContextsByPID: [pid_t: ObserverContext] = [:]
    private var pendingDestroyedWindowSyncRefreshPIDs: Set<pid_t> = []
    private var nextObserverInstallGeneration: UInt64 = 1
    private let deliveryCoordinator: RuntimeAXWindowChangeDeliveryCoordinator
    private let observationWorkScheduler: any RuntimeAXWindowObservationWorkScheduling
    private let observerInstaller: any RuntimeAXWindowObserverInstalling
    private let retryCoordinator: RuntimeAXWindowObservationRetryCoordinator
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
        observerInstaller: (any RuntimeAXWindowObserverInstalling)? = nil,
        retryPolicy: RuntimeAXWindowObservationRetryPolicy = .standard,
        retryScheduler: (any RuntimeAXWindowObservationRetryScheduling)? = nil,
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
        self.observerInstaller =
            observerInstaller ?? RuntimeAXWindowObserverInstaller()
        retryCoordinator = RuntimeAXWindowObservationRetryCoordinator(
            policy: retryPolicy,
            scheduler: retryScheduler
        )
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
        desiredWindowCountsByPID = appSummaries.reduce(into: [:]) {
            countsByPID, summary in
            guard expectedByPID[summary.pid] == summary.appID else { return }
            countsByPID[summary.pid] = summary.windowCount
        }
        terminalUnavailableAppIDsByPID = terminalUnavailableAppIDsByPID.filter {
            expectedByPID[$0.key] == $0.value
        }
        retryCoordinator.retainBindings(expectedByPID)

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
                  !retryCoordinator.hasPending(appID: appID, pid: pid),
                  terminalUnavailableAppIDsByPID[pid] != appID,
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
        desiredWindowCountsByPID.removeAll()
        terminalUnavailableAppIDsByPID.removeAll()
        retryCoordinator.stop()
        for pid in Array(pendingObserverInstallsByPID.keys) {
            invalidatePendingObserverInstall(pid: pid)
        }
        for pid in Array(observersByPID.keys) {
            removeObserver(pid: pid)
        }
        pendingDestroyedWindowSyncContextsByPID.removeAll()
        pendingDestroyedWindowSyncRefreshPIDs.removeAll()
        deliveryCoordinator.stop()
    }

    func observe(
        appID: String,
        pid: pid_t
    ) -> RuntimeAXWindowObservationInstallEvidence {
        retryCoordinator.cancel(pid: pid, reason: "explicitObservation")
        invalidatePendingObserverInstall(pid: pid)
        terminalUnavailableAppIDsByPID.removeValue(forKey: pid)
        if observersByPID[pid] != nil, appIDByPID[pid] == appID {
            syncDestroyedWindowObservers(pid: pid)
            return .installed
        }
        if observersByPID[pid] != nil {
            removeObserver(pid: pid)
        }
        return installObserver(pid: pid, appID: appID)
    }

    func stopObserving(pid: pid_t) {
        desiredAppIDsByPID.removeValue(forKey: pid)
        desiredWindowCountsByPID.removeValue(forKey: pid)
        terminalUnavailableAppIDsByPID.removeValue(forKey: pid)
        retryCoordinator.cancel(pid: pid, reason: "observationStopped")
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
            expectedWindowCount: expectedWindowCount,
            context: context
        )

        let request = RuntimeAXWindowObserverInstallRequest(
            pid: pid,
            expectedWindowCount: expectedWindowCount,
            notifications: watchedNotifications,
            callback: Self.callback,
            context: context
        )
        let observerInstaller = observerInstaller
        observationWorkScheduler.schedule { [weak self] in
            let result = observerInstaller.install(request)
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

    private func finishObserverInstall(
        appID: String,
        pid: pid_t,
        generation: UInt64,
        result: RuntimeAXWindowObserverInstallResult
    ) {
        guard let pending = pendingObserverInstallsByPID[pid],
              pending.appID == appID,
              pending.generation == generation,
              result.context === pending.context,
              result.context.appID == appID,
              result.context.pid == pid,
              result.context.bindingGeneration
                == pending.bindingGeneration
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
                let failedExpectedWindowCount = pending.expectedWindowCount
                let retry = retryCoordinator.schedule(
                    appID: appID,
                    pid: pid,
                    installGeneration: generation,
                    error: result.lastResult
                ) { [weak self] _ in
                    guard let self,
                          self.desiredAppIDsByPID[pid] == appID,
                          self.observersByPID[pid] == nil,
                          self.pendingObserverInstallsByPID[pid] == nil
                    else {
                        self?.retryCoordinator.cancel(
                            pid: pid,
                            reason: "bindingUnavailable"
                        )
                        return
                    }
                    self.scheduleObserverInstall(
                        appID: appID,
                        pid: pid,
                        expectedWindowCount:
                            self.desiredWindowCountsByPID[pid]
                            ?? failedExpectedWindowCount
                    )
                }
                if retry == nil {
                    terminalUnavailableAppIDsByPID[pid] = appID
                    RuntimeLog.debug(
                        .axObserver,
                        "homeAXObserverInstall result=terminalUnavailable appID=\(appID) pid=\(pid) installGeneration=\(generation) axError=\(result.lastResult.rawValue)"
                    )
                }
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
        terminalUnavailableAppIDsByPID.removeValue(forKey: pid)
        let retryAttempt = retryCoordinator.complete(pid: pid, appID: appID) ?? 0

        if let initialReadback = result.initialReadback {
            deliveryCoordinator.publishInitialReadback(
                pid: pid,
                bindingGeneration: pending.bindingGeneration,
                readback: initialReadback
            )
        }
        RuntimeLog.debug(
            .axObserver,
            "homeAXObserverInstall result=installed appID=\(appID) pid=\(pid) installGeneration=\(generation) retryAttempt=\(retryAttempt) notifications=\(result.registeredNotifications.count)"
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
        result: RuntimeAXWindowObserverInstallResult
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
            pendingDestroyedWindowSyncRefreshPIDs.remove(pid)
            return
        }
        let context = observerContextByPID.removeValue(forKey: pid)
        let registeredNotifications = registeredNotificationsByPID.removeValue(forKey: pid) ?? []
        let destroyedWindowElements = destroyedWindowElementsByPID.removeValue(forKey: pid) ?? []

        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        appIDByPID.removeValue(forKey: pid)
        if pendingDestroyedWindowSyncContextsByPID[pid] === context {
            pendingDestroyedWindowSyncContextsByPID.removeValue(forKey: pid)
        }
        pendingDestroyedWindowSyncRefreshPIDs.remove(pid)
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
        guard let observer = observersByPID[pid],
              let context = observerContextByPID[pid]
        else { return }
        guard pendingDestroyedWindowSyncContextsByPID[pid] == nil else {
            pendingDestroyedWindowSyncRefreshPIDs.insert(pid)
            return
        }

        let work = DestroyedWindowSyncWork(
            observer: observer,
            context: context,
            observedWindowElements: destroyedWindowElementsByPID[pid] ?? []
        )
        pendingDestroyedWindowSyncContextsByPID[pid] = context
        observationWorkScheduler.schedule { [weak self] in
            let result = DestroyedWindowSyncWorkResult(
                observedWindowElements: Self.synchronizeDestroyedWindowRegistrations(
                    observer: work.observer,
                    context: work.context,
                    currentWindows: Self.currentDestroyedWindowElements(
                        pid: work.context.pid
                    ),
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
        let completedCurrentSync =
            pendingDestroyedWindowSyncContextsByPID[pid] === work.context
        if completedCurrentSync {
            pendingDestroyedWindowSyncContextsByPID.removeValue(forKey: pid)
        }
        let refreshRequested = completedCurrentSync
            && pendingDestroyedWindowSyncRefreshPIDs.remove(pid) != nil
        guard observerContextByPID[pid] === work.context else {
            scheduleDestroyedWindowRegistrationCleanup(
                observer: work.observer,
                context: work.context,
                windowElements: result.observedWindowElements
            )
            return
        }
        destroyedWindowElementsByPID[pid] = result.observedWindowElements
        if refreshRequested {
            syncDestroyedWindowObservers(pid: pid)
        }
    }

    nonisolated static func synchronizeDestroyedWindowRegistrations(
        observer: AXObserver,
        context: ObserverContext,
        currentWindows: [AXUIElement],
        observedWindows: [AXUIElement]
    ) -> [AXUIElement] {
        let diff = RuntimeAXWindowElementRegistrationDiff.resolve(
            currentWindows: currentWindows,
            observedWindows: observedWindows
        )
        for removedElement in diff.removed {
            RuntimeAXMessagingTimeoutPolicy.apply(to: removedElement)
            AXObserverRemoveNotification(
                observer,
                removedElement,
                kAXUIElementDestroyedNotification as CFString
            )
        }

        var synchronizedWindows = diff.retained
        let contextPointer = UnsafeMutableRawPointer(
            Unmanaged.passUnretained(context).toOpaque()
        )
        for windowElement in diff.added {
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
            synchronizedWindows.append(windowElement)
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
        windowElements: [AXUIElement]
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
            for windowElement in work.destroyedWindowElements {
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

    nonisolated static func initialReadbackEvidence(
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
        element _: AXUIElement,
        bindingGeneration: UInt64
    ) {
        guard let changeKind = Self.changeKind(for: notification) else {
            return
        }
        if changeKind == .created {
            syncDestroyedWindowObservers(pid: pid)
        }
        if changeKind == .destroyed {
            RuntimeLog.debug(
                .axObserver,
                "homeAXDestroyed topologyInvalidated appID=\(appID) pid=\(pid)"
            )
        }
        deliveryCoordinator.recordObservedTransition(
            pid: pid,
            bindingGeneration: bindingGeneration,
            changeKind: changeKind
        )
    }

    nonisolated static func changeKind(
        for notification: CFString
    ) -> RuntimeAXWindowChangeEvidence.ChangeKind? {
        switch notification as String {
        case kAXWindowCreatedNotification as String:
            .created
        case kAXUIElementDestroyedNotification as String:
            .destroyed
        case kAXFocusedWindowChangedNotification as String,
             kAXMainWindowChangedNotification as String:
            .focus
        case kAXWindowMiniaturizedNotification as String,
             kAXWindowDeminiaturizedNotification as String:
            .visibility
        default:
            nil
        }
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
