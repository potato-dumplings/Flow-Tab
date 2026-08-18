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

    func testRuntimeCGVisibilitySamplingDoesNotReplaceAuthoritativeSpaceTopologyBaseline() throws {
        let visibleWindowID = CGWindowID(240_101)
        let offSpaceWindowID = CGWindowID(240_102)
        let pid: pid_t = 18_401
        let coordinator = RuntimeReconciliationCoordinator()
        let windowRecordStore = RuntimeWindowRecordStore()
        let provider = RuntimeSystemRepairFactProvider(
            cgWindowListProvider: ScopeSensitiveRuntimeCGWindowListProvider(
                onScreenWindowInfo: [
                    makeRawCGWindowInfo(
                        pid: pid,
                        windowID: visibleWindowID,
                        title: "Visible Window"
                    )
                ],
                allWindowInfo: [
                    makeRawCGWindowInfo(
                        pid: pid,
                        windowID: visibleWindowID,
                        title: "Visible Window"
                    ),
                    makeRawCGWindowInfo(
                        pid: pid,
                        windowID: offSpaceWindowID,
                        title: "Off-Space Window",
                        isOnscreen: false
                    )
                ]
            ),
            spaceTopologyProvider: WindowScopedRuntimeSpaceTopologyProvider(
                spaceIDByWindowID: [
                    visibleWindowID: 10,
                    offSpaceWindowID: 11
                ]
            ),
            windowRecordStore: windowRecordStore,
            reconciliationCoordinator: coordinator
        )

        let authoritativeCollection = provider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionAll, .excludeDesktopElements],
            now: 1
        )
        XCTAssertEqual(
            authoritativeCollection.spaceTopologyDiff?.affectedCGWindowIDs,
            [visibleWindowID, offSpaceWindowID]
        )
        let initialRequest = try XCTUnwrap(coordinator.readyRequests().first)
        coordinator.completeRequest(id: initialRequest.id)

        let visibilityCollection = provider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionOnScreenOnly, .excludeDesktopElements],
            now: 2
        )

        XCTAssertNil(visibilityCollection.spaceTopologyDiff)
        XCTAssertEqual(
            visibilityCollection.windowsByPID[pid]?.first?.spaceIDs,
            [10]
        )
        XCTAssertFalse(coordinator.hasPendingRequests())

        let repeatedAuthoritativeCollection = provider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionAll, .excludeDesktopElements],
            now: 3
        )
        XCTAssertEqual(
            repeatedAuthoritativeCollection.spaceTopologyDiff?.affectedCGWindowIDs,
            []
        )
        XCTAssertFalse(coordinator.hasPendingRequests())

        let movedProvider = RuntimeSystemRepairFactProvider(
            cgWindowListProvider: ScopeSensitiveRuntimeCGWindowListProvider(
                onScreenWindowInfo: [
                    makeRawCGWindowInfo(
                        pid: pid,
                        windowID: offSpaceWindowID,
                        title: "Off-Space Window"
                    )
                ],
                allWindowInfo: [
                    makeRawCGWindowInfo(
                        pid: pid,
                        windowID: visibleWindowID,
                        title: "Visible Window",
                        isOnscreen: false
                    ),
                    makeRawCGWindowInfo(
                        pid: pid,
                        windowID: offSpaceWindowID,
                        title: "Off-Space Window"
                    )
                ]
            ),
            spaceTopologyProvider: WindowScopedRuntimeSpaceTopologyProvider(
                spaceIDByWindowID: [
                    visibleWindowID: 10,
                    offSpaceWindowID: 11
                ]
            ),
            windowRecordStore: windowRecordStore,
            reconciliationCoordinator: coordinator
        )
        let movedAuthoritativeCollection = movedProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionAll, .excludeDesktopElements],
            now: 4
        )
        XCTAssertEqual(
            movedAuthoritativeCollection.spaceTopologyDiff?.affectedCGWindowIDs,
            [visibleWindowID, offSpaceWindowID]
        )
        XCTAssertEqual(
            movedAuthoritativeCollection.spaceTopologyDiff?
                .currentSignature.displays.first?.currentSpaceID,
            11
        )
        XCTAssertEqual(coordinator.readyRequests().map(\.target), [.spaceTopology])
    }
}

private struct ScopeSensitiveRuntimeCGWindowListProvider: RuntimeCGWindowListProviding {
    let onScreenWindowInfo: [[String: Any]]
    let allWindowInfo: [[String: Any]]

    func windowInfo(
        options: CGWindowListOption,
        relativeToWindow windowID: CGWindowID
    ) -> [[String: Any]]? {
        options.contains(.optionOnScreenOnly)
            ? onScreenWindowInfo
            : allWindowInfo
    }
}

private struct WindowScopedRuntimeSpaceTopologyProvider: RuntimeSpaceTopologyProviding {
    let spaceIDByWindowID: [CGWindowID: Int]

    func snapshot(for windowIDs: [CGWindowID]) -> RuntimeSpaceTopologySnapshot {
        let spaceIDsByCGWindowID = Dictionary(
            uniqueKeysWithValues: windowIDs.compactMap { windowID in
                spaceIDByWindowID[windowID].map { (windowID, Set([$0])) }
            }
        )
        let includedSpaceIDs = Set(spaceIDsByCGWindowID.values.flatMap { $0 })
        return RuntimeSpaceTopologySnapshot(
            spacesByID: Dictionary(
                uniqueKeysWithValues: includedSpaceIDs.map { spaceID in
                    (
                        spaceID,
                        RuntimeSpaceTopologySpace(
                            id: spaceID,
                            displayID: nil,
                            isCurrent: false
                        )
                    )
                }
            ),
            spaceIDsByCGWindowID: spaceIDsByCGWindowID
        )
    }
}
