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

extension FlowTabTests {
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
        wait(for: [publication], timeout: 1)
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
    func testSwitcherRuntimeProjectionNotificationsPublishWhileMainActorIsUnavailable() {
        let controller = SwitcherPanelController()
        let notificationNames: [Notification.Name] = [
            .runtimeAppSwitcherProjectionDidUpdate,
            .runtimeCurrentAppWindowProjectionDidUpdate,
            .runtimeCommittedSearchIndexDidUpdate
        ]
        let publishers = DispatchGroup()

        for name in notificationNames {
            publishers.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                NotificationCenter.default.post(name: name, object: nil)
                publishers.leave()
            }
        }

        let publicationResult = publishers.wait(timeout: .now() + 0.5)
        XCTAssertEqual(
            publicationResult,
            .success,
            "Runtime projection publishers must not synchronously wait for MainActor delivery."
        )

        let cleanupDeadline = Date().addingTimeInterval(1)
        while publishers.wait(timeout: .now()) == .timedOut, Date() < cleanupDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(publishers.wait(timeout: .now()), .success)
        withExtendedLifetime(controller) {}
    }
}
