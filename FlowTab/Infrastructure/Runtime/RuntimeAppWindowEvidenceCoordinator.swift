import AppKit
import Foundation

@MainActor
protocol RuntimeAppWindowEvidenceCoordinating: AnyObject {
    func start()
    func reconcileNow()
    func applicationDidLaunch(appID: String, pid: pid_t)
    func applicationDidTerminate(appID: String, pid: pid_t)
    func stop()
}

@MainActor
final class RuntimeAppWindowEvidenceCoordinator:
    RuntimeAppWindowEvidenceCoordinating
{
    private let monitor: any RuntimeAXWindowChangeMonitoring
    private let permissionObservationCoordinator:
        RuntimePermissionObservationCoordinator
    private let notificationCenter: NotificationCenter
    private let currentPID: pid_t
    private let readAccessibilityPermission: @MainActor () -> Bool
    private let bindingProvider:
        @MainActor () -> [RuntimeAXWindowObservationBinding]
    private let onAppWindowEvidence:
        @MainActor (RuntimeAXWindowChangeEvidence) -> Void
    private var bindingsByPID:
        [pid_t: RuntimeAXWindowObservationBinding] = [:]
    private var isStarted = false
    private var accessibilityTrusted: Bool?
    private var projectionObserver: NSObjectProtocol?

    init(
        monitor: any RuntimeAXWindowChangeMonitoring,
        permissionObservationCoordinator:
            RuntimePermissionObservationCoordinator? = nil,
        notificationCenter: NotificationCenter = .default,
        currentPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        readAccessibilityPermission:
            @escaping @MainActor () -> Bool = {
                AccessibilityPermissionChecker.isTrusted()
            },
        bindingProvider:
            @escaping @MainActor () -> [RuntimeAXWindowObservationBinding],
        onAppWindowEvidence:
            @escaping @MainActor (RuntimeAXWindowChangeEvidence) -> Void
    ) {
        self.monitor = monitor
        self.permissionObservationCoordinator =
            permissionObservationCoordinator
                ?? RuntimePermissionObservationCoordinator()
        self.notificationCenter = notificationCenter
        self.currentPID = currentPID
        self.readAccessibilityPermission = readAccessibilityPermission
        self.bindingProvider = bindingProvider
        self.onAppWindowEvidence = onAppWindowEvidence
    }

    convenience init(
        runtimeProjectionService: any RuntimeProjectionServing,
        monitor: (any RuntimeAXWindowChangeMonitoring)? = nil,
        permissionObservationCoordinator:
            RuntimePermissionObservationCoordinator? = nil,
        notificationCenter: NotificationCenter = .default,
        currentPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        readAccessibilityPermission:
            @escaping @MainActor () -> Bool = {
                AccessibilityPermissionChecker.isTrusted()
            }
    ) {
        self.init(
            monitor: monitor
                ?? RuntimeAXWindowChangeMonitor(
                    deliveryPolicy: .standardCoalesced
                ),
            permissionObservationCoordinator:
                permissionObservationCoordinator,
            notificationCenter: notificationCenter,
            currentPID: currentPID,
            readAccessibilityPermission: readAccessibilityPermission,
            bindingProvider: {
                Self.currentBindings(
                    runtimeProjectionService: runtimeProjectionService,
                    currentPID: currentPID
                )
            },
            onAppWindowEvidence: { evidence in
                runtimeProjectionService.consumeAXWindowChangeEvidence(
                    evidence
                )
            }
        )
    }

    deinit {
        if let projectionObserver {
            notificationCenter.removeObserver(projectionObserver)
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        projectionObserver = notificationCenter.addObserver(
            forName: .runtimeAppSwitcherProjectionDidUpdate,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.consumeProjectionUpdate()
            }
        }
        monitor.onAppWindowChanged = { [weak self] evidence in
            self?.onAppWindowEvidence(evidence)
        }
        permissionObservationCoordinator.start(
            target: .accessibility,
            mode: .whileOwned,
            readPermission: readAccessibilityPermission,
            onEvidence: { [weak self] evidence in
                self?.consumePermissionEvidence(evidence)
            },
            onWatchdog: { diagnostic in
                RuntimeLog.info(.permission, diagnostic.logMessage)
            }
        )
    }

    func reconcileNow() {
        guard isStarted else { return }
        let evidence = permissionObservationCoordinator.readback(
            target: .accessibility,
            source: .appActivation
        )
        guard evidence?.isGranted == true else { return }
        replaceBindingsFromProvider()
    }

    func applicationDidLaunch(appID: String, pid: pid_t) {
        guard isStarted, accessibilityTrusted == true,
              pid > 0, pid != currentPID
        else {
            return
        }
        let expectedWindowCount = RuntimeAXWindowObservationBindingCollection(
            bindingProvider(),
            currentPID: currentPID
        ).binding(appID: appID, pid: pid)?.expectedWindowCount ?? 0
        var desired = bindingsByPID
        desired[pid] = RuntimeAXWindowObservationBinding(
            appID: appID,
            pid: pid,
            expectedWindowCount: expectedWindowCount
        )
        publishBindingsIfChanged(desired)
    }

    func applicationDidTerminate(appID: String, pid: pid_t) {
        guard isStarted, accessibilityTrusted == true,
              let current = bindingsByPID[pid],
              current.appID == appID
        else {
            return
        }
        var desired = bindingsByPID
        desired.removeValue(forKey: pid)
        publishBindingsIfChanged(desired)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        permissionObservationCoordinator.cancel(target: .accessibility)
        if let projectionObserver {
            notificationCenter.removeObserver(projectionObserver)
            self.projectionObserver = nil
        }
        accessibilityTrusted = nil
        bindingsByPID.removeAll()
        monitor.onAppWindowChanged = nil
        monitor.stop()
    }

    private func consumePermissionEvidence(
        _ evidence: RuntimePermissionObservationEvidence
    ) {
        guard isStarted else { return }
        let previousTrust = accessibilityTrusted
        accessibilityTrusted = evidence.isGranted
        guard evidence.isGranted else {
            guard previousTrust != false else { return }
            bindingsByPID.removeAll()
            monitor.stop()
            return
        }
        guard previousTrust != true else { return }
        replaceBindingsFromProvider()
    }

    private func replaceBindingsFromProvider() {
        let desired = RuntimeAXWindowObservationBindingCollection(
            bindingProvider(),
            currentPID: currentPID
        ).byPID
        publishBindingsIfChanged(desired)
    }

    private func consumeProjectionUpdate() {
        guard isStarted, accessibilityTrusted == true else { return }
        replaceBindingsFromProvider()
    }

    private func publishBindingsIfChanged(
        _ desired: [pid_t: RuntimeAXWindowObservationBinding]
    ) {
        guard desired != bindingsByPID else { return }
        bindingsByPID = desired
        monitor.rebind(
            desired.values.sorted {
                if $0.pid != $1.pid {
                    return $0.pid < $1.pid
                }
                return $0.appID < $1.appID
            }
        )
    }

    private static func currentBindings(
        runtimeProjectionService: any RuntimeProjectionServing,
        currentPID: pid_t
    ) -> [RuntimeAXWindowObservationBinding] {
        let expectedCounts =
            runtimeProjectionService.readHomeSummaryProjection()?.summaries
                .reduce(into: [RuntimeAXWindowObservationIdentity: Int]()) {
                    counts, summary in
                    let identity = RuntimeAXWindowObservationIdentity(
                        appID: summary.appID,
                        pid: summary.pid
                    )
                    counts[identity] = max(
                        counts[identity] ?? 0,
                        summary.windowCount
                    )
                } ?? [:]
        let facts = RuntimeAppDirectoryFactSource.currentMaintenanceFacts(
            includeCurrentProcessInAppLayer:
                AppVisibilityPreferencesStore.loadShowInCommandTab(),
            currentPID: currentPID
        )
        return facts.windowRepairApplications.map { app in
            let appID = RuntimeAppIdentity.appID(for: app)
            let identity = RuntimeAXWindowObservationIdentity(
                appID: appID,
                pid: app.processIdentifier
            )
            return RuntimeAXWindowObservationBinding(
                appID: appID,
                pid: app.processIdentifier,
                expectedWindowCount: expectedCounts[identity] ?? 0
            )
        }
    }
}
