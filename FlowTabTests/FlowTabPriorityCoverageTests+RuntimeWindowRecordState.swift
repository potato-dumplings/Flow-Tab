import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testRuntimeCurrentAppWindowPayloadBuildsProjectionSeedFactsThroughAssemblyInput() throws {
        let app = NSRunningApplication.current
        let appID = "com.example.seeded-projection"
        let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
        let assemblyInput = RuntimeCurrentAppWindowProjectionAssemblyInput(
            appID: appID,
            displayName: "Seeded Projection",
            groupID: "seeded",
            summaryLastActiveAt: -2,
            candidateLastActiveAt: 120,
            pid: app.processIdentifier,
            runningApp: app,
            windowSeeds: [
                RuntimeAppWindowProjectionSeed(
                    windowID: "seed-window-a",
                    title: "Seed Window A",
                    isMinimized: false,
                    lastActiveAt: 119,
                    ownerPID: app.processIdentifier,
                    cgWindowID: 42_001,
                    spaceIDs: [3, 1, 3],
                    activationHandleID: "ax:seed-window-a",
                    frame: frame,
                    allowsPublicAXRecovery: true,
                    hasStickyBinding: true,
                    lastConfirmationSource: .verifiedFocusReadback,
                    bindingCandidateCount: 3
                ),
                RuntimeAppWindowProjectionSeed(
                    windowID: "seed-window-b",
                    title: "Seed Window B",
                    isMinimized: true,
                    lastActiveAt: 118,
                    ownerPID: app.processIdentifier,
                    cgWindowID: nil
                )
            ],
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: app)]
        )
        let payload = RuntimeCurrentAppWindowPayload(assemblyInput: assemblyInput)

        XCTAssertEqual(payload.summary.appID, appID)
        XCTAssertEqual(payload.summary.displayName, "Seeded Projection")
        XCTAssertEqual(payload.summary.groupID, "seeded")
        XCTAssertEqual(payload.summary.lastActiveAt, -2)
        XCTAssertEqual(payload.summary.windowCount, 2)
        XCTAssertEqual(payload.summary.pid, app.processIdentifier)
        XCTAssertEqual(payload.candidate.id, appID)
        XCTAssertEqual(payload.candidate.displayName, "Seeded Projection")
        XCTAssertEqual(payload.candidate.lastActiveAt, 120)
        XCTAssertEqual(payload.candidate.windows.map(\.id), ["seed-window-a", "seed-window-b"])
        XCTAssertEqual(payload.candidate.windows.map(\.lastActiveAt), [119, 118])
        XCTAssertEqual(payload.context.appID, appID)
        XCTAssertTrue(payload.context.runningApp === app)

        let seededContext = try XCTUnwrap(payload.context.windowsByID["seed-window-a"])
        XCTAssertEqual(seededContext.title, "Seed Window A")
        XCTAssertEqual(seededContext.ownerPID, app.processIdentifier)
        XCTAssertEqual(seededContext.cgWindowID, 42_001)
        XCTAssertEqual(seededContext.spaceIDs, [1, 3])
        XCTAssertEqual(seededContext.activationHandleID, "ax:seed-window-a")
        XCTAssertEqual(seededContext.frame, frame)
        XCTAssertTrue(seededContext.allowsPublicAXRecovery)
        XCTAssertTrue(seededContext.hasStickyBinding)
        XCTAssertEqual(seededContext.lastConfirmationSource, .verifiedFocusReadback)
        XCTAssertEqual(seededContext.bindingConfidence, .exact)
        XCTAssertEqual(seededContext.bindingCandidateCount, 3)

        let minimizedContext = try XCTUnwrap(payload.context.windowsByID["seed-window-b"])
        XCTAssertTrue(minimizedContext.isMinimized)
        XCTAssertEqual(minimizedContext.bindingConfidence, .provisional)

        XCTAssertEqual(payload.summary.appID, appID)
        XCTAssertEqual(payload.candidate.windows.map(\.id), ["seed-window-a", "seed-window-b"])
        XCTAssertEqual(payload.context.windowsByID.keys.sorted(), ["seed-window-a", "seed-window-b"])
    }

    func testRuntimeWindowMappingStateDerivesReverseAXCGIndex() {
        let state = RuntimeWindowMappingState(
            currentAXToCG: [
                "ax:18405:0": 240_001,
                "ax:18405:1": 243_747
            ],
            validCGWindowIDs: Set<CGWindowID>([240_001, 243_747, 250_000]),
            lastAXWindowIDs: Set(["ax:18405:0", "ax:18405:1"])
        )

        XCTAssertEqual(state.currentCGToAX[240_001], "ax:18405:0")
        XCTAssertEqual(state.currentCGToAX[243_747], "ax:18405:1")
        XCTAssertNil(state.currentCGToAX[250_000])
        XCTAssertEqual(state.validCGWindowIDs, Set<CGWindowID>([240_001, 243_747, 250_000]))
        XCTAssertEqual(state.lastAXWindowIDs, Set(["ax:18405:0", "ax:18405:1"]))
    }

    func testRuntimeWindowMappingStateClearsDestroyedAXAttachmentWithoutDeletingWindowRecord() {
        let pid = pid_t(18_405)
        let axWindowID = "ax:18405:0"
        let cgWindowID = CGWindowID(240_001)
        var record = RuntimeWindowRecord(
            cgWindowID: cgWindowID,
            stableWindowID: "cg:\(pid):\(cgWindowID)",
            firstSeenAt: 10
        )
        record.currentAXAttachment = RuntimeCurrentAXAttachment(
            axWindowID: axWindowID,
            axWindow: AXUIElementCreateApplication(pid),
            title: "Destroyed Window",
            frame: CGRect(x: 10, y: 10, width: 800, height: 600),
            state: RuntimeAXWindowState(isMinimized: false, isFocused: true, isMain: true)
        )
        record.lastExactAXWindowID = axWindowID
        record.lastConfirmationSource = .publicExactMatch
        var state = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: [cgWindowID: record],
            currentAXToCG: [axWindowID: cgWindowID],
            validCGWindowIDs: [cgWindowID],
            lastAXWindowIDs: [axWindowID]
        )

        let affectedCGWindowID = state.clearDestroyedAXAttachment(
            axWindowID: axWindowID,
            observedAt: 11
        )
        let downgradedRecord = state.windowRecordsByCGWindowID[cgWindowID]

        XCTAssertEqual(affectedCGWindowID, cgWindowID)
        XCTAssertNil(downgradedRecord?.currentAXAttachment)
        XCTAssertEqual(downgradedRecord?.lastExactAXWindowID, axWindowID)
        XCTAssertNil(downgradedRecord?.lastConfirmationSource)
        XCTAssertEqual(downgradedRecord?.bindingConfidence, .sticky)
        XCTAssertTrue(downgradedRecord?.needsReconciliation == true)
        XCTAssertEqual(downgradedRecord?.lastReconciliationMarkedAt, 11)
        XCTAssertNil(state.currentAXToCG[axWindowID])
        XCTAssertNil(state.currentCGToAX[cgWindowID])
        XCTAssertFalse(state.lastAXWindowIDs.contains(axWindowID))
    }

    func testRuntimeWindowMappingStateGroupsAffectedCGWindowIDsByPIDFromCurrentAndRecordedFacts() {
        let currentPID = pid_t(18_405)
        let recordedPID = pid_t(18_406)
        let currentWindowID = CGWindowID(240_001)
        let recordedWindowID = CGWindowID(240_002)
        let unrelatedWindowID = CGWindowID(240_003)
        let missingWindowID = CGWindowID(240_004)
        let currentCGWindowsByPID: [pid_t: [RuntimeCGWindowEntry]] = [
            currentPID: [
                RuntimeCGWindowEntry(
                    id: currentWindowID,
                    title: "Current",
                    bounds: CGRect(x: 10, y: 20, width: 640, height: 480),
                    isOnscreen: true,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [1]
                ),
                RuntimeCGWindowEntry(
                    id: unrelatedWindowID,
                    title: "Unrelated",
                    bounds: CGRect(x: 20, y: 30, width: 640, height: 480),
                    isOnscreen: true,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [1]
                )
            ]
        ]
        let recordedState = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: [
                recordedWindowID: RuntimeWindowRecord(
                    cgWindowID: recordedWindowID,
                    stableWindowID: "cg:\(recordedPID):\(recordedWindowID)",
                    firstSeenAt: 10
                )
            ]
        )

        let affectedByPID = RuntimeWindowMappingState.affectedCGWindowIDsByPID(
            affectedCGWindowIDs: [currentWindowID, recordedWindowID, missingWindowID],
            currentCGWindowsByPID: currentCGWindowsByPID,
            mappingStatesByPID: [recordedPID: recordedState]
        )

        XCTAssertEqual(
            affectedByPID,
            [
                currentPID: [currentWindowID],
                recordedPID: [recordedWindowID]
            ]
        )
    }

    func testRuntimeWindowMappingStateClassifiesTransientEmptyCurrentAppPayload() {
        let transientState = RuntimeWindowMappingState(
            hasObservedAXWindowHandle: true,
            consecutiveSnapshotsWithoutAXWindows: 1
        )
        let nonTransientMissingState = RuntimeWindowMappingState(
            hasObservedAXWindowHandle: false,
            consecutiveSnapshotsWithoutAXWindows: 1
        )
        let stableState = RuntimeWindowMappingState(
            hasObservedAXWindowHandle: true,
            consecutiveSnapshotsWithoutAXWindows: 0
        )

        XCTAssertTrue(transientState.isLikelyTransientAXRebuild)
        XCTAssertTrue(
            transientState.isTransientEmptyCurrentAppWindowPayload(
                currentAppWindowPayloadWasEmpty: true
            )
        )
        XCTAssertFalse(
            transientState.isTransientEmptyCurrentAppWindowPayload(
                currentAppWindowPayloadWasEmpty: false
            )
        )
        XCTAssertFalse(nonTransientMissingState.isLikelyTransientAXRebuild)
        XCTAssertFalse(
            nonTransientMissingState.isTransientEmptyCurrentAppWindowPayload(
                currentAppWindowPayloadWasEmpty: true
            )
        )
        XCTAssertFalse(stableState.isLikelyTransientAXRebuild)
        XCTAssertFalse(
            stableState.isTransientEmptyCurrentAppWindowPayload(
                currentAppWindowPayloadWasEmpty: true
            )
        )
    }

    func testRuntimeWindowMappingStateReportsAffectedWindowRecordEvidence() {
        let pid = pid_t(18_405)
        let exactWindowID = CGWindowID(240_001)
        let provisionalWindowID = CGWindowID(240_002)
        let missingWindowID = CGWindowID(240_003)
        var exactRecord = RuntimeWindowRecord(
            cgWindowID: exactWindowID,
            stableWindowID: "cg:\(pid):\(exactWindowID)",
            firstSeenAt: 10
        )
        exactRecord.lastConfirmationSource = .publicExactMatch
        let provisionalRecord = RuntimeWindowRecord(
            cgWindowID: provisionalWindowID,
            stableWindowID: "cg:\(pid):\(provisionalWindowID)",
            firstSeenAt: 10
        )
        let state = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: [
                exactWindowID: exactRecord,
                provisionalWindowID: provisionalRecord
            ]
        )

        let evidence = state.affectedWindowEvidence(
            for: [exactWindowID, provisionalWindowID, missingWindowID]
        )

        XCTAssertEqual(evidence.knownAffectedCGWindowIDs, [exactWindowID, provisionalWindowID])
        XCTAssertEqual(evidence.exactAffectedCGWindowIDs, [exactWindowID])
    }

    func testRuntimeWindowRecordKnownCGWindowsCombinesLiveFactsWithSynthesizedRecordEvidence() {
        let liveCGWindow = RuntimeCGWindowEntry(
            id: 240_001,
            title: "Live Title",
            bounds: CGRect(x: 10, y: 20, width: 900, height: 700),
            isOnscreen: true,
            alpha: 1.0,
            storeType: 1,
            spaceIDs: [1]
        )
        var staleRecord = RuntimeWindowRecord(
            cgWindowID: 240_002,
            stableWindowID: "cg:18405:240002",
            firstSeenAt: 10
        )
        staleRecord.lastKnownCGTitle = "Synthesized Title"
        staleRecord.lastKnownCGFrame = CGRect(x: 0, y: 124, width: 1_728, height: 993)
        staleRecord.spaceRecovery = RuntimeSpaceRecoveryState(
            cgWindowID: 240_002,
            spaceIDs: [11_682],
            hasConfirmedActivationRoute: true,
            lastValidatedAt: 10,
            invalidatedAt: nil
        )
        var liveBackedRecord = RuntimeWindowRecord(
            cgWindowID: liveCGWindow.id,
            stableWindowID: "cg:18405:240001",
            firstSeenAt: 10
        )
        liveBackedRecord.lastKnownCGTitle = "Old Title"

        let knownCGWindowsByID = RuntimeWindowRecord.knownCGWindowsByID(
            windowRecordsByCGWindowID: [
                liveCGWindow.id: liveBackedRecord,
                staleRecord.cgWindowID: staleRecord
            ],
            validCGWindows: [liveCGWindow]
        )

        XCTAssertEqual(knownCGWindowsByID[liveCGWindow.id]?.title, "Live Title")
        XCTAssertEqual(knownCGWindowsByID[liveCGWindow.id]?.isOnscreen, true)
        XCTAssertEqual(knownCGWindowsByID[staleRecord.cgWindowID]?.title, "Synthesized Title")
        XCTAssertEqual(knownCGWindowsByID[staleRecord.cgWindowID]?.bounds, staleRecord.lastKnownCGFrame)
        XCTAssertEqual(knownCGWindowsByID[staleRecord.cgWindowID]?.spaceIDs, [11_682])
        XCTAssertEqual(knownCGWindowsByID[staleRecord.cgWindowID]?.isOnscreen, false)

        let windowLayerCGWindows = RuntimeWindowRecord.windowLayerCGWindows(
            windowRecordsByCGWindowID: [
                liveCGWindow.id: liveBackedRecord,
                staleRecord.cgWindowID: staleRecord
            ],
            validCGWindows: [liveCGWindow]
        )
        XCTAssertEqual(windowLayerCGWindows.map(\.id), [liveCGWindow.id, staleRecord.cgWindowID])
        XCTAssertEqual(windowLayerCGWindows.map(\.isOnscreen), [true, false])
    }

    func testRuntimeWindowRecordStickyBindingReuseRequiresCompatibleTitleAndFrame() {
        let axElement = AXUIElementCreateApplication(NSRunningApplication.current.processIdentifier)
        let matchingFrame = CGRect(x: 10, y: 20, width: 900, height: 700)
        var record = RuntimeWindowRecord(
            cgWindowID: 240_003,
            stableWindowID: "cg:18405:240003",
            firstSeenAt: 10
        )
        record.lastKnownDisplayTitle = "Reusable Window"
        record.lastKnownCGFrame = matchingFrame
        let matchingAXWindow = RuntimeAXWindowEntry(
            index: 0,
            id: "ax:18405:sticky",
            title: "reusable window",
            sourceTitle: "reusable window",
            isMinimized: false,
            window: axElement,
            frame: matchingFrame.offsetBy(dx: 1, dy: -1)
        )
        let mismatchedTitleAXWindow = RuntimeAXWindowEntry(
            index: 1,
            id: "ax:18405:mismatch-title",
            title: "Different Window",
            sourceTitle: "Different Window",
            isMinimized: false,
            window: axElement,
            frame: matchingFrame
        )
        let mismatchedFrameAXWindow = RuntimeAXWindowEntry(
            index: 2,
            id: "ax:18405:mismatch-frame",
            title: "Reusable Window",
            sourceTitle: "Reusable Window",
            isMinimized: false,
            window: axElement,
            frame: CGRect(x: 400, y: 500, width: 900, height: 700)
        )

        XCTAssertTrue(record.canReuseStickyBinding(with: matchingAXWindow))
        XCTAssertFalse(record.canReuseStickyBinding(with: mismatchedTitleAXWindow))
        XCTAssertFalse(record.canReuseStickyBinding(with: mismatchedFrameAXWindow))
    }

    func testRuntimeWindowRecordReusableStickyAXWindowUsesCompatibleUnassignedExactID() {
        let axElement = AXUIElementCreateApplication(NSRunningApplication.current.processIdentifier)
        let matchingFrame = CGRect(x: 10, y: 20, width: 900, height: 700)
        var record = RuntimeWindowRecord(
            cgWindowID: 240_003,
            stableWindowID: "cg:18405:240003",
            firstSeenAt: 10
        )
        record.lastKnownDisplayTitle = "Reusable Window"
        record.lastKnownCGFrame = matchingFrame
        record.lastExactAXWindowID = "ax:18405:sticky"
        let matchingAXWindow = RuntimeAXWindowEntry(
            index: 0,
            id: "ax:18405:sticky",
            title: "reusable window",
            sourceTitle: "reusable window",
            isMinimized: false,
            window: axElement,
            frame: matchingFrame.offsetBy(dx: 1, dy: -1)
        )
        let mismatchedAXWindow = RuntimeAXWindowEntry(
            index: 1,
            id: "ax:18405:sticky",
            title: "Different Window",
            sourceTitle: "Different Window",
            isMinimized: false,
            window: axElement,
            frame: matchingFrame
        )

        XCTAssertEqual(
            record.reusableStickyAXWindow(
                from: [matchingAXWindow],
                assignedAXWindowIDs: []
            )?.id,
            matchingAXWindow.id
        )
        XCTAssertNil(
            record.reusableStickyAXWindow(
                from: [matchingAXWindow],
                assignedAXWindowIDs: [matchingAXWindow.id]
            )
        )
        XCTAssertNil(
            record.reusableStickyAXWindow(
                from: [mismatchedAXWindow],
                assignedAXWindowIDs: []
            )
        )
    }

    func testRuntimeWindowRecordReusableStickyAXWindowUsesPreviousAXElementIdentity() {
        let previousAXElement = AXUIElementCreateApplication(NSRunningApplication.current.processIdentifier)
        var record = RuntimeWindowRecord(
            cgWindowID: 240_003,
            stableWindowID: "cg:18405:240003",
            firstSeenAt: 10
        )
        record.lastKnownDisplayTitle = "Original Window"
        record.lastKnownCGFrame = CGRect(x: 10, y: 20, width: 900, height: 700)
        record.lastExactAXWindowID = "ax:18405:old"
        record.lastExactAXWindow = previousAXElement
        let renamedAXWindow = RuntimeAXWindowEntry(
            index: 0,
            id: "ax:18405:new",
            title: "Renamed Window",
            sourceTitle: "Renamed Window",
            isMinimized: false,
            window: previousAXElement,
            frame: CGRect(x: 400, y: 500, width: 900, height: 700)
        )

        XCTAssertEqual(
            record.reusableStickyAXWindow(
                from: [renamedAXWindow],
                assignedAXWindowIDs: []
            )?.id,
            renamedAXWindow.id
        )
        XCTAssertNil(
            record.reusableStickyAXWindow(
                from: [renamedAXWindow],
                assignedAXWindowIDs: [renamedAXWindow.id]
            )
        )
    }

    func testRuntimeWindowRecordLifecycleKeepsRecoverableMissingEvidenceDuringGraceWindow() {
        let policy = RuntimeWindowRecordLifecyclePolicy(evidenceGraceInterval: 1.0)
        let cgWindow = RuntimeCGWindowEntry(
            id: 240_001,
            title: "Recovered Window",
            bounds: CGRect(x: 20, y: 30, width: 800, height: 600),
            isOnscreen: false,
            alpha: 1.0,
            storeType: 1,
            spaceIDs: [11_679]
        )
        var record = RuntimeWindowRecord(
            cgWindowID: cgWindow.id,
            stableWindowID: "cg:18405:240001",
            firstSeenAt: 10
        )
        record.refreshCGState(from: cgWindow, observedAt: 10)

        let firstMissingDecision = record.reconcileLifecycle(
            validCGWindowIDs: [],
            observedAt: 11,
            policy: policy
        )
        let secondMissingDecision = record.reconcileLifecycle(
            validCGWindowIDs: [],
            observedAt: 11.5,
            policy: policy
        )
        let expiredDecision = record.reconcileLifecycle(
            validCGWindowIDs: [],
            observedAt: 12,
            policy: policy
        )

        XCTAssertEqual(firstMissingDecision, .keep)
        XCTAssertEqual(secondMissingDecision, .keep)
        XCTAssertEqual(expiredDecision, .delete)
        XCTAssertEqual(record.suspectDeletedAt, 11)
        XCTAssertEqual(record.spaceRecovery?.invalidatedAt, 11)
    }

    func testRuntimeWindowRecordLifecycleClearsSuspectStateWhenCGEvidenceReturns() {
        let cgWindow = RuntimeCGWindowEntry(
            id: 243_747,
            title: "Recovered Window",
            bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
            isOnscreen: false,
            alpha: 1.0,
            storeType: 1,
            spaceIDs: [11_680]
        )
        var record = RuntimeWindowRecord(
            cgWindowID: cgWindow.id,
            stableWindowID: "cg:18405:243747",
            firstSeenAt: 20
        )
        record.refreshCGState(from: cgWindow, observedAt: 20)

        XCTAssertEqual(
            record.reconcileLifecycle(validCGWindowIDs: [], observedAt: 21),
            .keep
        )
        XCTAssertEqual(record.suspectDeletedAt, 21)

        record.refreshCGState(from: cgWindow, observedAt: 21.2)
        XCTAssertEqual(
            record.reconcileLifecycle(validCGWindowIDs: [cgWindow.id], observedAt: 21.2),
            .keep
        )
        XCTAssertNil(record.suspectDeletedAt)
        XCTAssertNil(record.spaceRecovery?.invalidatedAt)
    }

    func testRuntimeWindowRecordClearsReconciliationNeedWhenCGEvidenceReturns() {
        let cgWindow = RuntimeCGWindowEntry(
            id: 243_748,
            title: "Topology Window",
            bounds: CGRect(x: 12, y: 124, width: 900, height: 700),
            isOnscreen: false,
            alpha: 1.0,
            storeType: 1,
            spaceIDs: [11_684]
        )
        var record = RuntimeWindowRecord(
            cgWindowID: cgWindow.id,
            stableWindowID: "cg:18405:243748",
            firstSeenAt: 20
        )

        record.markNeedsReconciliation(observedAt: 21)
        record.refreshCGState(from: cgWindow, observedAt: 22)

        XCTAssertFalse(record.needsReconciliation)
        XCTAssertEqual(record.lastReconciliationMarkedAt, 21)
    }

    func testRuntimeWindowRecordClearsReconciliationNeedAfterLifecycleReconciliation() {
        let policy = RuntimeWindowRecordLifecyclePolicy(evidenceGraceInterval: 1.0)
        var record = RuntimeWindowRecord(
            cgWindowID: 243_749,
            stableWindowID: "cg:18405:243749",
            firstSeenAt: 20
        )
        record.spaceRecovery = RuntimeSpaceRecoveryState(
            cgWindowID: 243_749,
            spaceIDs: [11_685],
            hasConfirmedActivationRoute: true,
            lastValidatedAt: 20,
            invalidatedAt: nil
        )

        record.markNeedsReconciliation(observedAt: 21)
        let decision = record.reconcileLifecycle(
            validCGWindowIDs: [],
            observedAt: 21.2,
            policy: policy
        )

        XCTAssertEqual(decision, .keep)
        XCTAssertFalse(record.needsReconciliation)
        XCTAssertEqual(record.lastReconciliationMarkedAt, 21)
    }

    func testRuntimeSnapshotProviderDropsWindowRecordAfterLifecycleGraceExpires() {
        let provider = RuntimeSnapshotProvider()
        let pid: pid_t = 18_405
        let now = Date.timeIntervalSinceReferenceDate
        var staleRecord = RuntimeWindowRecord(
            cgWindowID: 250_000,
            stableWindowID: "cg:18405:250000",
            firstSeenAt: now - 3
        )
        staleRecord.spaceRecovery = RuntimeSpaceRecoveryState(
            cgWindowID: 250_000,
            spaceIDs: [11_681],
            hasConfirmedActivationRoute: true,
            lastValidatedAt: now - 3,
            invalidatedAt: now - 2
        )
        staleRecord.suspectDeletedAt = now - 2
        provider.windowMappingStateByPID[pid] = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: [250_000: staleRecord]
        )

        let resolution = provider.resolveStableWindowMapping(
            axWindows: [],
            cgWindows: [],
            pid: pid,
            appName: "Google Chrome"
        )

        XCTAssertTrue(resolution.windowRecordsByCGWindowID.isEmpty)
        XCTAssertNil(provider.windowMappingStateByPID[pid])
    }

    func testRuntimeSnapshotProviderWindowLayerExposesInGraceStickyRecordWithoutCurrentCGEvidence() {
        let provider = RuntimeSnapshotProvider()
        let pid: pid_t = 18_405
        let now = Date.timeIntervalSinceReferenceDate
        var record = RuntimeWindowRecord(
            cgWindowID: 250_001,
            stableWindowID: "cg:18405:250001",
            firstSeenAt: now - 1
        )
        record.lastKnownCGTitle = "Recovered Sticky"
        record.lastKnownDisplayTitle = "Recovered Sticky"
        record.lastKnownCGFrame = CGRect(x: 0, y: 124, width: 1_728, height: 993)
        record.lastConfirmationSource = .stickyBinding
        record.lastExactAXWindowID = "ax:18405:sticky"
        record.spaceRecovery = RuntimeSpaceRecoveryState(
            cgWindowID: 250_001,
            spaceIDs: [11_682],
            hasConfirmedActivationRoute: true,
            lastValidatedAt: now - 1,
            invalidatedAt: now
        )
        record.suspectDeletedAt = now
        provider.windowMappingStateByPID[pid] = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: [250_001: record]
        )

        let entries = provider.resolvedStableWindowEntries(
            axWindows: [],
            cgWindows: [],
            pid: pid,
            appName: "Google Chrome"
        )

        XCTAssertEqual(entries.map(\.windowID), ["cg:18405:250001"])
        XCTAssertEqual(entries.first?.title, "Recovered Sticky")
        XCTAssertEqual(entries.first?.cgWindowID, 250_001)
        XCTAssertEqual(entries.first?.spaceIDs, [11_682])
        XCTAssertTrue(entries.first?.hasStickyBinding == true)
        XCTAssertNil(entries.first?.activationHandleID)
    }

    func testRuntimeSnapshotProviderWindowLayerExposesInGraceSpaceBackedRecordWithoutStickyBinding() {
        let provider = RuntimeSnapshotProvider()
        let pid: pid_t = 18_405
        let now = Date.timeIntervalSinceReferenceDate
        var record = RuntimeWindowRecord(
            cgWindowID: 250_002,
            stableWindowID: "cg:18405:250002",
            firstSeenAt: now - 1
        )
        record.lastKnownCGTitle = "Recovered Space"
        record.lastKnownDisplayTitle = "Recovered Space"
        record.lastKnownCGFrame = CGRect(x: 30, y: 124, width: 1_200, height: 820)
        record.spaceRecovery = RuntimeSpaceRecoveryState(
            cgWindowID: 250_002,
            spaceIDs: [11_683],
            hasConfirmedActivationRoute: true,
            lastValidatedAt: now - 1,
            invalidatedAt: now
        )
        record.suspectDeletedAt = now
        provider.windowMappingStateByPID[pid] = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: [250_002: record]
        )

        let entries = provider.resolvedStableWindowEntries(
            axWindows: [],
            cgWindows: [],
            pid: pid,
            appName: "Google Chrome"
        )

        XCTAssertEqual(entries.map(\.windowID), ["cg:18405:250002"])
        XCTAssertEqual(entries.first?.title, "Recovered Space")
        XCTAssertEqual(entries.first?.cgWindowID, 250_002)
        XCTAssertEqual(entries.first?.spaceIDs, [11_683])
        XCTAssertTrue(entries.first?.hasStickyBinding == false)
        XCTAssertNil(entries.first?.activationHandleID)
    }
}
