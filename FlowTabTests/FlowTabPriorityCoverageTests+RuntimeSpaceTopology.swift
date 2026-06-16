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

    func testRuntimeSpaceTopologySignatureGroupsStableDisplayState() {
        let first = RuntimeSpaceTopologySnapshot(
            currentSpaceIDByDisplay: [2: 22, 1: 10],
            spacesByID: [
                22: RuntimeSpaceTopologySpace(id: 22, displayID: 2, isCurrent: true),
                10: RuntimeSpaceTopologySpace(id: 10, displayID: 1, isCurrent: true),
                11: RuntimeSpaceTopologySpace(id: 11, displayID: 1, isCurrent: false)
            ],
            windowIDsBySpaceID: [
                11: Set<CGWindowID>([240_003, 240_002]),
                10: Set<CGWindowID>([240_001]),
                22: Set<CGWindowID>([240_004])
            ],
            fullscreenWindowIDBySpaceID: [
                11: 240_002
            ]
        )
        let reordered = RuntimeSpaceTopologySnapshot(
            currentSpaceIDByDisplay: [1: 10, 2: 22],
            spacesByID: [
                11: RuntimeSpaceTopologySpace(id: 11, displayID: 1, isCurrent: false),
                22: RuntimeSpaceTopologySpace(id: 22, displayID: 2, isCurrent: true),
                10: RuntimeSpaceTopologySpace(id: 10, displayID: 1, isCurrent: true)
            ],
            windowIDsBySpaceID: [
                22: Set<CGWindowID>([240_004]),
                10: Set<CGWindowID>([240_001]),
                11: Set<CGWindowID>([240_002, 240_003])
            ],
            fullscreenWindowIDBySpaceID: [
                11: 240_002
            ]
        )

        let signature = first.signature

        XCTAssertEqual(signature, reordered.signature)
        XCTAssertEqual(signature.displays.map(\.displayID), [1, 2])
        XCTAssertEqual(signature.displays.first?.currentSpaceID, 10)
        XCTAssertEqual(signature.displays.first?.spaceIDs, [10, 11])
        XCTAssertEqual(signature.displays.first?.windowIDsBySpaceID[11], [240_002, 240_003])
        XCTAssertEqual(signature.displays.first?.fullscreenWindowIDBySpaceID, [11: 240_002])
    }

    func testRuntimeSpaceTopologyDiffCarriesSignatureForFullscreenTransition() {
        let previous = RuntimeSpaceTopologySnapshot(
            currentSpaceIDByDisplay: [1: 10],
            spacesByID: [
                10: RuntimeSpaceTopologySpace(id: 10, displayID: 1, isCurrent: true)
            ],
            windowIDsBySpaceID: [
                10: Set<CGWindowID>([240_001, 240_002])
            ],
            fullscreenWindowIDBySpaceID: [:]
        )
        let current = RuntimeSpaceTopologySnapshot(
            currentSpaceIDByDisplay: [1: 10],
            spacesByID: [
                10: RuntimeSpaceTopologySpace(id: 10, displayID: 1, isCurrent: true)
            ],
            windowIDsBySpaceID: [
                10: Set<CGWindowID>([240_001, 240_002])
            ],
            fullscreenWindowIDBySpaceID: [
                10: 240_002
            ]
        )

        let diff = current.diff(from: previous)

        XCTAssertTrue(diff.hasSignatureChange)
        XCTAssertEqual(diff.changedSpaceIDs, [10])
        XCTAssertEqual(diff.affectedCGWindowIDs, [240_001, 240_002])
        XCTAssertEqual(diff.previousSignature, previous.signature)
        XCTAssertEqual(diff.currentSignature, current.signature)
        XCTAssertEqual(diff.currentSignature.displays.first?.fullscreenWindowIDBySpaceID, [10: 240_002])
    }

    func testRuntimeSpaceTopologyDiffSignatureLogFieldsSummarizeDisplayTopology() {
        let previous = RuntimeSpaceTopologySnapshot(
            currentSpaceIDByDisplay: [1: 10],
            spacesByID: [
                10: RuntimeSpaceTopologySpace(id: 10, displayID: 1, isCurrent: true)
            ],
            windowIDsBySpaceID: [
                10: Set<CGWindowID>([240_001])
            ]
        )
        let current = RuntimeSpaceTopologySnapshot(
            currentSpaceIDByDisplay: [1: 11],
            spacesByID: [
                10: RuntimeSpaceTopologySpace(id: 10, displayID: 1, isCurrent: false),
                11: RuntimeSpaceTopologySpace(id: 11, displayID: 1, isCurrent: true)
            ],
            windowIDsBySpaceID: [
                10: Set<CGWindowID>([240_001]),
                11: Set<CGWindowID>([240_002, 240_003])
            ],
            fullscreenWindowIDBySpaceID: [
                11: 240_002
            ]
        )

        let fields = Dictionary(uniqueKeysWithValues: current.diff(from: previous).signatureLogFields)

        XCTAssertEqual(fields["signatureChanged"], "1")
        XCTAssertEqual(fields["signatureDisplays"], "1")
        XCTAssertEqual(fields["signatureSpaces"], "2")
        XCTAssertEqual(fields["signatureWindows"], "3")
        XCTAssertEqual(fields["signatureFullscreen"], "1")
        XCTAssertEqual(fields["signature"], "d=1,current=11,spaces=2,windows=3,fullscreen=1")
        XCTAssertFalse(fields["signature"]?.contains(" ") == true)
    }
}
