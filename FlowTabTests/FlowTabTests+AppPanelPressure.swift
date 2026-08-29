import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabTests {
    func testAppPanelPressureLaunchRouteAndDatasetsAreExplicit() {
        let notificationName =
            "io.github.potato-dumplings.flowtab.pressure-test"
        let commandNotificationName =
            "io.github.potato-dumplings.flowtab.pressure-command-test"
        let evidenceAcknowledgementNotificationName =
            "io.github.potato-dumplings.flowtab.pressure-evidence-ack-test"
        let commandAcknowledgementNotificationName =
            "io.github.potato-dumplings.flowtab.pressure-command-ack-test"
        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                FlowTabTestLaunchOptions
                    .appPanelPressureEvidenceNotificationArgument,
                notificationName,
                FlowTabTestLaunchOptions
                    .appPanelPressureEvidenceAcknowledgementNotificationArgument,
                evidenceAcknowledgementNotificationName,
                FlowTabTestLaunchOptions
                    .appPanelPressureCommandNotificationArgument,
                commandNotificationName,
                FlowTabTestLaunchOptions
                    .appPanelPressureCommandAcknowledgementNotificationArgument,
                commandAcknowledgementNotificationName,
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-mock-runtime-variant",
                FlowTabUITestAppPanelPressureFixture
                    .realisticVariant
            ]
        ) {
            XCTAssertEqual(
                FlowTabTestLaunchOptions
                    .appPanelPressureEvidenceNotificationName,
                notificationName
            )
            XCTAssertEqual(
                FlowTabTestLaunchOptions
                    .appPanelPressureEvidenceAcknowledgementNotificationName,
                evidenceAcknowledgementNotificationName
            )
            XCTAssertEqual(
                FlowTabTestLaunchOptions
                    .appPanelPressureCommandNotificationName,
                commandNotificationName
            )
            XCTAssertEqual(
                FlowTabTestLaunchOptions
                    .appPanelPressureCommandAcknowledgementNotificationName,
                commandAcknowledgementNotificationName
            )
            XCTAssertTrue(
                FlowTabTestLaunchOptions.runsAppPanelPressure
            )
            XCTAssertFalse(
                FlowTabTestLaunchOptions.showsSwitcherDiagnostics
            )
            let dataset =
                FlowTabUITestRuntimeProjectionDataset.current()
            XCTAssertEqual(
                dataset?.appSwitcherApps.count,
                FlowTabUITestAppPanelPressureFixture
                    .realisticAppCount
            )
            XCTAssertEqual(
                dataset?.appSwitcherApps
                    .dropFirst()
                    .first?
                    .windows.count,
                FlowTabUITestAppPanelPressureFixture
                    .realisticWindowCount
            )
        }

        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-mock-runtime-variant",
                FlowTabUITestAppPanelPressureFixture
                    .extremeVariant
            ]
        ) {
            let dataset =
                FlowTabUITestRuntimeProjectionDataset.current()
            XCTAssertEqual(
                dataset?.appSwitcherApps.count,
                FlowTabUITestAppPanelPressureFixture
                    .extremeAppCount
            )
            XCTAssertEqual(
                dataset?.appSwitcherApps
                    .dropFirst()
                    .first?
                    .windows.count,
                FlowTabUITestAppPanelPressureFixture
                    .extremeSelectedAppWindowCount
            )
            XCTAssertEqual(
                dataset?.appSwitcherApps
                    .dropFirst(2)
                    .first?
                    .windows.count,
                FlowTabUITestAppPanelPressureFixture
                    .extremeWindowCount
            )
        }
    }

    func testAppPanelPressureCommandEnvelopeRejectsDuplicatesAndOldSequences() {
        let notification = Notification(
            name: Notification.Name("pressure-command"),
            userInfo: [
                AppPanelPressureCommandEnvelope
                    .UserInfoKey.sequence: NSNumber(value: 7),
                AppPanelPressureCommandEnvelope
                    .UserInfoKey.action:
                    AppPanelPressureCommandAction.cancel.rawValue
            ]
        )
        let envelope = AppPanelPressureCommandEnvelope(
            notification: notification
        )
        XCTAssertEqual(envelope?.sequence, 7)
        XCTAssertEqual(envelope?.action, .cancel)

        var gate = AppPanelPressureCommandSequenceGate()
        XCTAssertTrue(gate.accept(7))
        XCTAssertFalse(gate.accept(7))
        XCTAssertFalse(gate.accept(6))
        XCTAssertTrue(gate.accept(8))
        XCTAssertEqual(gate.lastAcceptedSequence, 8)
    }

    func testAppPanelPressureEvidenceRequiresExactVisibleAndClosedStates() {
        let visible = AppPanelPressureEvidence(
            sequence: 1,
            phase: .opened,
            elapsedMilliseconds: 12,
            panelPresented: true,
            userVisible: true,
            selectedAppID:
                FlowTabUITestAppPanelPressureFixture
                    .appID(index: 1),
            appCount:
                FlowTabUITestAppPanelPressureFixture
                    .realisticAppCount,
            selectedWindowCount:
                FlowTabUITestAppPanelPressureFixture
                    .realisticWindowCount,
            stageMetrics: [:]
        )
        XCTAssertTrue(visible.isSatisfied)

        let occluded = AppPanelPressureEvidence(
            sequence: 2,
            phase: .highlighted,
            elapsedMilliseconds: 8,
            panelPresented: true,
            userVisible: false,
            selectedAppID:
                FlowTabUITestAppPanelPressureFixture
                    .appID(index: 2),
            appCount:
                FlowTabUITestAppPanelPressureFixture
                    .realisticAppCount,
            selectedWindowCount:
                FlowTabUITestAppPanelPressureFixture
                    .realisticWindowCount,
            stageMetrics: [:]
        )
        XCTAssertFalse(occluded.isSatisfied)

        let closed = AppPanelPressureEvidence(
            sequence: 3,
            phase: .closed,
            elapsedMilliseconds: 4,
            panelPresented: false,
            userVisible: false,
            selectedAppID: nil,
            appCount: 0,
            selectedWindowCount: 0,
            stageMetrics: [:]
        )
        XCTAssertTrue(closed.isSatisfied)
    }

    func testAppPanelPressureStaticDatasetBuildsOncePerVariant() {
        FlowTabUITestRuntimeProjectionDataset
            .resetAppPanelPressureCacheForTesting()
        defer {
            FlowTabUITestRuntimeProjectionDataset
                .resetAppPanelPressureCacheForTesting()
        }
        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-mock-runtime-variant",
                FlowTabUITestAppPanelPressureFixture
                    .extremeVariant
            ]
        ) {
            XCTAssertNotNil(
                FlowTabUITestRuntimeProjectionDataset.current()
            )
            XCTAssertNotNil(
                FlowTabUITestRuntimeProjectionDataset.current()
            )
            XCTAssertEqual(
                FlowTabUITestRuntimeProjectionDataset
                    .appPanelPressureBuildCountForTesting,
                1
            )
        }
    }

    @MainActor
    func testAppPanelPressureRuntimeProjectionKeepsWindowCoverageAcrossMaintenance() {
        let previousTrustedOverride =
            AccessibilityPermissionChecker
                .isTrustedOverrideForTesting
        FlowTabUITestRuntimeProjectionDataset
            .resetAppPanelPressureCacheForTesting()
        defer {
            AccessibilityPermissionChecker
                .isTrustedOverrideForTesting =
                    previousTrustedOverride
            FlowTabUITestRuntimeProjectionDataset
                .resetAppPanelPressureCacheForTesting()
        }
        AccessibilityPermissionChecker
            .isTrustedOverrideForTesting = { true }
        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-mock-runtime-variant",
                FlowTabUITestAppPanelPressureFixture
                    .realisticVariant
            ]
        ) {
            let service = RuntimeProjectionService(
                label:
                    "FlowTabTests.AppPanelPressureProjection",
                appDirectoryProvider:
                    RuntimeUITestProjectionAppDirectoryProvider()
            )

            service.requestAppSwitcherProjectionMaintenance(
                reason: .switcherSessionStarted
            )
            service.waitForMaintenanceQueueForTesting()
            if let dataset =
                    FlowTabUITestRuntimeProjectionDataset.current()
            {
                for entry in dataset.appDirectoryEntries {
                    service.signalAppWindowsChanged(
                        appID: entry.appID,
                        pid: entry.pid
                    )
                }
                service.waitForMaintenanceQueueForTesting()
            }
            service.refreshApplicationDirectoryMembershipForPresentation()
            let firstWindowCount = service
                .readAppSwitcherProjection()?
                .appCycleApps
                .first(where: {
                    $0.id
                        == FlowTabUITestAppPanelPressureFixture
                            .appID(index: 1)
                })?
                .windows.count

            service.requestAppSwitcherProjectionMaintenance(
                reason: .switcherSessionStarted
            )
            service.waitForMaintenanceQueueForTesting()
            service.refreshApplicationDirectoryMembershipForPresentation()
            let secondWindowCount = service
                .readAppSwitcherProjection()?
                .appCycleApps
                .first(where: {
                    $0.id
                        == FlowTabUITestAppPanelPressureFixture
                            .appID(index: 1)
                })?
                .windows.count

            XCTAssertEqual(
                firstWindowCount,
                FlowTabUITestAppPanelPressureFixture
                    .realisticWindowCount
            )
            XCTAssertEqual(secondWindowCount, firstWindowCount)

            let model = LiveSwitcherModel(
                runtimeProjectionService: service
            )
            XCTAssertTrue(
                model.startSession(
                    triggerDirection: .forward,
                    deferMaintenanceUntilFirstVisibleFrame: true
                )
            )
            XCTAssertEqual(
                model.session?.selectedApp.windows.count,
                FlowTabUITestAppPanelPressureFixture
                    .realisticWindowCount
            )
            XCTAssertTrue(
                model.performDeferredRuntimeProjectionMaintenance()
            )
            service.waitForMaintenanceQueueForTesting()
            model.handle(.tabForward)
            _ = model.scheduleSelectedAppWindowProjectionIfNeeded()
            service.waitForMaintenanceQueueForTesting()
            model.cancelSelection()

            XCTAssertTrue(
                model.startSession(
                    triggerDirection: .forward,
                    deferMaintenanceUntilFirstVisibleFrame: true
                )
            )
            XCTAssertEqual(
                model.session?.selectedApp.windows.count,
                FlowTabUITestAppPanelPressureFixture
                    .realisticWindowCount
            )
        }
    }

    @MainActor
    func testSelectedReadyAppProjectionStaysOutOfAppSnapshotAfterHighlightAndAppliesOnEntry() {
        let runningApp = NSRunningApplication.current
        let appIDs = (0..<3).map {
            "com.flowtab.ready-highlight.\($0)"
        }
        let windowsByAppID = Dictionary(
            uniqueKeysWithValues: appIDs.enumerated().map {
                index, appID in
                (
                    appID,
                    (0..<2).map { windowIndex in
                        WindowCandidate(
                            id: "window-\(index)-\(windowIndex)",
                            title: "Window \(index)-\(windowIndex)",
                            isMinimized: false,
                            lastActiveAt:
                                TimeInterval(20 - windowIndex)
                        )
                    }
                )
            }
        )
        let appOnlyCandidates = appIDs.enumerated().map {
            index, appID in
            AppSwitchCandidate(
                id: appID,
                displayName: "Ready App \(index)",
                groupID: appID,
                lastActiveAt: TimeInterval(100 - index),
                windows: []
            )
        }
        let contextsByID = Dictionary(
            uniqueKeysWithValues: appOnlyCandidates.map { app in
                let windows = windowsByAppID[app.id] ?? []
                let contexts = Dictionary(
                    uniqueKeysWithValues: windows.map { window in
                        (
                            window.id,
                            RuntimeWindowContext(
                                id: window.id,
                                title: window.title,
                                isMinimized: false,
                                ownerPID:
                                    runningApp.processIdentifier
                            )
                        )
                    }
                )
                return (
                    app.id,
                    RuntimeAppContext(
                        appID: app.id,
                        runningApp: runningApp,
                        windowsByID: contexts
                    )
                )
            }
        )
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 10,
            sourceGeneration:
                RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let currentProjections = Dictionary(
            uniqueKeysWithValues: appOnlyCandidates.map { app in
                let windows = windowsByAppID[app.id] ?? []
                let candidate = AppSwitchCandidate(
                    id: app.id,
                    displayName: app.displayName,
                    groupID: app.groupID,
                    lastActiveAt: app.lastActiveAt,
                    windows: windows
                )
                return (
                    app.id,
                    RuntimeCurrentAppWindowProjection(
                        appID: app.id,
                        currentAppWindowPayload:
                            RuntimeCurrentAppWindowPayload(
                                summary: RuntimeHomeAppSummary(
                                    appID: app.id,
                                    displayName: app.displayName,
                                    groupID: app.groupID,
                                    lastActiveAt:
                                        app.lastActiveAt,
                                    windowCount: windows.count,
                                    pid:
                                        runningApp
                                            .processIdentifier
                                ),
                                candidate: candidate,
                                context: contextsByID[app.id]!,
                                appDirectoryEntries: []
                            ),
                        freshness: freshness
                    )
                )
            }
        )
        let service = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: appOnlyCandidates,
                contextsByID: contextsByID,
                freshness: freshness
            ),
            currentAppWindowProjectionsByAppID:
                currentProjections
        )
        let model = LiveSwitcherModel(
            runtimeProjectionService: service
        )
        model.runtimeProjectionMaintenanceEnabled = false

        XCTAssertTrue(
            model.startSession(triggerDirection: .forward)
        )
        XCTAssertEqual(model.session?.selectedApp.id, appIDs[1])
        model.handle(.rightArrow)
        XCTAssertEqual(model.session?.selectedApp.id, appIDs[2])
        XCTAssertEqual(model.session?.selectedApp.windows.count, 0)

        XCTAssertFalse(
            model.scheduleSelectedAppWindowProjectionIfNeeded()
        )
        XCTAssertEqual(model.session?.selectedApp.windows, [])
        XCTAssertEqual(
            model.enterSelectedAppWindowLayerUsingCurrentReadiness(),
            .entered
        )
        XCTAssertEqual(
            model.session?.selectedApp.windows.map(\.id),
            ["window-2-0", "window-2-1"]
        )
        XCTAssertTrue(
            service
                .selectedCurrentAppWindowChangeSignalsRecorded()
                .isEmpty
        )
    }
}
