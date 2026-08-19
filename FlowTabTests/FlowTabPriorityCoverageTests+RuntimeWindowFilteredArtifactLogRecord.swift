import CoreGraphics
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testFilteredArtifactLogRecordsBindCountsToExactProcessIdentifiers() {
        let records =
            RuntimeWindowFilteredArtifactLogRecord.records(
                appName: "Chrome Fixture",
                kind: .fullscreenHostArtifacts,
                stage: "presentation",
                droppedEntries: [
                    filteredArtifactEntry(
                        processIdentifier: 4_322,
                        windowNumber: 202
                    ),
                    filteredArtifactEntry(
                        processIdentifier: 4_321,
                        windowNumber: 101
                    ),
                    filteredArtifactEntry(
                        processIdentifier: 4_321,
                        windowNumber: 102
                    )
                ]
            )

        XCTAssertEqual(
            records,
            [
                RuntimeWindowFilteredArtifactLogRecord(
                    appName: "Chrome Fixture",
                    processIdentifier: 4_321,
                    kind: .fullscreenHostArtifacts,
                    stage: "presentation",
                    droppedCount: 2
                ),
                RuntimeWindowFilteredArtifactLogRecord(
                    appName: "Chrome Fixture",
                    processIdentifier: 4_322,
                    kind: .fullscreenHostArtifacts,
                    stage: "presentation",
                    droppedCount: 1
                )
            ]
        )
        XCTAssertEqual(
            records.map(\.logMessage),
            [
                "Chrome Fixture filtered-fullscreen-host-artifacts "
                    + "stage=presentation dropped=2 pid=4321",
                "Chrome Fixture filtered-fullscreen-host-artifacts "
                    + "stage=presentation dropped=1 pid=4322"
            ]
        )
    }

    func testFilteredArtifactLogRecordsRequirePositiveProcessIdentity() {
        XCTAssertTrue(
            RuntimeWindowFilteredArtifactLogRecord.records(
                appName: "Chrome Fixture",
                kind: .cgOnlyCoveredByActivation,
                stage:
                    "read-model-current-app-normalization",
                droppedEntries: [
                    filteredArtifactEntry(
                        processIdentifier: 0,
                        windowNumber: 101
                    )
                ]
            )
            .isEmpty
        )
    }

    func testRepeatedFullscreenTitleFilterKeepsExactCurrentDesktopWindowsWithoutSiblingTopology() {
        let processIdentifier: pid_t = 6_520
        let frame = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let firstWindowID = CGWindowID(107_289)
        let secondWindowID = CGWindowID(84_479)
        let entries = [firstWindowID, secondWindowID].enumerated().map {
            index,
            windowID in
            RuntimeWindowListEntry(
                windowID: "cg:\(processIdentifier):\(windowID)",
                title: "Shared Window Title",
                isMinimized: false,
                ownerPID: processIdentifier,
                cgWindowID: windowID,
                activationHandleID: "ax:\(processIdentifier):\(index)",
                frame: frame.offsetBy(dx: CGFloat(index), dy: CGFloat(index)),
                spaceIDs: [1],
                isOnscreen: true,
                lastConfirmationSource: .privateExactBridge
            )
        }
        let knownCGWindowsByID = Dictionary(
            uniqueKeysWithValues: entries.compactMap { entry in
                entry.cgWindowID.map { windowID in
                    (
                        windowID,
                        RuntimeCGWindowEntry(
                            id: windowID,
                            title: entry.title,
                            bounds: entry.frame,
                            isOnscreen: true,
                            alpha: 1,
                            storeType: 1,
                            spaceIDs: [1]
                        )
                    )
                }
            }
        )

        let filtered = RuntimeWindowPresentationFilter
            .filterRepeatedFullscreenPresentationTitles(
                entries,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: "Multi Window App",
                hasFullscreenTopology: false,
                stage: "unit"
            )

        XCTAssertEqual(filtered.map(\.windowID), entries.map(\.windowID))
    }

    private func filteredArtifactEntry(
        processIdentifier: pid_t,
        windowNumber: CGWindowID
    ) -> RuntimeWindowListEntry {
        RuntimeWindowListEntry(
            windowID:
                "cg:\(processIdentifier):\(windowNumber)",
            title: "Artifact",
            isMinimized: false,
            ownerPID: processIdentifier,
            cgWindowID: windowNumber
        )
    }
}
