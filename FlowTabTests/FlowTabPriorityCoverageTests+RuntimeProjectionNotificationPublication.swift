import AppKit
import Foundation
import FlowTabCore
import XCTest
@testable import FlowTab

private final class ProjectionPublicationAppDirectoryProvider: RuntimeAppDirectoryProviding {
    private let entries: [RuntimeAppDirectoryEntry]

    init(entries: [RuntimeAppDirectoryEntry]) {
        self.entries = entries
    }

    func appDirectoryEntriesForRuntimeMaintenance() -> [RuntimeAppDirectoryEntry] {
        entries
    }
}

private func makeProjectionPublicationWindowRecord(
    pid: pid_t,
    cgWindowID: CGWindowID,
    axWindowID: String,
    title: String
) -> RuntimeWindowRecord {
    var record = RuntimeWindowRecord(
        cgWindowID: cgWindowID,
        stableWindowID: RuntimeWindowListEntry.cgStableWindowID(
            pid: pid,
            cgWindowID: cgWindowID
        ),
        firstSeenAt: 10
    )
    record.currentAXAttachment = RuntimeCurrentAXAttachment(
        axWindowID: axWindowID,
        axWindow: AXUIElementCreateApplication(pid),
        title: title,
        frame: CGRect(x: 40, y: 50, width: 900, height: 700),
        state: RuntimeAXWindowState(isMinimized: false, isFocused: true, isMain: true)
    )
    record.lastKnownCGTitle = title
    record.lastKnownCGFrame = CGRect(x: 40, y: 50, width: 900, height: 700)
    record.lastConfirmationSource = .verifiedFocusReadback
    record.lastExactConfirmedAt = 12
    return record
}

extension FlowTabTests {
    func testFlowTabTestLaunchOptionsParsesFrontmostBundleIdentifierOverride() {
        withLaunchArgumentsForTesting(
            ["FlowTab", "--flowtab-ui-frontmost-bundle-id", "com.example.fixture.chrome"]
        ) {
            XCTAssertEqual(
                FlowTabTestLaunchOptions.frontmostBundleIdentifierOverride,
                "com.example.fixture.chrome"
            )
        }
    }

    @MainActor
    func testUITestBootstrapperPublishesMockRuntimeProjectionBeforeReturning() {
        let previousHooks = AppDelegate.testHooks
        defer {
            AppDelegate.testHooks = previousHooks
        }
        AppDelegate.testHooks.runtimeProjectionService = nil

        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-ax-trusted",
                "false"
            ]
        ) {
            FlowTabUITestBootstrapper.prepareIfNeeded()
        }

        guard let service = AppDelegate.testHooks.runtimeProjectionService else {
            XCTFail("Expected UI-test bootstrap to install a runtime projection service")
            return
        }
        let projection = service.readHomeSummaryProjection()
        XCTAssertEqual(
            projection?.summaries.map(\.appID),
            [
                "com.flowtab.mock.mail",
                "com.flowtab.mock.browser",
                "com.flowtab.mock.flow-search",
                "com.xxx.test",
                "com.xxx.csgo",
                "com.flowtab.mock.file-transfer-assistant"
            ]
        )
        XCTAssertEqual(projection?.summaries.map(\.windowCount), [0, 0, 0, 0, 0, 0])
    }

    @MainActor
    func testUITestBootstrapperPublishesMockWindowRowsWhenAccessibilityIsTrusted() {
        let previousHooks = AppDelegate.testHooks
        defer {
            AppDelegate.testHooks = previousHooks
        }
        AppDelegate.testHooks.runtimeProjectionService = nil

        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-ax-trusted",
                "true"
            ]
        ) {
            FlowTabUITestBootstrapper.prepareIfNeeded()
        }

        guard let service = AppDelegate.testHooks.runtimeProjectionService else {
            XCTFail("Expected UI-test bootstrap to install a runtime projection service")
            return
        }
        XCTAssertTrue(
            FlowTabUITestBootstrapper.resolvedRuntimeProjectionService as AnyObject
                === service as AnyObject
        )
        let projection = service.readAppSwitcherProjection()
        XCTAssertEqual(
            projection?.apps.first(where: { $0.id == "com.flowtab.mock.mail" })?.windows.map(\.id),
            ["mock-mail-inbox", "mock-mail-draft"]
        )
        XCTAssertEqual(
            service.readHomeAppDetailProjection(appID: "com.flowtab.mock.mail")?.candidate.windows.map(\.title),
            ["Inbox", "Draft"]
        )
        let searchIndexRead = service.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchIndexRead.readiness, .committedGenerationValidated)
        XCTAssertEqual(
            searchIndexRead.projection?.windowEntries
                .filter { $0.appID == "com.flowtab.mock.mail" }
                .map(\.windowID),
            ["mock-mail-inbox", "mock-mail-draft"]
        )
    }
}

extension FlowTabPriorityCoverageTests {
    func testRuntimeReconciliationCoordinatorNewSignalResumesEvidenceWait() throws {
        let coordinator = RuntimeReconciliationCoordinator()
        let dirty = coordinator.markAppDirty(
            appID: "com.example.editor",
            pid: 18_405,
            reason: .axNotification,
            now: 10
        )
        let started = try XCTUnwrap(coordinator.startRequest(id: dirty.id))
        let retry = try XCTUnwrap(
            coordinator.deferRequestAfterTransientEmptyCurrentAppWindowPayload(
                id: started.id,
                now: 10.1
            )
        )

        let duplicate = coordinator.markAppDirty(
            appID: "com.example.editor",
            pid: 18_405,
            reason: .axNotification,
            now: 10.2
        )

        XCTAssertEqual(duplicate.id, retry.id)
        XCTAssertEqual(duplicate.state, .pending)
        XCTAssertEqual(duplicate.attempt, 1)
        XCTAssertEqual(duplicate.lastObservedAt, 10.2, accuracy: 0.0001)
        XCTAssertEqual(coordinator.readyRequests().map(\.id), [dirty.id])
    }

    func testRuntimeProjectionServiceDropsRepeatedAXWindowRepairSignalsWhenAccessibilityIsUnavailable() {
        let coordinator = RuntimeReconciliationCoordinator()
        let lock = NSLock()
        var executionCount = 0
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.AXUnavailable",
            repairProvider: RuntimeProjectionRepairProvider(
                reconciliationCoordinator: coordinator
            ),
            axWindowRepairAvailability: { false },
            reconciliationExecutor: { _, _ in
                lock.lock()
                executionCount += 1
                lock.unlock()
                return .completed
            }
        )

        for _ in 0..<50 {
            service.signalAppWindowsChanged(
                appID: "com.example.editor",
                pid: 18_405
            )
            service.signalSelectedCurrentAppWindowsChanged(
                appID: "com.example.editor",
                pid: 18_405
            )
            service.requestAppSwitcherProjectionMaintenance(reason: .homeProjectionMissing)
        }
        service.waitForMaintenanceQueueForTesting()

        lock.lock()
        let finalExecutionCount = executionCount
        lock.unlock()
        XCTAssertEqual(finalExecutionCount, 0)
        XCTAssertTrue(coordinator.readyRequests().isEmpty)
        let diagnostics = service.runtimeReadModelDiagnostics()
        XCTAssertTrue(diagnostics.dirtyAppIDs.isEmpty)
        XCTAssertTrue(diagnostics.dirtyPIDs.isEmpty)
        XCTAssertTrue(diagnostics.pendingRepairScopes.isEmpty)
    }

    func testUITestFrontmostProjectionOverrideRoutesFocusedReadsAndRefreshesToTarget() throws {
        let runningApp = NSRunningApplication.current
        let appID = "com.example.fixture.chrome"
        let baseService = makeCurrentAppWindowProjectionService(
            appID: appID,
            runningApp: runningApp,
            windows: [
                WindowCandidate(
                    id: "fixture-window",
                    title: "Fixture Window",
                    isMinimized: false,
                    lastActiveAt: 10
                )
            ]
        )
        let target = RuntimeUITestFrontmostAppTarget(
            appID: appID,
            pid: runningApp.processIdentifier,
            bundleIdentifier: "com.example.fixture.chrome"
        )
        let service = RuntimeUITestFrontmostProjectionService(
            baseService: baseService,
            targetProvider: { target }
        )

        let focusedRead = try XCTUnwrap(service.readFocusedCurrentAppWindowProjection())
        XCTAssertEqual(focusedRead.appID, appID)
        XCTAssertEqual(focusedRead.pid, runningApp.processIdentifier)
        XCTAssertEqual(
            focusedRead.projection?.currentAppWindowPayload.candidate.windows.map { $0.id },
            ["fixture-window"]
        )

        service.signalFocusedCurrentAppWindowsChanged()
        let selectedSignals = baseService.selectedCurrentAppWindowChangeSignalsRecorded()
        XCTAssertEqual(selectedSignals.count, 1)
        XCTAssertEqual(selectedSignals.first?.appID, appID)
        XCTAssertEqual(selectedSignals.first?.pid, runningApp.processIdentifier)
    }

    func testRuntimeProjectionServiceRepublishesAppSwitcherAfterScopedWindowRepair() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let readModelStore = RuntimeReadModelStore()
        readModelStore.seedAppSwitcherProjectionForTesting(
            apps: [
                AppSwitchCandidate(
                    id: appID,
                    displayName: runningApp.localizedName ?? appID,
                    groupID: RuntimeAppIdentity.groupID(
                        for: runningApp.bundleIdentifier,
                        fallbackName: runningApp.localizedName ?? appID
                    ),
                    lastActiveAt: 10,
                    windows: []
                )
            ],
            contextsByID: [:],
            appDirectoryEntries: [appDirectoryEntry],
            generatedAt: 10
        )
        let cgWindowID = CGWindowID(240_911)
        let axWindowID = "ax:\(pid):scoped-publication"
        let windowRecordStore = RuntimeWindowRecordStore()
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.ScopedWindowPublication",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ),
            readModelStore: readModelStore,
            reconciliationExecutor: { _, _ in
                let record = makeProjectionPublicationWindowRecord(
                    pid: pid,
                    cgWindowID: cgWindowID,
                    axWindowID: axWindowID,
                    title: "Published After Repair"
                )
                windowRecordStore.setState(
                    RuntimeWindowMappingState(
                        windowRecordsByCGWindowID: [cgWindowID: record],
                        currentAXToCG: [axWindowID: cgWindowID],
                        validCGWindowIDs: [cgWindowID],
                        lastAXWindowIDs: [axWindowID],
                        hasObservedAXWindowHandle: true
                    ),
                    for: pid
                )
                return .completedWithCurrentAppRepairEvidence([
                    RuntimeCurrentAppRepairEvidence(
                        appID: appID,
                        pid: pid,
                        appDirectoryEntries: [appDirectoryEntry],
                        currentAppWindowPayloadWasEmpty: false,
                        authoritativeCGWindowIDs: [cgWindowID]
                    )
                ])
            }
        )

        service.signalAppWindowsChanged(appID: appID, pid: pid)
        service.waitForMaintenanceQueueForTesting()

        let expectedWindowID = RuntimeWindowListEntry.cgStableWindowID(
            pid: pid,
            cgWindowID: cgWindowID
        )
        XCTAssertEqual(
            readModelStore.readAppSwitcherProjection()?
                .apps.first(where: { $0.id == appID })?.windows.map(\.id),
            [expectedWindowID]
        )
        XCTAssertEqual(
            readModelStore.readHomeAppDetailProjection(appID: appID)?.candidate.windows.map(\.id),
            [expectedWindowID]
        )
    }

    func testRuntimeProjectionServiceRepublishesWindowRemovalAfterScopedRepair() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let cgWindowID = CGWindowID(240_912)
        let axWindowID = "ax:\(pid):scoped-removal"
        let windowID = RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID)
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: runningApp.localizedName ?? appID,
            groupID: RuntimeAppIdentity.groupID(
                for: runningApp.bundleIdentifier,
                fallbackName: runningApp.localizedName ?? appID
            ),
            lastActiveAt: 10,
            windows: [
                WindowCandidate(
                    id: windowID,
                    title: "Removed After Repair",
                    isMinimized: false,
                    lastActiveAt: 10
                )
            ]
        )
        let readModelStore = RuntimeReadModelStore()
        readModelStore.seedAppSwitcherProjectionForTesting(
            apps: [candidate],
            contextsByID: [:],
            appDirectoryEntries: [appDirectoryEntry],
            generatedAt: 10
        )
        let record = makeProjectionPublicationWindowRecord(
            pid: pid,
            cgWindowID: cgWindowID,
            axWindowID: axWindowID,
            title: "Removed After Repair"
        )
        let windowRecordStore = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                pid: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [cgWindowID: record],
                    currentAXToCG: [axWindowID: cgWindowID],
                    validCGWindowIDs: [cgWindowID],
                    lastAXWindowIDs: [axWindowID],
                    hasObservedAXWindowHandle: true
                )
            ]
        )
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.ScopedWindowRemoval",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ),
            readModelStore: readModelStore,
            reconciliationExecutor: { _, _ in
                windowRecordStore.setState(RuntimeWindowMappingState(), for: pid)
                return .completedWithCurrentAppRepairEvidence([
                    RuntimeCurrentAppRepairEvidence(
                        appID: appID,
                        pid: pid,
                        appDirectoryEntries: [appDirectoryEntry],
                        currentAppWindowPayloadWasEmpty: true,
                        authoritativeCGWindowIDs: []
                    )
                ])
            }
        )

        service.signalAXWindowDestroyed(appID: appID, pid: pid, axWindowID: axWindowID)
        service.waitForMaintenanceQueueForTesting()

        XCTAssertEqual(
            readModelStore.readAppSwitcherProjection()?
                .apps.first(where: { $0.id == appID })?.windows,
            []
        )
        XCTAssertEqual(
            readModelStore.readHomeAppDetailProjection(appID: appID)?.candidate.windows,
            []
        )
    }

    @MainActor
    func testPendingSearchActivationPreventsWindowAutoEnterUntilIndexPublishes() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .window) {
            let apps = searchScenarioApps()
            let service = RecordingRuntimeProjectionService(
                appSwitcherApps: apps,
                committedSearchApps: apps,
                committedSearchReadiness: .missingCommittedIndex
            )
            let model = LiveSwitcherModel(runtimeProjectionService: service)

            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            XCTAssertFalse(model.enterSearchMode())
            XCTAssertTrue(model.pendingSearchActivationAfterFreshnessBarrier)
            XCTAssertFalse(model.canAutoEnterWindowLayer)
            XCTAssertFalse(model.autoEnterWindowLayerIfPossible())
            XCTAssertEqual(model.session?.mode, .appCycle)

            service.installCommittedSearchIndex(for: apps)

            XCTAssertTrue(model.handleCommittedSearchIndexDidUpdate())
            XCTAssertTrue(model.isSearchActive)
            XCTAssertEqual(model.searchScope, .window)
            XCTAssertFalse(model.pendingSearchActivationAfterFreshnessBarrier)
        }
    }

    @MainActor
    func testSwitcherPanelControllerPresentsDeferredSearchAfterIndexPublishes() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .window) {
            let apps = searchScenarioApps()
            let service = RecordingRuntimeProjectionService(
                appSwitcherApps: apps,
                committedSearchApps: apps,
                committedSearchReadiness: .missingCommittedIndex
            )
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(runtimeProjectionService: service)
            )

            XCTAssertTrue(controller.presentSearchHotkeySessionForTesting())
            XCTAssertFalse(controller.modelForTesting.isSearchActive)
            XCTAssertFalse(controller.isPanelPresented)

            service.installCommittedSearchIndex(for: apps, generatedAt: 20)

            XCTAssertTrue(controller.handleCommittedSearchIndexDidUpdateForTesting())
            XCTAssertTrue(controller.modelForTesting.isSearchActive)
            XCTAssertTrue(controller.isPanelPresented)
            XCTAssertTrue(controller.modelForTesting.isSearchInputFocused)
            controller.cancelSelectionForTesting()
        }
    }

    @MainActor
    func testLiveSwitcherModelSkipsLayoutPublicationForUnchangedEmptySelectedProjection() {
        let runningApp = NSRunningApplication.current
        let appID = "com.example.unchanged-empty-selected-projection"
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: "Empty Projection",
            groupID: "empty-projection",
            lastActiveAt: 10,
            windows: []
        )
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            windowsByID: [:]
        )
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 10,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let service = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [candidate],
                contextsByID: [appID: context],
                freshness: freshness
            ),
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    currentAppWindowPayload: RuntimeCurrentAppWindowPayload(
                        summary: RuntimeHomeAppSummary(
                            appID: appID,
                            displayName: candidate.displayName,
                            groupID: candidate.groupID,
                            lastActiveAt: candidate.lastActiveAt,
                            windowCount: 0,
                            pid: runningApp.processIdentifier
                        ),
                        candidate: candidate,
                        context: context,
                        appDirectoryEntries: [RuntimeAppDirectoryEntry(app: runningApp)]
                    ),
                    freshness: freshness
                )
            ]
        )
        let model = LiveSwitcherModel(runtimeProjectionService: service)
        var layoutPublicationCount = 0
        model.onSessionLayoutChanged = {
            layoutPublicationCount += 1
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.scheduleSelectedAppWindowProjectionIfNeeded(for: appID))
        XCTAssertEqual(model.session?.selectedApp.windows, [])
        XCTAssertEqual(layoutPublicationCount, 0)
    }

    func testRuntimeProjectionServicePublishesPendingSearchIndexAfterNestedWindowRepairsComplete() throws {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let windowRecordStore = RuntimeWindowRecordStore()
        _ = windowRecordStore.resolveStableWindowMapping(
            axWindows: [],
            cgWindows: [],
            pid: pid,
            appName: runningApp.localizedName ?? appID,
            remoteScanCompleteness: .complete(scanned: 0)
        )
        let readModelStore = RuntimeReadModelStore()
        var executedTargets: [RuntimeReconciliationTarget] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.PendingSearchAfterWindowRepair",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            ),
            appDirectoryProvider: ProjectionPublicationAppDirectoryProvider(
                entries: [appDirectoryEntry]
            ),
            readModelStore: readModelStore,
            reconciliationExecutor: { request, repairProvider in
                executedTargets.append(request.target)
                switch request.target {
                case let .app(requestPID):
                    XCTAssertEqual(requestPID, pid)
                    XCTAssertTrue(request.reasons.contains(.axNotification))
                    repairProvider.recordSpaceTopologyRepairNeeded(
                        affectedCGWindowIDs: [240_909],
                        now: Date.timeIntervalSinceReferenceDate
                    )
                    return .completedWithCurrentAppRepairEvidence([
                        RuntimeCurrentAppRepairEvidence(
                            appID: appID,
                            pid: pid,
                            appDirectoryEntries: [appDirectoryEntry],
                            currentAppWindowPayloadWasEmpty: true
                        )
                    ])
                case .spaceTopology:
                    return .completed
                case .fullRepair:
                    XCTFail("Unexpected reconciliation target: \(request.target)")
                    return .completed
                }
            }
        )

        service.requestAppSwitcherProjectionMaintenance(reason: .switcherSessionStarted)
        service.waitForMaintenanceQueueForTesting()
        readModelStore.markAppWindowsDirty(
            appID: appID,
            pid: pid,
            pendingScope: "appWindows:\(appID)"
        )

        service.requestSearchIndexFreshnessBarrier(reason: .searchFreshnessBarrier)
        service.waitForMaintenanceQueueForTesting()
        XCTAssertEqual(
            readModelStore.readCommittedSearchIndexForSearch().readiness,
            .missingCommittedIndex
        )

        let publication = expectation(
            forNotification: .runtimeCommittedSearchIndexDidUpdate,
            object: service
        )
        service.signalAppWindowsChanged(appID: appID, pid: pid)
        wait(
            for: [publication],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .committedSearchIndexPublication
        )
        service.waitForMaintenanceQueueForTesting()

        let searchRead = readModelStore.readCommittedSearchIndexForSearch()
        XCTAssertEqual(searchRead.readiness, .committedGenerationValidated)
        XCTAssertEqual(searchRead.resultState, .committedGenerationResult)
        XCTAssertEqual(searchRead.projection?.appEntries.map(\.appID), [appID])
        XCTAssertEqual(searchRead.projection?.windowEntries, [])
        XCTAssertTrue(searchRead.committedIndexCoversCurrentGeneration)
        XCTAssertTrue(readModelStore.diagnostics().pendingRepairScopes.isEmpty)
        XCTAssertEqual(executedTargets, [.app(pid), .spaceTopology])
    }

    @MainActor
    func testRuntimeProjectionNotificationPublisherDeliversBackgroundPostsOnMainThread() async {
        let notificationCenter = NotificationCenter()
        let notificationObject = NSObject()
        let delivered = expectation(
            description: "unmetCondition=runtimeProjectionUpdateDeliveredOnMainThread"
        )
        delivered.assertForOverFulfill = true
        let observer = notificationCenter.addObserver(
            forName: .runtimeAppSwitcherProjectionDidUpdate,
            object: notificationObject,
            queue: nil
        ) { _ in
            XCTAssertTrue(Thread.isMainThread)
            delivered.fulfill()
        }
        defer {
            notificationCenter.removeObserver(observer)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            RuntimeProjectionNotificationPublisher.post(
                name: .runtimeAppSwitcherProjectionDidUpdate,
                object: notificationObject,
                notificationCenter: notificationCenter
            )
        }

        await fulfillment(
            of: [delivered],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .runtimeProjectionMainThreadDelivery
        )
    }

    @MainActor
    func testSwitcherRuntimeProjectionNotificationsPublishWhileMainActorIsUnavailable() {
        let controller = SwitcherPanelController()
        let notificationNames: [Notification.Name] = [
            .runtimeAppSwitcherProjectionDidUpdate,
            .runtimeCurrentAppWindowProjectionDidUpdate,
            .runtimeCommittedSearchIndexDidUpdate
        ]
        let publishers = DispatchGroup()
        let publisherCompletion = expectation(
            description: "All runtime projection notification publishers returned"
        )
        let publicationEvidence = RuntimeProjectionNotificationPublicationEvidence()

        for _ in notificationNames {
            publishers.enter()
        }
        publishers.notify(queue: .main) {
            publisherCompletion.fulfill()
        }

        for name in notificationNames {
            DispatchQueue.global(qos: .userInitiated).async {
                NotificationCenter.default.post(name: name, object: nil)
                publicationEvidence.recordCompletion(of: name)
                publishers.leave()
            }
        }

        let publicationResult = publishers.wait(
            timeout: .now()
                + RuntimeProjectionNotificationPublicationTestPolicy
                    .mainActorNonblockingWatchdog
        )
        XCTAssertEqual(
            publicationResult,
            .success,
            """
            Runtime projection publishers must return without synchronously waiting for \
            MainActor delivery. completed=\(publicationEvidence.completedNames) \
            expected=\(notificationNames.map(\.rawValue).sorted())
            """
        )

        wait(
            for: [publisherCompletion],
            timeout: RuntimeProjectionNotificationPublicationTestPolicy
                .publisherCompletionWatchdog
        )
        XCTAssertEqual(publishers.wait(timeout: .now()), .success)
        withExtendedLifetime(controller) {}
    }
}

private enum RuntimeProjectionNotificationPublicationTestPolicy {
    static let mainActorNonblockingWatchdog: DispatchTimeInterval = .milliseconds(500)
    static let publisherCompletionWatchdog: TimeInterval = 1
}

private final class RuntimeProjectionNotificationPublicationEvidence: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [Notification.Name] = []

    var completedNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return names.map(\.rawValue).sorted()
    }

    func recordCompletion(of name: Notification.Name) {
        lock.lock()
        names.append(name)
        lock.unlock()
    }
}
