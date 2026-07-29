import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabTests {
    @MainActor
    func testProjectionAcknowledgementSnapshotUsesExactProjectionEvidence() throws {
        let runningApp = NSRunningApplication.current
        let bundleIdentifier = try XCTUnwrap(
            runningApp.bundleIdentifier
        )
        let appID = "com.example.snapshot"
        let windows = [
            WindowCandidate(
                id: "snapshot-1",
                title: "One",
                isMinimized: false,
                lastActiveAt: 2
            ),
            WindowCandidate(
                id: "snapshot-2",
                title: "Two",
                isMinimized: false,
                lastActiveAt: 1
            )
        ]
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: "Snapshot",
            groupID: "fixture",
            lastActiveAt: 2,
            windows: windows
        )
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            ownerPID: 43_001,
            windowsByID: [:]
        )
        let generation = RuntimeReadModelGeneration(
            appLifecycle: 1,
            cg: 2,
            space: 3,
            axDirty: 4,
            projection: 5
        )
        let cleanProjection = RuntimeAppSwitcherProjection(
            apps: [candidate],
            contextsByID: [appID: context],
            freshness: projectionAcknowledgementFreshness(
                generation: generation
            )
        )

        XCTAssertEqual(
            FlowTabUITestProjectionAcknowledgementSnapshot
                .makeSnapshots(projection: cleanProjection),
            [
                FlowTabUITestProjectionAcknowledgementSnapshot(
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: 43_001,
                    windowCount: 2,
                    sourceGeneration:
                        "appLifecycle=1,cg=2,space=3,"
                        + "axDirty=4,projection=5",
                    isComplete: true
                )
            ]
        )

        let dirtyProjection = RuntimeAppSwitcherProjection(
            apps: [candidate],
            contextsByID: [appID: context],
            freshness: projectionAcknowledgementFreshness(
                generation: generation,
                dirtyAppIDs: [appID]
            )
        )
        XCTAssertEqual(
            FlowTabUITestProjectionAcknowledgementSnapshot
                .makeSnapshots(projection: dirtyProjection)
                .map(\.isComplete),
            [false]
        )
    }

    private func projectionAcknowledgementFreshness(
        generation: RuntimeReadModelGeneration,
        dirtyAppIDs: Set<String> = []
    ) -> RuntimeProjectionFreshness {
        RuntimeProjectionFreshness(
            generatedAt: 10,
            sourceGeneration: generation,
            dirtyAppIDs: dirtyAppIDs,
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
    }
}
