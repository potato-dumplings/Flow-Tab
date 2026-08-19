import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testRuntimeWindowRecordLifecycleRemovesDestroyedWindowAfterAuthoritativeAbsence() {
        let pid = pid_t(18_405)
        let axWindowID = "ax:\(pid):destroyed"
        let cgWindowID = CGWindowID(250_010)
        let axWindow = AXUIElementCreateApplication(pid)
        let cgWindow = RuntimeCGWindowEntry(
            id: cgWindowID,
            title: "Closing Window",
            bounds: CGRect(x: 20, y: 30, width: 800, height: 600),
            isOnscreen: true,
            alpha: 1.0,
            storeType: 1,
            spaceIDs: [RuntimeWindowTopologyClassifier.desktopSpaceID]
        )
        var record = RuntimeWindowRecord(
            cgWindowID: cgWindowID,
            stableWindowID:
                RuntimeWindowListEntry.cgStableWindowID(
                    pid: pid,
                    cgWindowID: cgWindowID
                ),
            firstSeenAt: 10
        )
        record.refreshCGState(from: cgWindow, observedAt: 10)
        record.currentAXAttachment = RuntimeCurrentAXAttachment(
            axWindowID: axWindowID,
            axWindow: axWindow,
            title: "Closing Window",
            frame: cgWindow.bounds,
            state: RuntimeAXWindowState(
                isMinimized: false,
                isFocused: false,
                isMain: false
            )
        )
        record.lastExactAXWindowID = axWindowID
        record.lastExactAXWindow = axWindow
        record.lastConfirmationSource = .publicExactMatch
        let store = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                pid: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        cgWindowID: record
                    ],
                    currentAXToCG: [axWindowID: cgWindowID],
                    validCGWindowIDs: [cgWindowID],
                    lastAXWindowIDs: [axWindowID],
                    hasObservedAXWindowHandle: true
                )
            ]
        )

        XCTAssertEqual(
            store.clearDestroyedAXAttachment(
                processIdentifier: pid,
                axWindowID: axWindowID,
                now: 11
            ),
            cgWindowID
        )

        let closingResolution = store.resolveStableWindowMapping(
            axWindows: [],
            cgWindows: [cgWindow],
            pid: pid,
            appName: "Closing App"
        )
        XCTAssertNotNil(
            closingResolution.windowRecordsByCGWindowID[cgWindowID]
        )
        XCTAssertEqual(
            store.state(for: pid)?.affectedWindowEvidence(
                for: [cgWindowID]
            ).pendingDestroyedCGWindowIDs,
            [cgWindowID]
        )

        let absentResolution = store.resolveStableWindowMapping(
            axWindows: [],
            cgWindows: [],
            pid: pid,
            appName: "Closing App"
        )

        XCTAssertTrue(
            absentResolution.windowRecordsByCGWindowID.isEmpty
        )
    }

    func testRuntimeWindowRecordStoreResolvesDestroyedAXFromUniqueExactHistory() {
        let pid = pid_t(18_405)
        let axWindowID = "ax:\(pid):historical-destroyed"
        let cgWindowID = CGWindowID(250_012)
        var record = RuntimeWindowRecord(
            cgWindowID: cgWindowID,
            stableWindowID:
                RuntimeWindowListEntry.cgStableWindowID(
                    pid: pid,
                    cgWindowID: cgWindowID
                ),
            firstSeenAt: 10
        )
        record.lastExactAXWindowID = axWindowID
        record.lastExactAXWindow = AXUIElementCreateApplication(pid)
        let store = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                pid: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: [
                        cgWindowID: record
                    ],
                    validCGWindowIDs: [cgWindowID]
                )
            ]
        )

        XCTAssertEqual(
            store.clearDestroyedAXAttachment(
                processIdentifier: pid,
                axWindowID: axWindowID,
                now: 11
            ),
            cgWindowID
        )
        XCTAssertEqual(
            store.state(for: pid)?
                .windowRecordsByCGWindowID[cgWindowID]?
                .pendingDestroyedAXWindowID,
            axWindowID
        )
    }

    func testRuntimeWindowRecordStoreRejectsAmbiguousDestroyedAXHistory() {
        let pid = pid_t(18_405)
        let axWindowID = "ax:\(pid):ambiguous-destroyed"
        let firstCGWindowID = CGWindowID(250_013)
        let secondCGWindowID = CGWindowID(250_014)
        let records = [firstCGWindowID, secondCGWindowID].reduce(
            into: [CGWindowID: RuntimeWindowRecord]()
        ) { records, cgWindowID in
            var record = RuntimeWindowRecord(
                cgWindowID: cgWindowID,
                stableWindowID:
                    RuntimeWindowListEntry.cgStableWindowID(
                        pid: pid,
                        cgWindowID: cgWindowID
                    ),
                firstSeenAt: 10
            )
            record.lastExactAXWindowID = axWindowID
            record.lastExactAXWindow =
                AXUIElementCreateApplication(pid)
            records[cgWindowID] = record
        }
        let store = RuntimeWindowRecordStore(
            mappingStatesByPID: [
                pid: RuntimeWindowMappingState(
                    windowRecordsByCGWindowID: records,
                    validCGWindowIDs: [
                        firstCGWindowID,
                        secondCGWindowID
                    ]
                )
            ]
        )

        XCTAssertNil(
            store.clearDestroyedAXAttachment(
                processIdentifier: pid,
                axWindowID: axWindowID,
                now: 11
            )
        )
        XCTAssertTrue(
            store.state(for: pid)?
                .windowRecordsByCGWindowID.values
                .allSatisfy {
                    !$0.hasPendingDestroyedAXEvidence
                } == true
        )
    }

    func testRuntimeWindowRecordDestroyedEvidenceClearsAfterExactRebinding() {
        let pid = pid_t(18_405)
        let cgWindowID = CGWindowID(250_011)
        let cgWindow = RuntimeCGWindowEntry(
            id: cgWindowID,
            title: "Rebound Window",
            bounds: CGRect(x: 30, y: 40, width: 900, height: 700),
            isOnscreen: true,
            alpha: 1.0,
            storeType: 1,
            spaceIDs: [RuntimeWindowTopologyClassifier.desktopSpaceID]
        )
        var record = RuntimeWindowRecord(
            cgWindowID: cgWindowID,
            stableWindowID:
                RuntimeWindowListEntry.cgStableWindowID(
                    pid: pid,
                    cgWindowID: cgWindowID
                ),
            firstSeenAt: 10
        )
        record.clearDestroyedAXAttachment(
            axWindowID: "ax:\(pid):destroyed",
            observedAt: 11
        )
        XCTAssertTrue(record.hasPendingDestroyedAXEvidence)

        let reboundAXWindow = RuntimeAXWindowEntry(
            index: 0,
            id: "ax:\(pid):rebound",
            title: "Rebound Window",
            sourceTitle: "Rebound Window",
            isMinimized: false,
            window: AXUIElementCreateApplication(pid),
            frame: cgWindow.bounds
        )
        record.applyExactMatch(
            axWindow: reboundAXWindow,
            resolvedTitle: "Rebound Window",
            confirmationSource: .publicExactMatch,
            observedAt: 12,
            matchedCGWindow: cgWindow
        )

        XCTAssertFalse(record.hasPendingDestroyedAXEvidence)
        XCTAssertEqual(
            record.currentAXWindowID,
            reboundAXWindow.id
        )
    }

    func testRuntimeWindowRecordDestroyedEvidenceSurvivesStaleExactReadback() {
        let pid = pid_t(18_405)
        let axWindowID = "ax:\(pid):destroyed"
        let cgWindowID = CGWindowID(250_015)
        let axWindow = AXUIElementCreateApplication(pid)
        let cgWindow = RuntimeCGWindowEntry(
            id: cgWindowID,
            title: "Stale Destroyed Window",
            bounds: CGRect(x: 40, y: 50, width: 800, height: 600),
            isOnscreen: true,
            alpha: 1.0,
            storeType: 1,
            spaceIDs: [RuntimeWindowTopologyClassifier.desktopSpaceID]
        )
        var record = RuntimeWindowRecord(
            cgWindowID: cgWindowID,
            stableWindowID:
                RuntimeWindowListEntry.cgStableWindowID(
                    pid: pid,
                    cgWindowID: cgWindowID
                ),
            firstSeenAt: 10
        )
        record.lastExactAXWindowID = axWindowID
        record.lastExactAXWindow = axWindow
        record.clearDestroyedAXAttachment(
            axWindowID: axWindowID,
            observedAt: 11
        )

        record.applyExactMatch(
            axWindow: RuntimeAXWindowEntry(
                index: 0,
                id: axWindowID,
                title: "Stale Destroyed Window",
                sourceTitle: "Stale Destroyed Window",
                isMinimized: false,
                window: axWindow,
                frame: cgWindow.bounds
            ),
            resolvedTitle: "Stale Destroyed Window",
            confirmationSource: .publicExactMatch,
            observedAt: 12,
            matchedCGWindow: cgWindow
        )

        XCTAssertTrue(record.hasPendingDestroyedAXEvidence)
    }
}
