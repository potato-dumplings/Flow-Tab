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
