import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabTests {
    @MainActor
    func testProjectionAcknowledgementSnapshotUsesExactCurrentAppScopeEvidence() throws {
        let runningApp = NSRunningApplication.current
        let bundleIdentifier = try XCTUnwrap(
            runningApp.bundleIdentifier
        )
        let appID = bundleIdentifier
        let processIdentifier =
            runningApp.processIdentifier
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
            ownerPID: processIdentifier,
            windowsByID: [:]
        )
        let payload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: candidate.displayName,
                groupID: candidate.groupID,
                lastActiveAt: candidate.lastActiveAt,
                windowCount: windows.count,
                pid: processIdentifier,
                bundleIdentifier: bundleIdentifier,
                bundleURL: runningApp.bundleURL
            ),
            candidate: candidate,
            context: context,
            appDirectoryEntries: []
        )
        let readModelStore = RuntimeReadModelStore()
        readModelStore.markAppWindowsDirty(
            appID: "com.example.unrelated",
            pid: 43_002,
            pendingScope:
                "appWindows:com.example.unrelated"
        )
        readModelStore.commitCurrentAppWindowProjection(
            payload,
            clearsDirtyState: true,
            generatedAt: 10
        )
        let exactScopeProjection = try XCTUnwrap(
            readModelStore.readCurrentAppWindowProjection(
                appID: appID
            )
        )

        XCTAssertTrue(exactScopeProjection.freshness.isDirty)
        XCTAssertTrue(
            exactScopeProjection.freshness
                .isCompleteForScope
        )

        XCTAssertEqual(
            FlowTabUITestProjectionAcknowledgementSnapshot
                .makeSnapshot(
                    projection: exactScopeProjection
                ),
            FlowTabUITestProjectionAcknowledgementSnapshot(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: processIdentifier,
                windowCount: 2,
                sourceGeneration:
                    "appLifecycle=0,cg=0,space=0,"
                    + "axDirty=1,projection=1",
                isComplete: true
            )
        )

        readModelStore.markAppWindowsDirty(
            appID: appID,
            pid: processIdentifier,
            pendingScope: "appWindows:\(appID)"
        )
        let incompleteExactScopeProjection = try XCTUnwrap(
            readModelStore.readCurrentAppWindowProjection(
                appID: appID
            )
        )
        XCTAssertEqual(
            FlowTabUITestProjectionAcknowledgementSnapshot
                .makeSnapshot(
                    projection:
                        incompleteExactScopeProjection
                )?
                .isComplete,
            false
        )
    }
}
