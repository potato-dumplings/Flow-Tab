import CoreGraphics
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testRuntimeSpaceTopologySnapshotNormalizesWindowSpaceIndexes() {
        let snapshot = RuntimeSpaceTopologySnapshot(
            currentSpaceIDByDisplay: [1: 10],
            spacesByID: [
                10: RuntimeSpaceTopologySpace(id: 10, displayID: 1, isCurrent: true)
            ],
            windowIDsBySpaceID: [
                11: Set<CGWindowID>([240_002])
            ],
            spaceIDsByCGWindowID: [
                240_001: Set([10, 10, 0])
            ]
        )

        XCTAssertEqual(snapshot.currentSpaceIDByDisplay, [1: 10])
        XCTAssertEqual(snapshot.spacesByID[10], RuntimeSpaceTopologySpace(id: 10, displayID: 1, isCurrent: true))
        XCTAssertEqual(snapshot.spacesByID[11], RuntimeSpaceTopologySpace(id: 11, displayID: nil, isCurrent: false))
        XCTAssertEqual(snapshot.windowIDsBySpaceID[10], Set<CGWindowID>([240_001]))
        XCTAssertEqual(snapshot.windowIDsBySpaceID[11], Set<CGWindowID>([240_002]))
        XCTAssertEqual(snapshot.spaceIDsByCGWindowID[240_001], Set([10]))
        XCTAssertEqual(snapshot.spaceIDsByCGWindowID[240_002], Set([11]))
    }

    func testRuntimeSpaceTopologySnapshotDiffReportsAffectedCGWindows() {
        let previous = RuntimeSpaceTopologySnapshot(
            currentSpaceIDByDisplay: [1: 10],
            spacesByID: [
                10: RuntimeSpaceTopologySpace(id: 10, displayID: 1, isCurrent: true),
                11: RuntimeSpaceTopologySpace(id: 11, displayID: 1, isCurrent: false)
            ],
            windowIDsBySpaceID: [
                10: Set<CGWindowID>([240_001]),
                11: Set<CGWindowID>([240_002])
            ],
            fullscreenWindowIDBySpaceID: [11: 240_002]
        )
        let current = RuntimeSpaceTopologySnapshot(
            currentSpaceIDByDisplay: [1: 12],
            spacesByID: [
                10: RuntimeSpaceTopologySpace(id: 10, displayID: 1, isCurrent: false),
                12: RuntimeSpaceTopologySpace(id: 12, displayID: 1, isCurrent: true)
            ],
            windowIDsBySpaceID: [
                10: Set<CGWindowID>([240_001, 240_003]),
                12: Set<CGWindowID>([240_004])
            ],
            fullscreenWindowIDBySpaceID: [12: 240_004]
        )

        let diff = current.diff(from: previous)

        XCTAssertEqual(diff.addedSpaceIDs, Set([12]))
        XCTAssertEqual(diff.removedSpaceIDs, Set([11]))
        XCTAssertEqual(diff.changedSpaceIDs, Set([10, 11, 12]))
        XCTAssertEqual(diff.affectedCGWindowIDs, Set<CGWindowID>([240_001, 240_002, 240_003, 240_004]))
    }
}
