import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    func testWindowTopologyConvergenceRemovesAbsentRecordAndRebindsReorderedSurvivor() {
        let pid = pid_t(18_405)
        let retiredCGWindowID = CGWindowID(250_010)
        let survivorCGWindowID = CGWindowID(250_011)
        let retiredAXElement = AXUIElementCreateApplication(18_451)
        let originalSurvivorAXElement = AXUIElementCreateApplication(18_452)
        let rebuiltSurvivorAXElement = AXUIElementCreateApplication(18_453)
        let retiredCGWindow = makeTopologyCGWindow(
            id: retiredCGWindowID,
            title: "Retired Window",
            x: 20
        )
        let survivorCGWindow = makeTopologyCGWindow(
            id: survivorCGWindowID,
            title: "Survivor Window",
            x: 940
        )
        let store = RuntimeWindowRecordStore()

        let baseline = store.resolveStableWindowMapping(
            axWindows: [
                makeTopologyAXWindow(
                    index: 0,
                    pid: pid,
                    title: "Retired Window",
                    element: retiredAXElement,
                    frame: retiredCGWindow.bounds
                ),
                makeTopologyAXWindow(
                    index: 1,
                    pid: pid,
                    title: "Survivor Window",
                    element: originalSurvivorAXElement,
                    frame: survivorCGWindow.bounds
                )
            ],
            cgWindows: [retiredCGWindow, survivorCGWindow],
            pid: pid,
            appName: "Chrome Style App"
        )
        XCTAssertEqual(baseline.windowRecordsByCGWindowID.count, 2)
        _ = store.invalidateWindowTopology(processIdentifier: pid)

        let converged = store.resolveStableWindowMapping(
            axWindows: [
                makeTopologyAXWindow(
                    index: 0,
                    pid: pid,
                    title: "Survivor Window",
                    element: rebuiltSurvivorAXElement,
                    frame: survivorCGWindow.bounds
                )
            ],
            cgWindows: [survivorCGWindow],
            pid: pid,
            appName: "Chrome Style App",
            axCollectionIsComplete: true,
            cgCollectionIsComplete: true
        )

        XCTAssertNil(
            converged.windowRecordsByCGWindowID[retiredCGWindowID]
        )
        let survivor = converged.windowRecordsByCGWindowID[
            survivorCGWindowID
        ]
        XCTAssertNotNil(survivor)
        XCTAssertEqual(
            converged.exactMatchesByAXWindowID["ax:\(pid):0"],
            survivorCGWindowID
        )
        XCTAssertTrue(
            survivor?.currentAXAttachment.map {
                CFEqual($0.axWindow, rebuiltSurvivorAXElement)
            } == true
        )
        XCTAssertFalse(converged.isWindowTopologyConvergencePending)
        XCTAssertNil(
            store.pendingWindowTopologyInvalidationGeneration(
                processIdentifier: pid
            )
        )
    }

    func testWindowTopologyConvergenceWaitsForCompleteAXAndCGFacts() {
        let pid = pid_t(18_406)
        let cgWindowID = CGWindowID(250_020)
        let cgWindow = makeTopologyCGWindow(
            id: cgWindowID,
            title: "Closing Window",
            x: 30
        )
        let store = RuntimeWindowRecordStore()
        _ = store.resolveStableWindowMapping(
            axWindows: [
                makeTopologyAXWindow(
                    index: 0,
                    pid: pid,
                    title: "Closing Window",
                    element: AXUIElementCreateApplication(18_461),
                    frame: cgWindow.bounds
                )
            ],
            cgWindows: [cgWindow],
            pid: pid,
            appName: "Incomplete Facts App"
        )
        _ = store.invalidateWindowTopology(processIdentifier: pid)

        let incomplete = store.resolveStableWindowMapping(
            axWindows: [],
            cgWindows: [],
            pid: pid,
            appName: "Incomplete Facts App",
            axCollectionIsComplete: false,
            cgCollectionIsComplete: true
        )

        XCTAssertTrue(incomplete.isWindowTopologyConvergencePending)
        XCTAssertNotNil(
            incomplete.windowRecordsByCGWindowID[cgWindowID]
        )

        let complete = store.resolveStableWindowMapping(
            axWindows: [],
            cgWindows: [],
            pid: pid,
            appName: "Incomplete Facts App",
            axCollectionIsComplete: true,
            cgCollectionIsComplete: true
        )

        XCTAssertFalse(complete.isWindowTopologyConvergencePending)
        XCTAssertTrue(complete.windowRecordsByCGWindowID.isEmpty)
    }

    func testRepeatedDestroyedEvidenceUsesOneApplicationTopologyInvalidationGeneration() {
        let pid = pid_t(18_407)
        let store = RuntimeWindowRecordStore()
        let provider = RuntimeProjectionRepairProvider(
            windowRecordStore: store,
            reconciliationCoordinator: RuntimeReconciliationCoordinator()
        )

        provider.recordAppWindowsChanged(
            appID: "com.example.repeated-destroyed",
            pid: pid,
            changeKinds: [.destroyed],
            now: 10
        )
        let firstGeneration = store
            .pendingWindowTopologyInvalidationGeneration(
                processIdentifier: pid
            )
        provider.recordAppWindowsChanged(
            appID: "com.example.repeated-destroyed",
            pid: pid,
            changeKinds: [.destroyed],
            now: 11
        )

        XCTAssertNotNil(firstGeneration)
        XCTAssertEqual(
            store.pendingWindowTopologyInvalidationGeneration(
                processIdentifier: pid
            ),
            firstGeneration
        )
    }

    func testObservedDestroyedEvidencePublishesDirtyProjectionBeforeTrailingRepair() throws {
        let runningApp = NSRunningApplication.current
        let pid = runningApp.processIdentifier
        let appID = "com.example.destroyed-window-freshness"
        let window = WindowCandidate(
            id: "destroyed-window",
            title: "Destroyed Window",
            isMinimized: false,
            lastActiveAt: 10
        )
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: "Destroyed Window App",
            groupID: "destroyed-window-app",
            lastActiveAt: 10,
            windows: [window]
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            windows: [window]
        )
        let directoryEntry = RuntimeAppDirectoryEntry(
            pid: pid,
            appID: appID,
            bundleIdentifier: appID,
            localizedName: candidate.displayName,
            launchDate: nil
        )
        let store = RuntimeReadModelStore()
        store.commitFullRepairAppDirectoryEvidence(
            [directoryEntry],
            generatedAt: 10
        )
        store.commitCurrentAppWindowProjection(
            RuntimeCurrentAppWindowPayload(
                summary: RuntimeHomeAppSummary(
                    appID: appID,
                    displayName: candidate.displayName,
                    groupID: candidate.groupID,
                    lastActiveAt: candidate.lastActiveAt,
                    windowCount: 1,
                    pid: pid
                ),
                candidate: candidate,
                context: context,
                appDirectoryEntries: [directoryEntry]
            ),
            clearsDirtyState: true,
            generatedAt: 10
        )
        let service = RuntimeProjectionService(
            label: "FlowTabTests.DestroyedWindowFreshness.Service",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: RuntimeWindowRecordStore(),
                reconciliationCoordinator: RuntimeReconciliationCoordinator()
            ),
            readModelStore: store,
            reconciliationExecutor: { _, _ in .completed }
        )

        service.markAppWindowsDirty(
            RuntimeAXWindowChangeEvidence(
                appID: appID,
                pid: pid,
                generation: 1,
                source: .observedTransition,
                observedTransitionCount: 1,
                changeKinds: [.destroyed],
                initialReadback: nil
            )
        )

        let projection = try XCTUnwrap(
            store.readCurrentAppWindowProjection(appID: appID)
        )
        XCTAssertFalse(projection.freshness.isCompleteForScope)
        XCTAssertEqual(projection.freshness.dirtyAppIDs, [appID])
        XCTAssertEqual(projection.freshness.dirtyPIDs, [pid])
        XCTAssertEqual(
            projection.freshness.pendingRepairScopes,
            ["appWindows:\(appID)"]
        )
        XCTAssertEqual(projection.freshness.sourceGeneration.axDirty, 1)
    }

    private func makeTopologyCGWindow(
        id: CGWindowID,
        title: String,
        x: CGFloat
    ) -> RuntimeCGWindowEntry {
        RuntimeCGWindowEntry(
            id: id,
            title: title,
            bounds: CGRect(x: x, y: 40, width: 800, height: 600),
            isOnscreen: true,
            alpha: 1,
            storeType: 1,
            spaceIDs: [RuntimeWindowTopologyClassifier.desktopSpaceID]
        )
    }

    private func makeTopologyAXWindow(
        index: Int,
        pid: pid_t,
        title: String,
        element: AXUIElement,
        frame: CGRect?
    ) -> RuntimeAXWindowEntry {
        RuntimeAXWindowEntry(
            index: index,
            id: "ax:\(pid):\(index)",
            title: title,
            sourceTitle: title,
            isMinimized: false,
            window: element,
            frame: frame
        )
    }
}
