import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    func testWindowBindingSourcesExposeExplicitConfidence() {
        XCTAssertEqual(WindowBindingConfirmationSource.publicExactMatch.bindingConfidence, .exact)
        XCTAssertEqual(WindowBindingConfirmationSource.privateExactBridge.bindingConfidence, .exact)
        XCTAssertEqual(WindowBindingConfirmationSource.verifiedFocusReadback.bindingConfidence, .exact)
        XCTAssertEqual(WindowBindingConfirmationSource.stickyBinding.bindingConfidence, .sticky)
        XCTAssertEqual(WindowBindingConfirmationSource.fullscreenContentRebinding.bindingConfidence, .inferred)
        XCTAssertEqual(WindowBindingConfirmationSource.fullscreenContentFallbackBinding.bindingConfidence, .inferred)
        XCTAssertEqual(WindowBindingConfirmationSource.desktopSiblingBinding.bindingConfidence, .inferred)

        let provisionalEntry = RuntimeSnapshotProvider.WindowListEntry(
            windowID: "cg:42:101",
            title: "Draft",
            isMinimized: false,
            cgWindowID: 101
        )
        XCTAssertEqual(provisionalEntry.bindingConfidence, .provisional)

        let stickyEntry = RuntimeSnapshotProvider.WindowListEntry(
            windowID: "cg:42:102",
            title: "Inbox",
            isMinimized: false,
            cgWindowID: 102,
            hasStickyBinding: true
        )
        XCTAssertEqual(stickyEntry.bindingConfidence, .sticky)

        let context = RuntimeWindowContext(
            id: "cg:42:103",
            title: "Report",
            isMinimized: false,
            cgWindowID: 103,
            hasStickyBinding: true,
            lastConfirmationSource: .privateExactBridge
        )
        XCTAssertEqual(context.bindingConfidence, .exact)
        XCTAssertEqual(
            WindowBindingConfidence.exact.allowedActions,
            [
                .exposeInSwitcher,
                .useForAXActivation,
                .useForCGActivationFallback,
                .updateStickyHistory,
                .updateRecency,
                .capturePreview
            ]
        )
        XCTAssertFalse(WindowBindingConfidence.sticky.allowedActions.contains(.updateStickyHistory))
        XCTAssertFalse(WindowBindingConfidence.inferred.allowedActions.contains(.updateRecency))
        XCTAssertEqual(
            WindowBindingConfidence.provisional.allowedActions,
            [.capturePreview]
        )
        XCTAssertEqual(WindowBindingConfidence.ambiguous.allowedActions, [.quarantineOnly])
        XCTAssertTrue(
            WindowBindingDiagnostic(
                stableWindowID: "ambiguous",
                axWindowID: nil,
                cgWindowID: nil,
                confidence: .ambiguous,
                source: nil,
                reason: nil,
                candidateCount: 2,
                allowedActions: WindowBindingConfidence.ambiguous.allowedActions
            ).isQuarantined
        )
        XCTAssertEqual(context.bindingDiagnostic.confidence, .exact)
        XCTAssertEqual(context.bindingDiagnostic.source, .privateExactBridge)
        XCTAssertTrue(context.bindingDiagnostic.allowedActions.contains(.useForAXActivation))
        XCTAssertEqual(provisionalEntry.bindingDiagnostic.confidence, .provisional)
        XCTAssertFalse(provisionalEntry.bindingDiagnostic.allowedActions.contains(.exposeInSwitcher))
        XCTAssertFalse(provisionalEntry.bindingDiagnostic.allowedActions.contains(.useForAXActivation))

        let ambiguousEntry = RuntimeSnapshotProvider.WindowListEntry(
            windowID: "cg:42:104",
            title: "Ambiguous",
            isMinimized: false,
            cgWindowID: 104,
            bindingConfidenceOverride: .ambiguous,
            bindingCandidateCount: 2
        )
        XCTAssertEqual(ambiguousEntry.bindingConfidence, .ambiguous)
        XCTAssertEqual(ambiguousEntry.bindingDiagnostic.candidateCount, 2)
        XCTAssertTrue(ambiguousEntry.bindingDiagnostic.isQuarantined)

        let ambiguousContext = RuntimeWindowContext(
            id: "cg:42:105",
            title: "Ambiguous Context",
            isMinimized: false,
            cgWindowID: 105,
            bindingConfidenceOverride: .ambiguous,
            bindingCandidateCount: 2
        )
        XCTAssertEqual(ambiguousContext.bindingConfidence, .ambiguous)
        XCTAssertEqual(ambiguousContext.bindingDiagnostic.candidateCount, 2)
        XCTAssertFalse(ambiguousContext.bindingAllowedActions.contains(.capturePreview))
    }

    func testRuntimeSnapshotProviderWindowListEntryProjectionSeedPreservesRuntimeEvidence() {
        let spaceEvidence = RuntimeSpaceEvidence(
            cgWindowID: 204,
            spaceIDs: [3, 7],
            confidence: .inferredFromTopology,
            displayID: 99,
            source: "unit"
        )
        let entry = RuntimeSnapshotProvider.WindowListEntry(
            windowID: "cg:4242:204",
            title: "Runtime Evidence",
            isMinimized: true,
            ownerPID: 4_242,
            cgWindowID: 204,
            activationHandleID: "ax:4242:204",
            frame: CGRect(x: 10, y: 20, width: 300, height: 200),
            spaceIDs: [7, 3, 3],
            isOnscreen: false,
            allowsPublicAXRecovery: true,
            hasStickyBinding: true,
            lastConfirmationSource: .desktopSiblingBinding,
            bindingConfidenceOverride: .inferred,
            bindingCandidateCount: 3,
            spaceEvidence: spaceEvidence
        )

        let seed = entry.projectionSeed(lastActiveAt: 12_345)

        XCTAssertEqual(seed.candidate.id, "cg:4242:204")
        XCTAssertEqual(seed.candidate.title, "Runtime Evidence")
        XCTAssertEqual(seed.candidate.isMinimized, true)
        XCTAssertEqual(seed.candidate.lastActiveAt, 12_345)
        XCTAssertEqual(seed.context.ownerPID, 4_242)
        XCTAssertEqual(seed.context.cgWindowID, 204)
        XCTAssertEqual(seed.context.spaceIDs, [3, 7])
        XCTAssertEqual(seed.context.activationHandleID, "ax:4242:204")
        XCTAssertEqual(seed.context.frame, CGRect(x: 10, y: 20, width: 300, height: 200))
        XCTAssertEqual(seed.context.allowsPublicAXRecovery, true)
        XCTAssertEqual(seed.context.hasStickyBinding, true)
        XCTAssertEqual(seed.context.lastConfirmationSource, .desktopSiblingBinding)
        XCTAssertEqual(seed.context.bindingConfidence, .inferred)
        XCTAssertEqual(seed.context.bindingCandidateCount, 3)
        XCTAssertEqual(seed.context.spaceEvidence, spaceEvidence)
    }

    func testRuntimeWindowRecordOnlyExactMatchesUpdateStickyHistory() {
        let currentApp = NSRunningApplication.current
        let cgWindow = RuntimeCGWindowEntry(
            id: 24_501,
            title: "Fullscreen Candidate",
            bounds: CGRect(x: 40, y: 80, width: 960, height: 640),
            isOnscreen: true,
            alpha: 1.0,
            storeType: 1,
            spaceIDs: [8_401]
        )
        let inferredAXWindow = RuntimeAXWindowEntry(
            index: 0,
            id: "ax:\(currentApp.processIdentifier):inferred",
            title: "Fullscreen Candidate",
            sourceTitle: "Fullscreen Candidate",
            isMinimized: false,
            window: AXUIElementCreateApplication(currentApp.processIdentifier),
            frame: cgWindow.bounds
        )
        var record = RuntimeWindowRecord(
            cgWindowID: cgWindow.id,
            stableWindowID: "cg:\(currentApp.processIdentifier):\(cgWindow.id)",
            firstSeenAt: 10
        )

        record.applyExactMatch(
            axWindow: inferredAXWindow,
            resolvedTitle: "Fullscreen Candidate",
            confirmationSource: .fullscreenContentFallbackBinding,
            observedAt: 11,
            matchedCGWindow: cgWindow
        )

        XCTAssertEqual(record.currentAXWindowID, inferredAXWindow.id)
        XCTAssertEqual(record.lastConfirmationSource, .fullscreenContentFallbackBinding)
        XCTAssertEqual(record.bindingConfidence, .inferred)
        XCTAssertNil(record.lastExactAXWindowID)
        XCTAssertNil(record.lastExactAXWindow)
        XCTAssertNil(record.lastExactConfirmedAt)

        let exactAXWindow = RuntimeAXWindowEntry(
            index: 1,
            id: "ax:\(currentApp.processIdentifier):exact",
            title: "Fullscreen Candidate",
            sourceTitle: "Fullscreen Candidate",
            isMinimized: false,
            window: AXUIElementCreateApplication(currentApp.processIdentifier),
            frame: cgWindow.bounds
        )
        record.applyExactMatch(
            axWindow: exactAXWindow,
            resolvedTitle: "Fullscreen Candidate",
            confirmationSource: .publicExactMatch,
            observedAt: 12,
            matchedCGWindow: cgWindow
        )

        XCTAssertEqual(record.currentAXWindowID, exactAXWindow.id)
        XCTAssertEqual(record.lastConfirmationSource, .publicExactMatch)
        XCTAssertEqual(record.bindingConfidence, .exact)
        XCTAssertEqual(record.lastExactAXWindowID, exactAXWindow.id)
        XCTAssertNotNil(record.lastExactAXWindow)
        XCTAssertEqual(record.lastExactConfirmedAt, 12)
    }

    func testRuntimeFullRepairProjectionAssemblerSortsCurrentAppInputsAndBuildsContexts() {
        let currentApp = NSRunningApplication.current
        let payload = RuntimeFullRepairProjectionAssembler.payload(
            fromCurrentAppWindowProjectionInputs: [
                RuntimeCurrentAppWindowProjectionAssemblyInput(
                    appID: "com.example.notes",
                    displayName: "Notes",
                    groupID: "example",
                    summaryLastActiveAt: -3,
                    candidateLastActiveAt: 997,
                    pid: 30,
                    runningApp: currentApp,
                    windowSeeds: []
                ),
                RuntimeCurrentAppWindowProjectionAssemblyInput(
                    appID: "com.example.mail",
                    displayName: "Mail",
                    groupID: "example",
                    summaryLastActiveAt: 0,
                    candidateLastActiveAt: 1_000,
                    pid: 11,
                    runningApp: currentApp,
                    windowSeeds: [
                        RuntimeAppWindowProjectionSeed(
                            windowID: "mail-1",
                            title: "Inbox",
                            isMinimized: false,
                            lastActiveAt: 1_000,
                            ownerPID: 11,
                            cgWindowID: 11
                        ),
                        RuntimeAppWindowProjectionSeed(
                            windowID: "mail-2",
                            title: "Draft",
                            isMinimized: false,
                            lastActiveAt: 999,
                            ownerPID: 11,
                            cgWindowID: 12
                        )
                    ]
                )
            ]
        )

        XCTAssertEqual(payload.apps.map(\.id), ["com.example.mail", "com.example.notes"])
        XCTAssertEqual(payload.apps.first?.windows.map(\.id), ["mail-1", "mail-2"])
        XCTAssertEqual(payload.contextsByID.keys.sorted(), ["com.example.mail", "com.example.notes"])
        XCTAssertEqual(payload.contextsByID["com.example.mail"]?.windowsByID["mail-1"]?.cgWindowID, 11)
        XCTAssertEqual(payload.contextsByID["com.example.mail"]?.windowsByID["mail-2"]?.ownerPID, 11)
    }

    func testRuntimeCurrentAppWindowProjectionAssemblyInputBuildsRankedPayloadFacts() {
        let currentApp = NSRunningApplication.current
        let pid = currentApp.processIdentifier
        let input = RuntimeCurrentAppWindowProjectionAssemblyInput(
            appID: "com.example.current",
            app: currentApp,
            appGroup: [currentApp],
            rankByPID: [pid: 4],
            rankFallback: 10_000,
            generatedAt: 1_000,
            windowSeeds: [
                RuntimeAppWindowProjectionSeed(
                    windowID: "current-1",
                    title: "Current Window",
                    isMinimized: false,
                    lastActiveAt: 999,
                    ownerPID: pid,
                    cgWindowID: 400
                )
            ]
        )
        let payload = RuntimeCurrentAppWindowPayload(assemblyInput: input)

        XCTAssertEqual(input.summaryLastActiveAt, -4)
        XCTAssertEqual(input.candidateLastActiveAt, 996)
        XCTAssertEqual(input.pid, pid)
        XCTAssertEqual(payload.summary.appID, "com.example.current")
        XCTAssertEqual(payload.summary.windowCount, 1)
        XCTAssertEqual(payload.candidate.windows.map(\.id), ["current-1"])
        XCTAssertEqual(payload.context.windowsByID["current-1"]?.cgWindowID, 400)
    }

    func testRuntimeFullRepairProjectionAssemblerBuildsPayloadContextsFromCurrentAppInputs() {
        let currentApp = NSRunningApplication.current
        let evidence = RuntimeSpaceEvidence(
            cgWindowID: 710,
            spaceIDs: [5, 2],
            confidence: .observed,
            displayID: 44,
            source: "unit"
        )
        let payload = RuntimeFullRepairProjectionAssembler.payload(
            fromCurrentAppWindowProjectionInputs: [
                RuntimeCurrentAppWindowProjectionAssemblyInput(
                    appID: "com.example.alpha",
                    displayName: "Alpha",
                    groupID: "alpha",
                    summaryLastActiveAt: -2,
                    candidateLastActiveAt: 2_000,
                    pid: 710,
                    runningApp: currentApp,
                    windowSeeds: [
                        RuntimeAppWindowProjectionSeed(
                            windowID: "alpha-window",
                            title: "Alpha Window",
                            isMinimized: false,
                            lastActiveAt: 2_000,
                            ownerPID: 710,
                            cgWindowID: 710,
                            spaceIDs: [5, 2, 2],
                            activationHandleID: "ax:710:window",
                            frame: CGRect(x: 1, y: 2, width: 300, height: 200),
                            allowsPublicAXRecovery: true,
                            hasStickyBinding: true,
                            lastConfirmationSource: .verifiedFocusReadback,
                            bindingCandidateCount: 1,
                            spaceEvidence: evidence
                        )
                    ]
                ),
                RuntimeCurrentAppWindowProjectionAssemblyInput(
                    appID: "com.example.beta",
                    displayName: "Beta",
                    groupID: "beta",
                    summaryLastActiveAt: -1,
                    candidateLastActiveAt: 3_000,
                    pid: 711,
                    runningApp: currentApp,
                    windowSeeds: []
                )
            ]
        )

        XCTAssertEqual(payload.apps.map(\.id), ["com.example.beta", "com.example.alpha"])
        XCTAssertEqual(payload.contextsByID.keys.sorted(), ["com.example.alpha", "com.example.beta"])

        let alpha = payload.apps.first { $0.id == "com.example.alpha" }
        XCTAssertEqual(alpha?.displayName, "Alpha")
        XCTAssertEqual(alpha?.windows.map(\.id), ["alpha-window"])

        let alphaContext = payload.contextsByID["com.example.alpha"]
        let alphaWindow = alphaContext?.windowsByID["alpha-window"]
        XCTAssertEqual(alphaContext?.appID, "com.example.alpha")
        XCTAssertTrue(alphaContext?.runningApp === currentApp)
        XCTAssertEqual(alphaWindow?.ownerPID, 710)
        XCTAssertEqual(alphaWindow?.cgWindowID, 710)
        XCTAssertEqual(alphaWindow?.spaceIDs, [2, 5])
        XCTAssertEqual(alphaWindow?.activationHandleID, "ax:710:window")
        XCTAssertEqual(alphaWindow?.frame, CGRect(x: 1, y: 2, width: 300, height: 200))
        XCTAssertEqual(alphaWindow?.allowsPublicAXRecovery, true)
        XCTAssertEqual(alphaWindow?.hasStickyBinding, true)
        XCTAssertEqual(alphaWindow?.lastConfirmationSource, .verifiedFocusReadback)
        XCTAssertEqual(alphaWindow?.bindingConfidence, .exact)
        XCTAssertEqual(alphaWindow?.bindingCandidateCount, 1)
        XCTAssertEqual(alphaWindow?.spaceEvidence, evidence)
    }

    func testRuntimeAppDirectoryMergedWindowStatsCombinesCountsAcrossProcessIDs() {
        let mergedStats = RuntimeAppDirectory.mergedWindowStats(
            processIDs: [101, 102, 103],
            windowStatsByPID: [
                101: .init(windowCount: 2, hasVisibleWindow: false),
                102: .init(windowCount: 3, hasVisibleWindow: true),
                103: .init(windowCount: 0, hasVisibleWindow: false)
            ]
        )

        XCTAssertEqual(mergedStats.windowCount, 5)
        XCTAssertTrue(mergedStats.hasVisibleWindow)
    }

    func testRuntimeSnapshotProviderValidCGWindowsFilterSkipsInvalidEntries() {
        let validWindowIDs = RuntimeSnapshotProvider.validCGWindowIDsForTesting(
            existingCGWindowIDs: Set<CGWindowID>([240016]),
            allCGWindows: [
                .init(
                    id: 240016,
                    title: "Visible",
                    bounds: CGRect(x: 0, y: 38, width: 1_728, height: 1_079),
                    isOnscreen: true
                ),
                .init(
                    id: 243747,
                    title: "Recovered 1",
                    bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                    isOnscreen: false
                ),
                .init(
                    id: 260000,
                    title: "Recovered 2",
                    bounds: CGRect(x: 200, y: 160, width: 420, height: 240),
                    isOnscreen: false
                ),
                .init(
                    id: 243749,
                    title: "Too Short",
                    bounds: CGRect(x: 0, y: 37, width: 1_728, height: 41),
                    isOnscreen: false
                ),
                .init(
                    id: 245064,
                    title: "Transparent",
                    bounds: CGRect(x: 0, y: 38, width: 1_728, height: 1_079),
                    isOnscreen: false,
                    alpha: 0.0003
                ),
                .init(
                    id: 240080,
                    title: "Wrong Store",
                    bounds: CGRect(x: 0, y: 0, width: 1_728, height: 1_079),
                    isOnscreen: false,
                    storeType: 2
                ),
                .init(
                    id: 240018,
                    title: "Tiny",
                    bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                    isOnscreen: false
                )
            ]
        )

        XCTAssertEqual(validWindowIDs, [243747, 260000])
    }

    func testRuntimeSnapshotProviderSupplementalCGWindowTitleUsesAppNameWhenCGTitleMissing() {
        let windowID: CGWindowID = 243747
        let cachedTitle = "百度一下，你就知道 - Google Chrome - test2"
        let appName = "Google Chrome"

        let titleFromFallback = RuntimeSnapshotProvider.supplementalCGWindowTitleForTesting(
            appName: appName,
            cgWindow: .init(
                id: windowID,
                title: nil,
                bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                isOnscreen: false
            ),
            cachedAXTitlesByCGWindowID: [windowID: cachedTitle]
        )
        XCTAssertEqual(titleFromFallback, appName)

        let titleFromCG = RuntimeSnapshotProvider.supplementalCGWindowTitleForTesting(
            appName: appName,
            cgWindow: .init(
                id: windowID,
                title: "From CG",
                bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                isOnscreen: false
            ),
            cachedAXTitlesByCGWindowID: [windowID: cachedTitle]
        )
        XCTAssertEqual(titleFromCG, "From CG")
    }

    func testRuntimeSnapshotProviderSupplementalCGWindowTitleFallsBackToAppNameWhenUntitled() {
        let title = RuntimeSnapshotProvider.supplementalCGWindowTitleForTesting(
            appName: "Google Chrome",
            cgWindow: .init(
                id: 243679,
                title: nil,
                bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                isOnscreen: false
            ),
            cachedAXTitlesByCGWindowID: [:]
        )

        XCTAssertEqual(title, "Google Chrome")
    }

    func testRuntimeSnapshotProviderWindowListAppendsUnmatchedCGEntriesAfterExactMatches() {
        let mergedEntries = RuntimeSnapshotProvider.appendOffSpaceCGWindowsForTesting(
            entries: [
                .init(
                    windowID: "cg:18405:240001",
                    title: "Normal 1",
                    isMinimized: false,
                    cgWindowID: 240_001
                ),
                .init(
                    windowID: "cg:18405:240002",
                    title: "Normal 2",
                    isMinimized: false,
                    cgWindowID: 240_002
                )
            ],
            appName: "Google Chrome",
            pid: 18405,
            allCGWindows: [
                .init(
                    id: 240_001,
                    title: "Normal 1",
                    bounds: CGRect(x: 0, y: 38, width: 1_200, height: 800),
                    isOnscreen: true
                ),
                .init(
                    id: 240_002,
                    title: "Normal 2",
                    bounds: CGRect(x: 20, y: 58, width: 1_200, height: 800),
                    isOnscreen: true
                ),
                .init(
                    id: 243_747,
                    title: "Fullscreen 3",
                    bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                    isOnscreen: false
                ),
                .init(
                    id: 243_679,
                    title: nil,
                    bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                    isOnscreen: false
                )
            ],
            matchedCGWindowIDs: Set<CGWindowID>([240_001, 240_002])
        )

        XCTAssertEqual(
            mergedEntries.map(\.windowID),
            ["cg:18405:240001", "cg:18405:240002", "cg:18405:243747", "cg:18405:243679"]
        )
        XCTAssertEqual(mergedEntries[2].title, "Fullscreen 3")
        XCTAssertEqual(mergedEntries[3].title, "Google Chrome")
    }

    func testRuntimeSnapshotProviderWindowListDoesNotExposeProvisionalCGOnlyEntriesWithoutRecoveryEvidence() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let mergedEntries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [
                .init(
                    id: "ax:18405:0",
                    index: 0,
                    title: "Google 搜索 - Google Chrome - test1",
                    bounds: fullscreenBounds
                ),
                .init(
                    id: "ax:18405:1",
                    index: 1,
                    title: "Only In AX",
                    bounds: CGRect(x: 60, y: 98, width: 1_728, height: 1_079)
                )
            ],
            cgWindows: [
                .init(
                    id: 240_001,
                    title: "Google 搜索 - Google Chrome - test1",
                    bounds: fullscreenBounds,
                    isOnscreen: true
                ),
                .init(
                    id: 243_747,
                    title: "Recovered Tab",
                    bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                    isOnscreen: false
                )
            ],
            pid: 18405,
            appName: "Google Chrome"
        )

        XCTAssertEqual(
            mergedEntries.map(\.windowID),
            ["cg:18405:240001"]
        )
        XCTAssertEqual(mergedEntries.first?.cgWindowID, 240_001)
        XCTAssertEqual(mergedEntries.first?.title, "Google 搜索 - Google Chrome - test1")
        XCTAssertEqual(mergedEntries.first?.lastConfirmationSource, .publicExactMatch)
    }

    func testRuntimeSnapshotProviderWindowListUsesPrivateExactBridgeWhenPublicSignalsRemainAmbiguous() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let mergedEntries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [
                .init(
                    id: "ax:18405:0",
                    index: 0,
                    title: "Google 搜索 - Google Chrome",
                    bounds: fullscreenBounds,
                    bridgedCGWindowID: 240_001
                ),
                .init(
                    id: "ax:18405:1",
                    index: 1,
                    title: "Google 搜索 - Google Chrome",
                    bounds: fullscreenBounds,
                    bridgedCGWindowID: 240_002
                )
            ],
            cgWindows: [
                .init(
                    id: 240_001,
                    title: "Google 搜索 - Google Chrome",
                    bounds: fullscreenBounds,
                    isOnscreen: true
                ),
                .init(
                    id: 240_002,
                    title: "Google 搜索 - Google Chrome",
                    bounds: fullscreenBounds,
                    isOnscreen: true
                )
            ],
            pid: 18405,
            appName: "Google Chrome"
        )

        XCTAssertEqual(mergedEntries.map(\.windowID), ["cg:18405:240001", "cg:18405:240002"])
        XCTAssertEqual(mergedEntries.map(\.cgWindowID), [240_001, 240_002])
        XCTAssertTrue(mergedEntries.allSatisfy { $0.lastConfirmationSource == .privateExactBridge })
    }

    func testRuntimeSnapshotProviderWindowListKeepsSpaceBackedEntriesAfterAXDisappearsWithoutStickyBinding() throws {
        let provider = RuntimeSnapshotProvider()
        let mergedEntries = provider.resolvedStableWindowEntries(
            axWindows: [],
            cgWindows: [
                RuntimeCGWindowEntry(
                    id: 243_747,
                    title: "Recovered Window",
                    bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [11_679]
                )
            ],
            pid: 18405,
            appName: "Google Chrome"
        )

        XCTAssertEqual(mergedEntries.map(\.windowID), ["cg:18405:243747"])
        let entry = try XCTUnwrap(mergedEntries.first)
        XCTAssertEqual(entry.title, "Recovered Window")
        XCTAssertEqual(entry.cgWindowID, 243_747)
        XCTAssertNil(entry.lastConfirmationSource)
        XCTAssertEqual(entry.bindingConfidence, .inferred)
        XCTAssertTrue(entry.bindingAllowedActions.contains(.exposeInSwitcher))
        XCTAssertTrue(entry.bindingAllowedActions.contains(.useForCGActivationFallback))
    }

    func testRuntimeSnapshotProviderStoresCGFirstWindowRecordsAsSingleSourceOfTruth() throws {
        let provider = RuntimeSnapshotProvider()
        let pid: pid_t = 18_405
        let appName = "Google Chrome"
        let exactBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let recoveryBounds = CGRect(x: 0, y: 124, width: 1_728, height: 993)

        let axWindows = [
            RuntimeAXWindowEntry(
                index: 0,
                id: "ax:18405:0",
                title: "Doc A",
                sourceTitle: "Doc A",
                isMinimized: false,
                isFocused: true,
                isMain: true,
                window: AXUIElementCreateApplication(90_101),
                frame: exactBounds
            )
        ]
        let cgWindows = [
            RuntimeCGWindowEntry(
                id: 240_001,
                title: "Doc A",
                bounds: exactBounds,
                isOnscreen: true,
                alpha: 1.0,
                storeType: 1,
                spaceIDs: [11_679]
            ),
            RuntimeCGWindowEntry(
                id: 243_747,
                title: "Recovered Window",
                bounds: recoveryBounds,
                isOnscreen: false,
                alpha: 1.0,
                storeType: 1,
                spaceIDs: [11_680]
            )
        ]

        let entries = provider.resolvedStableWindowEntries(
            axWindows: axWindows,
            cgWindows: cgWindows,
            pid: pid,
            appName: appName
        )

        XCTAssertEqual(entries.map(\.windowID), ["cg:18405:240001", "cg:18405:243747"])

        let state = try XCTUnwrap(provider.windowMappingStateByPID[pid])
        XCTAssertEqual(state.currentAXToCG["ax:18405:0"], 240_001)
        XCTAssertEqual(state.currentCGToAX[240_001], "ax:18405:0")
        XCTAssertEqual(state.validCGWindowIDs, Set<CGWindowID>([240_001, 243_747]))
        XCTAssertEqual(state.lastAXWindowIDs, Set(["ax:18405:0"]))

        let exactRecord = try XCTUnwrap(state.windowRecordsByCGWindowID[240_001])
        XCTAssertEqual(exactRecord.stableWindowID, "cg:18405:240001")
        XCTAssertEqual(exactRecord.lastKnownCGTitle, "Doc A")
        XCTAssertEqual(exactRecord.lastKnownDisplayTitle, "Doc A")
        XCTAssertEqual(exactRecord.currentAXAttachment?.axWindowID, "ax:18405:0")
        XCTAssertEqual(
            exactRecord.currentAXAttachment?.state,
            RuntimeAXWindowState(
                isMinimized: false,
                isFocused: true,
                isMain: true
            )
        )
        XCTAssertFalse(exactRecord.isMinimized)
        XCTAssertTrue(exactRecord.isFocused)
        XCTAssertTrue(exactRecord.isMain)
        XCTAssertEqual(exactRecord.lastExactAXWindowID, "ax:18405:0")
        XCTAssertEqual(exactRecord.spaceRecovery?.spaceIDs, [11_679])
        XCTAssertEqual(exactRecord.lastConfirmationSource, .publicExactMatch)

        let recoveryRecord = try XCTUnwrap(state.windowRecordsByCGWindowID[243_747])
        XCTAssertEqual(recoveryRecord.stableWindowID, "cg:18405:243747")
        XCTAssertEqual(recoveryRecord.lastKnownCGTitle, "Recovered Window")
        XCTAssertEqual(recoveryRecord.lastKnownCGFrame, recoveryBounds)
        XCTAssertNil(recoveryRecord.currentAXAttachment)
        XCTAssertNil(recoveryRecord.lastExactAXWindowID)
        XCTAssertEqual(recoveryRecord.spaceRecovery?.spaceIDs, [11_680])
        XCTAssertNil(recoveryRecord.lastConfirmationSource)
    }

    func testRuntimeSnapshotProviderWindowListHidesCGOnlyEntriesBoundToSpaceOneWithoutAXHandle() {
        let mergedEntries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [],
            cgWindows: [
                .init(
                    id: 243_747,
                    title: "Recovered Window",
                    bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                    isOnscreen: false,
                    spaceIDs: [1]
                )
            ],
            pid: 18405,
            appName: "Google Chrome"
        )

        XCTAssertTrue(mergedEntries.isEmpty)
    }

    func testRuntimeSnapshotProviderWindowListKeepsExactEntriesBoundToSpaceOneWhenAXHandleIsPresent() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let mergedEntries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [
                .init(
                    id: "ax:18405:0",
                    index: 0,
                    title: "Google 搜索 - Google Chrome - test1",
                    bounds: fullscreenBounds
                )
            ],
            cgWindows: [
                .init(
                    id: 240_001,
                    title: "Google 搜索 - Google Chrome - test1",
                    bounds: fullscreenBounds,
                    isOnscreen: false,
                    spaceIDs: [1]
                )
            ],
            pid: 18405,
            appName: "Google Chrome"
        )

        XCTAssertEqual(mergedEntries.map(\.windowID), ["cg:18405:240001"])
        XCTAssertEqual(mergedEntries.first?.lastConfirmationSource, .publicExactMatch)
    }

    func testRuntimeSnapshotProviderWindowListKeepsDistinctCGOnlyEntriesSharingSameSpaceBinding() {
        let provider = RuntimeSnapshotProvider()
        let mergedEntries = provider.resolvedStableWindowEntries(
            axWindows: [],
            cgWindows: [
                RuntimeCGWindowEntry(
                    id: 288_544,
                    title: "Google Chrome",
                    bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [11_679]
                ),
                RuntimeCGWindowEntry(
                    id: 258_323,
                    title: "Google Chrome",
                    bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [11_679]
                )
            ],
            pid: 18405,
            appName: "Google Chrome"
        )

        XCTAssertEqual(mergedEntries.map(\.windowID), ["cg:18405:288544", "cg:18405:258323"])
        XCTAssertEqual(mergedEntries.map(\.cgWindowID), [288_544, 258_323])
        XCTAssertTrue(mergedEntries.allSatisfy { $0.bindingConfidence == .inferred })
        XCTAssertTrue(mergedEntries.allSatisfy {
            $0.bindingAllowedActions.contains(.useForCGActivationFallback)
        })
    }

    func testRuntimeSnapshotProviderWindowListSuppressesCGOnlyEntryCoveredByStickySpaceBinding() {
        let mergedEntries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [],
            cgWindows: [
                .init(
                    id: 288_544,
                    title: "Sticky Window",
                    bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                    isOnscreen: false,
                    spaceIDs: [11_679]
                ),
                .init(
                    id: 258_323,
                    title: "Weak Candidate",
                    bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                    isOnscreen: false,
                    spaceIDs: [11_679]
                )
            ],
            previousMatches: ["ax:18405:sticky": 288_544],
            previousAXWindowIDs: ["ax:18405:sticky"],
            previousCGWindowIDs: [288_544],
            pid: 18405,
            appName: "Google Chrome"
        )

        XCTAssertEqual(mergedEntries.map(\.windowID), ["cg:18405:288544"])
        XCTAssertEqual(mergedEntries.first?.cgWindowID, 288_544)
        XCTAssertEqual(mergedEntries.first?.lastConfirmationSource, .stickyBinding)
    }

    func testRuntimeSnapshotProviderWindowListKeepsUnmatchedAXEntriesWhenSpaceBindingDiffers() {
        let mergedEntries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [],
            cgWindows: [
                .init(
                    id: 288_544,
                    title: "Google Chrome",
                    bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                    isOnscreen: false,
                    spaceIDs: [11_679]
                ),
                .init(
                    id: 258_323,
                    title: "Google Chrome",
                    bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                    isOnscreen: false,
                    spaceIDs: [11_680]
                )
            ],
            pid: 18405,
            appName: "Google Chrome"
        )

        XCTAssertEqual(mergedEntries.map(\.windowID), ["cg:18405:288544", "cg:18405:258323"])
    }

    func testRuntimeSnapshotProviderWindowListKeepsStickyCGEntriesWhenCurrentAXHandleIsMissing() {
        let mergedEntries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [],
            cgWindows: [
                .init(
                    id: 243_747,
                    title: "Recovered Window",
                    bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                    isOnscreen: false
                )
            ],
            previousMatches: ["ax:18405:0": 243_747],
            previousAXWindowIDs: ["ax:18405:0"],
            previousCGWindowIDs: [243_747],
            pid: 18405,
            appName: "Google Chrome"
        )

        XCTAssertEqual(mergedEntries.map(\.windowID), ["cg:18405:243747"])
        XCTAssertEqual(mergedEntries.first?.title, "Recovered Window")
        XCTAssertEqual(mergedEntries.first?.cgWindowID, 243_747)
        XCTAssertEqual(mergedEntries.first?.lastConfirmationSource, .stickyBinding)
    }

    func testRuntimeSnapshotProviderWindowListFiltersFullscreenSiblingArtifactsAroundNoisyWindows() {
        let appName = "Chrome Fixture"
        let normalFrame = CGRect(x: 384, y: 258, width: 960, height: 640)
        let incognitoFrame = CGRect(x: 492, y: 354, width: 960, height: 640)
        let fullscreenFrame = CGRect(x: 0, y: 37, width: 1_728, height: 1_080)
        let fullscreenContentFrame = CGRect(x: 0, y: 158, width: 1_728, height: 959)
        let fullscreenBandFrame = CGRect(x: 0, y: 74, width: 1_728, height: 165)

        let mergedEntries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [
                .init(
                    id: "ax:chrome:normal",
                    index: 0,
                    title: "Chrome Normal Tab",
                    bounds: normalFrame,
                    bridgedCGWindowID: 147_870
                ),
                .init(
                    id: "ax:chrome:incognito",
                    index: 1,
                    title: "Chrome Incognito Tab",
                    bounds: incognitoFrame,
                    bridgedCGWindowID: 147_873
                ),
                .init(
                    id: "ax:chrome:fullscreen-host",
                    index: 2,
                    title: "Chrome Fullscreen Tab",
                    bounds: fullscreenFrame,
                    bridgedCGWindowID: 147_871
                ),
                .init(
                    id: "ax:chrome:second-fullscreen-host",
                    index: 3,
                    title: "Chrome Second Fullscreen Tab",
                    bounds: fullscreenFrame,
                    bridgedCGWindowID: 147_872
                ),
                .init(
                    id: "ax:chrome:fullscreen-content",
                    index: 4,
                    title: "Chrome Fullscreen Tab",
                    bounds: fullscreenContentFrame,
                    bridgedCGWindowID: 147_910
                ),
                .init(
                    id: "ax:chrome:second-fullscreen-content",
                    index: 5,
                    title: "Chrome Second Fullscreen Tab",
                    bounds: fullscreenContentFrame,
                    bridgedCGWindowID: 147_911
                ),
                .init(
                    id: "ax:chrome:desktop-helper",
                    index: 6,
                    title: appName,
                    bounds: fullscreenBandFrame,
                    bridgedCGWindowID: 147_881
                )
            ],
            cgWindows: [
                .init(
                    id: 147_870,
                    title: "Chrome Normal Tab",
                    bounds: normalFrame,
                    isOnscreen: false,
                    spaceIDs: [1]
                ),
                .init(
                    id: 147_873,
                    title: "Chrome Incognito Tab",
                    bounds: incognitoFrame,
                    isOnscreen: false,
                    spaceIDs: [1]
                ),
                .init(
                    id: 147_871,
                    title: "Chrome Fullscreen Tab",
                    bounds: fullscreenFrame,
                    isOnscreen: true,
                    spaceIDs: [7_006]
                ),
                .init(
                    id: 147_872,
                    title: "Chrome Second Fullscreen Tab",
                    bounds: fullscreenFrame,
                    isOnscreen: false,
                    spaceIDs: [7_002]
                ),
                .init(
                    id: 147_881,
                    title: appName,
                    bounds: fullscreenBandFrame,
                    isOnscreen: false,
                    spaceIDs: [1]
                ),
                .init(
                    id: 147_909,
                    title: appName,
                    bounds: fullscreenBandFrame,
                    isOnscreen: true,
                    spaceIDs: [7_002]
                ),
                .init(
                    id: 147_910,
                    title: "Chrome Fullscreen Tab",
                    bounds: fullscreenContentFrame,
                    isOnscreen: true,
                    spaceIDs: [7_006]
                ),
                .init(
                    id: 147_911,
                    title: "Chrome Second Fullscreen Tab",
                    bounds: fullscreenContentFrame,
                    isOnscreen: false,
                    spaceIDs: [1]
                ),
                .init(
                    id: 147_884,
                    title: nil,
                    bounds: CGRect(x: 160, y: 239, width: 1_408, height: 80),
                    isOnscreen: false,
                    spaceIDs: [1]
                )
            ],
            previousMatches: [
                "ax:chrome:normal": 147_870,
                "ax:chrome:fullscreen-host": 147_871,
                "ax:chrome:second-fullscreen-host": 147_872,
                "ax:chrome:incognito": 147_873,
                "ax:chrome:fullscreen-content": 147_910,
                "ax:chrome:second-fullscreen-content": 147_911
            ],
            previousAXWindowIDs: [
                "ax:chrome:normal",
                "ax:chrome:fullscreen-host",
                "ax:chrome:second-fullscreen-host",
                "ax:chrome:incognito",
                "ax:chrome:fullscreen-content",
                "ax:chrome:second-fullscreen-content"
            ],
            previousCGWindowIDs: [147_870, 147_871, 147_872, 147_873, 147_910, 147_911],
            pid: 20_596,
            appName: appName
        )

        XCTAssertEqual(
            mergedEntries.map(\.title),
            [
                "Chrome Fullscreen Tab",
                "Chrome Normal Tab",
                "Chrome Incognito Tab",
                "Chrome Second Fullscreen Tab"
            ]
        )
        XCTAssertEqual(
            mergedEntries.compactMap(\.cgWindowID),
            [147_910, 147_870, 147_873, 147_911]
        )
        XCTAssertTrue(
            mergedEntries.filter { $0.title.contains("Fullscreen") }.allSatisfy {
                $0.hasActivationHandle
            }
        )
        XCTAssertFalse(mergedEntries.contains { $0.title == appName })
    }

    func testRuntimeSnapshotProviderWindowListOrdersOnscreenWindowsByCGZOrderInFullscreenTopology() {
        let appName = "Chrome Fixture"
        let normalFrame = CGRect(x: 384, y: 258, width: 960, height: 640)
        let incognitoFrame = CGRect(x: 492, y: 354, width: 960, height: 640)
        let fullscreenFrame = CGRect(x: 0, y: 37, width: 1_728, height: 1_080)

        let mergedEntries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [
                .init(
                    id: "ax:chrome:normal",
                    index: 0,
                    title: "Chrome Normal Tab",
                    bounds: normalFrame,
                    bridgedCGWindowID: 151_139
                ),
                .init(
                    id: "ax:chrome:incognito",
                    index: 1,
                    title: "Chrome Incognito Tab",
                    bounds: incognitoFrame,
                    bridgedCGWindowID: 151_142
                ),
                .init(
                    id: "ax:chrome:fullscreen",
                    index: 2,
                    title: "Chrome Fullscreen Tab",
                    bounds: fullscreenFrame,
                    bridgedCGWindowID: 151_178
                )
            ],
            cgWindows: [
                .init(
                    id: 151_142,
                    title: "Chrome Incognito Tab",
                    bounds: incognitoFrame,
                    isOnscreen: true,
                    spaceIDs: [1]
                ),
                .init(
                    id: 151_139,
                    title: "Chrome Normal Tab",
                    bounds: normalFrame,
                    isOnscreen: true,
                    spaceIDs: [1]
                ),
                .init(
                    id: 151_178,
                    title: "Chrome Fullscreen Tab",
                    bounds: fullscreenFrame,
                    isOnscreen: false,
                    spaceIDs: [7_177]
                )
            ],
            pid: 64_785,
            appName: appName
        )

        XCTAssertEqual(
            mergedEntries.compactMap(\.cgWindowID),
            [151_142, 151_139, 151_178]
        )
        XCTAssertEqual(mergedEntries.first?.title, "Chrome Incognito Tab")
    }

    func testRuntimeSnapshotProviderWindowListKeepsDesktopWindowsBeforeOffscreenFullscreenFallback() {
        let appName = "Chrome Fixture"
        let normalFrame = CGRect(x: 384, y: 258, width: 960, height: 640)
        let incognitoFrame = CGRect(x: 492, y: 354, width: 960, height: 640)
        let fullscreenContentFrame = CGRect(x: 0, y: 195, width: 1_728, height: 922)

        let mergedEntries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [
                .init(
                    id: "ax:chrome:normal",
                    index: 0,
                    title: "Chrome Normal Tab",
                    bounds: normalFrame,
                    bridgedCGWindowID: 151_401
                ),
                .init(
                    id: "ax:chrome:incognito",
                    index: 1,
                    title: "Chrome Incognito Tab",
                    bounds: incognitoFrame,
                    bridgedCGWindowID: 151_402
                ),
                .init(
                    id: "ax:chrome:fullscreen-content",
                    index: 2,
                    title: "Chrome Fullscreen Tab",
                    bounds: fullscreenContentFrame,
                    bridgedCGWindowID: 151_403
                ),
                .init(
                    id: "ax:chrome:second-fullscreen-content",
                    index: 3,
                    title: "Chrome Second Fullscreen Tab",
                    bounds: fullscreenContentFrame,
                    bridgedCGWindowID: 151_404
                )
            ],
            cgWindows: [
                .init(
                    id: 151_403,
                    title: "Chrome Fullscreen Tab",
                    bounds: fullscreenContentFrame,
                    isOnscreen: true,
                    spaceIDs: [7_006]
                ),
                .init(
                    id: 151_404,
                    title: "Chrome Second Fullscreen Tab",
                    bounds: fullscreenContentFrame,
                    isOnscreen: false,
                    spaceIDs: [7_002]
                ),
                .init(
                    id: 151_401,
                    title: "Chrome Normal Tab",
                    bounds: normalFrame,
                    isOnscreen: false,
                    spaceIDs: [1]
                ),
                .init(
                    id: 151_402,
                    title: "Chrome Incognito Tab",
                    bounds: incognitoFrame,
                    isOnscreen: false,
                    spaceIDs: [1]
                )
            ],
            pid: 67_097,
            appName: appName
        )

        XCTAssertEqual(
            mergedEntries.map(\.title),
            [
                "Chrome Fullscreen Tab",
                "Chrome Normal Tab",
                "Chrome Incognito Tab",
                "Chrome Second Fullscreen Tab"
            ]
        )
        XCTAssertEqual(
            mergedEntries.compactMap(\.cgWindowID),
            [151_403, 151_401, 151_402, 151_404]
        )
    }

    func testRuntimeSnapshotProviderWindowListKeepsDesktopFullscreenSiblingsBehindNormalSurfaces() {
        let appName = "Chrome Fixture"
        let normalFrame = CGRect(x: 384, y: 258, width: 960, height: 640)
        let incognitoFrame = CGRect(x: 492, y: 354, width: 960, height: 640)
        let fullscreenHostFrame = CGRect(x: 0, y: 37, width: 1_728, height: 1_080)
        let fullscreenContentFrame = CGRect(x: 0, y: 195, width: 1_728, height: 922)

        let mergedEntries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [
                .init(
                    id: "ax:chrome:normal",
                    index: 0,
                    title: "Chrome Normal Tab",
                    bounds: normalFrame,
                    bridgedCGWindowID: 151_321
                ),
                .init(
                    id: "ax:chrome:incognito",
                    index: 1,
                    title: "Chrome Incognito Tab",
                    bounds: incognitoFrame,
                    bridgedCGWindowID: 151_324
                ),
                .init(
                    id: "ax:chrome:second-fullscreen-content",
                    index: 2,
                    title: "Chrome Second Fullscreen Tab",
                    bounds: fullscreenContentFrame,
                    bridgedCGWindowID: 151_332
                ),
                .init(
                    id: "ax:chrome:fullscreen-content",
                    index: 3,
                    title: "Chrome Fullscreen Tab",
                    bounds: fullscreenContentFrame,
                    bridgedCGWindowID: 151_360
                )
            ],
            cgWindows: [
                .init(
                    id: 151_332,
                    title: "Chrome Second Fullscreen Tab",
                    bounds: fullscreenContentFrame,
                    isOnscreen: true,
                    spaceIDs: [1]
                ),
                .init(
                    id: 151_321,
                    title: "Chrome Normal Tab",
                    bounds: normalFrame,
                    isOnscreen: true,
                    spaceIDs: [1]
                ),
                .init(
                    id: 151_324,
                    title: "Chrome Incognito Tab",
                    bounds: incognitoFrame,
                    isOnscreen: true,
                    spaceIDs: [1]
                ),
                .init(
                    id: 151_323,
                    title: "Chrome Second Fullscreen Tab",
                    bounds: fullscreenHostFrame,
                    isOnscreen: false,
                    spaceIDs: [7_185]
                ),
                .init(
                    id: 151_360,
                    title: "Chrome Fullscreen Tab",
                    bounds: fullscreenContentFrame,
                    isOnscreen: false,
                    spaceIDs: [7_189]
                )
            ],
            pid: 67_097,
            appName: appName
        )

        XCTAssertEqual(
            mergedEntries.compactMap(\.cgWindowID),
            [151_321, 151_324, 151_332, 151_360]
        )
        XCTAssertEqual(mergedEntries.first?.title, "Chrome Normal Tab")
    }

    func testRuntimeSnapshotProviderWindowListFiltersChromeFindOverlayAXWindow() {
        let appName = "Google Chrome"
        let browserFrame = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let findOverlayFrame = CGRect(x: 1_140, y: 110, width: 403, height: 84)

        let mergedEntries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [
                .init(
                    id: "ax:chrome:browser",
                    index: 0,
                    title: "Docs - Google Chrome - Profile",
                    bounds: browserFrame,
                    bridgedCGWindowID: 151_421
                ),
                .init(
                    id: "ax:chrome:find-overlay",
                    index: 1,
                    title: "Find in page",
                    bounds: findOverlayFrame,
                    bridgedCGWindowID: 151_422
                )
            ],
            cgWindows: [
                .init(
                    id: 151_422,
                    title: nil,
                    bounds: findOverlayFrame,
                    isOnscreen: true,
                    spaceIDs: [1]
                ),
                .init(
                    id: 151_421,
                    title: "Docs",
                    bounds: browserFrame,
                    isOnscreen: true,
                    spaceIDs: [1]
                )
            ],
            pid: 67_097,
            appName: appName
        )

        XCTAssertEqual(mergedEntries.compactMap(\.cgWindowID), [151_421])
        XCTAssertEqual(mergedEntries.first?.title, "Docs - Google Chrome - Profile")
    }

    func testRuntimeSnapshotProviderWindowListKeepsStickyCGEntriesBoundToSpaceOneDuringTransientAXRebuild() {
        let provider = RuntimeSnapshotProvider()
        let pid: pid_t = 18_405
        let appName = "Google Chrome"
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let cgWindows = [
            RuntimeCGWindowEntry(
                id: 243_747,
                title: "Recovered Window",
                bounds: fullscreenBounds,
                isOnscreen: false,
                alpha: 1.0,
                storeType: 1,
                spaceIDs: [1]
            )
        ]
        let initialAXWindows = [
            RuntimeAXWindowEntry(
                index: 0,
                id: "ax:18405:0",
                title: "Recovered Window",
                sourceTitle: "Recovered Window",
                isMinimized: false,
                window: AXUIElementCreateApplication(90_001),
                frame: fullscreenBounds
            )
        ]

        let initialEntries = provider.resolvedStableWindowEntries(
            axWindows: initialAXWindows,
            cgWindows: cgWindows,
            pid: pid,
            appName: appName
        )
        XCTAssertEqual(initialEntries.map(\.windowID), ["cg:18405:243747"])
        XCTAssertEqual(initialEntries.first?.lastConfirmationSource, .publicExactMatch)
        XCTAssertFalse(provider.isLikelyTransientAXRebuild(for: pid))

        let transientMissingAXEntries = provider.resolvedStableWindowEntries(
            axWindows: [],
            cgWindows: cgWindows,
            pid: pid,
            appName: appName
        )

        XCTAssertEqual(transientMissingAXEntries.map(\.windowID), ["cg:18405:243747"])
        XCTAssertTrue(transientMissingAXEntries.first?.hasStickyBinding == true)
        XCTAssertNotNil(transientMissingAXEntries.first?.lastConfirmationSource)
        XCTAssertTrue(provider.isLikelyTransientAXRebuild(for: pid))
    }

    func testRuntimeSnapshotProviderWindowListKeepsMultipleStickySpaceOneEntriesWhenAXReturnsSubsetFromFullscreenSpace() {
        let provider = RuntimeSnapshotProvider()
        let pid: pid_t = 18_405
        let appName = "Google Chrome"
        let desktopBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let fullscreenBoundsA = CGRect(x: 0, y: 124, width: 1_728, height: 993)
        let fullscreenBoundsB = CGRect(x: 0, y: 158, width: 1_728, height: 959)

        func title(for index: Int) -> String {
            "Chrome Window \(index)"
        }

        func bounds(for index: Int) -> CGRect {
            switch index {
            case 18:
                return fullscreenBoundsA
            case 19:
                return fullscreenBoundsB
            default:
                return desktopBounds
            }
        }

        func spaceIDs(for index: Int) -> [Int] {
            switch index {
            case 18:
                return [6_380]
            case 19:
                return [6_371]
            default:
                return [1]
            }
        }

        func cgWindow(for index: Int, isOnscreen: Bool) -> RuntimeCGWindowEntry {
            RuntimeCGWindowEntry(
                id: CGWindowID(240_000 + index),
                title: title(for: index),
                bounds: bounds(for: index),
                isOnscreen: isOnscreen,
                alpha: 1.0,
                storeType: 1,
                spaceIDs: spaceIDs(for: index)
            )
        }

        func axWindow(for index: Int) -> RuntimeAXWindowEntry {
            RuntimeAXWindowEntry(
                index: index,
                id: "ax:18405:\(index)",
                title: title(for: index),
                sourceTitle: title(for: index),
                isMinimized: false,
                window: AXUIElementCreateApplication(pid + pid_t(index) + 1),
                frame: bounds(for: index)
            )
        }

        let initialEntries = provider.resolvedStableWindowEntries(
            axWindows: (0..<20).map(axWindow),
            cgWindows: (0..<20).map { cgWindow(for: $0, isOnscreen: true) },
            pid: pid,
            appName: appName
        )
        XCTAssertEqual(initialEntries.count, 20)

        let fullscreenSpaceEntries = provider.resolvedStableWindowEntries(
            axWindows: [17, 18, 19].map(axWindow),
            cgWindows: (0..<20).map { cgWindow(for: $0, isOnscreen: false) },
            pid: pid,
            appName: appName
        )

        XCTAssertEqual(fullscreenSpaceEntries.count, 20)
        XCTAssertEqual(
            Set(fullscreenSpaceEntries.compactMap(\.cgWindowID)),
            Set((0..<20).map { CGWindowID(240_000 + $0) })
        )
    }

    func testRuntimeSnapshotProviderWindowListHidesStickyCGEntriesBoundToSpaceOneAfterAXRebuildGraceRetriesExhausted() {
        let provider = RuntimeSnapshotProvider()
        let pid: pid_t = 18_405
        let appName = "Google Chrome"
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let cgWindows = [
            RuntimeCGWindowEntry(
                id: 243_747,
                title: "Recovered Window",
                bounds: fullscreenBounds,
                isOnscreen: false,
                alpha: 1.0,
                storeType: 1,
                spaceIDs: [1]
            )
        ]
        let initialAXWindows = [
            RuntimeAXWindowEntry(
                index: 0,
                id: "ax:18405:0",
                title: "Recovered Window",
                sourceTitle: "Recovered Window",
                isMinimized: false,
                window: AXUIElementCreateApplication(90_002),
                frame: fullscreenBounds
            )
        ]

        _ = provider.resolvedStableWindowEntries(
            axWindows: initialAXWindows,
            cgWindows: cgWindows,
            pid: pid,
            appName: appName
        )
        XCTAssertFalse(provider.isLikelyTransientAXRebuild(for: pid))

        for _ in 0..<3 {
            let retryEntries = provider.resolvedStableWindowEntries(
                axWindows: [],
                cgWindows: cgWindows,
                pid: pid,
                appName: appName
            )
            XCTAssertEqual(retryEntries.map(\.windowID), ["cg:18405:243747"])
            XCTAssertTrue(provider.isLikelyTransientAXRebuild(for: pid))
        }

        let exhaustedEntries = provider.resolvedStableWindowEntries(
            axWindows: [],
            cgWindows: cgWindows,
            pid: pid,
            appName: appName
        )
        XCTAssertTrue(exhaustedEntries.isEmpty)
        XCTAssertFalse(provider.isLikelyTransientAXRebuild(for: pid))
    }

    func testRuntimeSnapshotProviderPartialRemoteAXScanDoesNotConsumeMissingAXGrace() {
        let provider = RuntimeSnapshotProvider()
        let pid: pid_t = 18_405
        let appName = "Google Chrome"
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let cgWindows = [
            RuntimeCGWindowEntry(
                id: 243_747,
                title: "Recovered Window",
                bounds: fullscreenBounds,
                isOnscreen: false,
                alpha: 1.0,
                storeType: 1,
                spaceIDs: [1]
            )
        ]
        let initialAXWindows = [
            RuntimeAXWindowEntry(
                index: 0,
                id: "ax:18405:0",
                title: "Recovered Window",
                sourceTitle: "Recovered Window",
                isMinimized: false,
                window: AXUIElementCreateApplication(90_003),
                frame: fullscreenBounds
            )
        ]

        _ = provider.resolvedStableWindowEntries(
            axWindows: initialAXWindows,
            cgWindows: cgWindows,
            pid: pid,
            appName: appName
        )

        for _ in 0..<5 {
            let partialEntries = provider.resolvedStableWindowEntries(
                axWindows: [],
                cgWindows: cgWindows,
                pid: pid,
                appName: appName,
                remoteScanCompleteness: .partialTimedOut(scanned: 24, maximum: 1_000)
            )
            XCTAssertEqual(partialEntries.map(\.windowID), ["cg:18405:243747"])
            XCTAssertFalse(provider.isLikelyTransientAXRebuild(for: pid))
        }

        let firstAuthoritativeMissingEntries = provider.resolvedStableWindowEntries(
            axWindows: [],
            cgWindows: cgWindows,
            pid: pid,
            appName: appName,
            remoteScanCompleteness: .complete(scanned: 1_000)
        )
        XCTAssertEqual(firstAuthoritativeMissingEntries.map(\.windowID), ["cg:18405:243747"])
        XCTAssertTrue(provider.isLikelyTransientAXRebuild(for: pid))
    }

    func testRuntimeSnapshotProviderWindowListKeepsStickyMatchesWhenAXTitlesChange() {
        let provider = RuntimeSnapshotProvider()
        let pid: pid_t = 18405
        let appName = "Google Chrome"
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)

        let firstAXWindows = [
            RuntimeAXWindowEntry(
                index: 0,
                id: "ax:18405:0",
                title: "Doc A",
                sourceTitle: "Doc A",
                isMinimized: false,
                window: AXUIElementCreateApplication(90_001),
                frame: fullscreenBounds
            ),
            RuntimeAXWindowEntry(
                index: 1,
                id: "ax:18405:1",
                title: "Doc B",
                sourceTitle: "Doc B",
                isMinimized: false,
                window: AXUIElementCreateApplication(90_002),
                frame: fullscreenBounds
            )
        ]
        let firstCGWindows = [
            RuntimeCGWindowEntry(
                id: 240_001,
                title: "Doc A",
                bounds: fullscreenBounds,
                isOnscreen: true,
                alpha: 1.0,
                storeType: 1
            ),
            RuntimeCGWindowEntry(
                id: 240_002,
                title: "Doc B",
                bounds: fullscreenBounds,
                isOnscreen: true,
                alpha: 1.0,
                storeType: 1
            )
        ]

        let firstEntries = provider.resolvedStableWindowEntries(
            axWindows: firstAXWindows,
            cgWindows: firstCGWindows,
            pid: pid,
            appName: appName
        )
        XCTAssertEqual(Set(firstEntries.compactMap(\.cgWindowID)), Set<CGWindowID>([240_001, 240_002]))

        let secondAXWindows = [
            RuntimeAXWindowEntry(
                index: 0,
                id: "ax:18405:0",
                title: "Doc A (Updated)",
                sourceTitle: "Doc A (Updated)",
                isMinimized: false,
                window: firstAXWindows[0].window,
                frame: fullscreenBounds
            ),
            RuntimeAXWindowEntry(
                index: 1,
                id: "ax:18405:1",
                title: "Doc B (Updated)",
                sourceTitle: "Doc B (Updated)",
                isMinimized: false,
                window: firstAXWindows[1].window,
                frame: fullscreenBounds
            )
        ]
        let secondCGWindows = [
            RuntimeCGWindowEntry(
                id: 240_001,
                title: nil,
                bounds: fullscreenBounds,
                isOnscreen: true,
                alpha: 1.0,
                storeType: 1
            ),
            RuntimeCGWindowEntry(
                id: 240_002,
                title: nil,
                bounds: fullscreenBounds,
                isOnscreen: true,
                alpha: 1.0,
                storeType: 1
            )
        ]

        let secondEntries = provider.resolvedStableWindowEntries(
            axWindows: secondAXWindows,
            cgWindows: secondCGWindows,
            pid: pid,
            appName: appName
        )

        let secondEntriesByCGWindowID = Dictionary(
            uniqueKeysWithValues: secondEntries.compactMap { entry -> (CGWindowID, RuntimeSnapshotProvider.WindowListEntry)? in
                guard let cgWindowID = entry.cgWindowID else { return nil }
                return (cgWindowID, entry)
            }
        )
        XCTAssertEqual(secondEntriesByCGWindowID[240_001]?.title, "Doc A (Updated)")
        XCTAssertEqual(secondEntriesByCGWindowID[240_002]?.title, "Doc B (Updated)")
    }

    func testRuntimeSnapshotProviderAXWindowTitleFallsBackToAppNameWhenSourceTitleMissing() {
        let fallbackTitle = RuntimeSnapshotProvider.resolvedAXWindowTitleForTesting(
            sourceTitle: nil,
            matchedCGTitle: nil,
            appName: "Google Chrome",
            fallbackIndex: 1
        )
        XCTAssertEqual(fallbackTitle, "Google Chrome")

        let explicitTitle = RuntimeSnapshotProvider.resolvedAXWindowTitleForTesting(
            sourceTitle: "百度一下，你就知道",
            matchedCGTitle: "From CG",
            appName: "Google Chrome",
            fallbackIndex: 1
        )
        XCTAssertEqual(explicitTitle, "百度一下，你就知道")
    }

    func testRuntimeSnapshotProviderAXWindowTitleUsesMatchedCGTitleWhenAXTitleMissing() {
        let title = RuntimeSnapshotProvider.resolvedAXWindowTitleForTesting(
            sourceTitle: nil,
            matchedCGTitle: "百度一下，你就知道 - Google Chrome - test2",
            appName: "Google Chrome",
            fallbackIndex: 0
        )
        XCTAssertEqual(title, "百度一下，你就知道 - Google Chrome - test2")
    }

    func testRuntimeSnapshotProviderAXWindowTitleTreatsAppNameSourceAsFallbackWhenCGTitleExists() {
        let title = RuntimeSnapshotProvider.resolvedAXWindowTitleForTesting(
            sourceTitle: "Google Chrome",
            matchedCGTitle: "百度一下，你就知道 - Google Chrome - test2",
            appName: "Google Chrome",
            fallbackIndex: 0
        )
        XCTAssertEqual(title, "百度一下，你就知道 - Google Chrome - test2")
    }

    func testRuntimeSnapshotProviderAXWindowTitleTreatsAppNameSourceAsFallbackWhenRefreshedAXTitleExists() {
        let title = RuntimeSnapshotProvider.resolvedAXWindowTitleForTesting(
            sourceTitle: "Google Chrome",
            matchedCGTitle: nil,
            appName: "Google Chrome",
            fallbackIndex: 2,
            refreshedAXTitle: "百度一下，你就知道 - Google Chrome - test3"
        )
        XCTAssertEqual(title, "百度一下，你就知道 - Google Chrome - test3")
    }

    func testRuntimeSnapshotProviderAXWindowTitleUsesRefreshedAXTitleWhenPrimaryTitleMissing() {
        let title = RuntimeSnapshotProvider.resolvedAXWindowTitleForTesting(
            sourceTitle: nil,
            matchedCGTitle: nil,
            appName: "Google Chrome",
            fallbackIndex: 2,
            refreshedAXTitle: "百度一下，你就知道 - Google Chrome - test2"
        )
        XCTAssertEqual(title, "百度一下，你就知道 - Google Chrome - test2")
    }

    func testRuntimeFullRepairProjectionAssemblerPreservesMinimizedSeedsAndFallbackGroupIDs() {
        let currentApp = NSRunningApplication.current
        let payload = RuntimeFullRepairProjectionAssembler.payload(
            fromCurrentAppWindowProjectionInputs: [
                RuntimeCurrentAppWindowProjectionAssemblyInput(
                    appID: "pid:41",
                    displayName: "Zulu",
                    groupID: "z",
                    summaryLastActiveAt: -5,
                    candidateLastActiveAt: 1_995,
                    pid: 41,
                    runningApp: currentApp,
                    windowSeeds: [
                        RuntimeAppWindowProjectionSeed(
                            windowID: "z-1",
                            title: "Zulu Window",
                            isMinimized: true,
                            lastActiveAt: 2_000,
                            ownerPID: 41,
                            cgWindowID: 41
                        )
                    ]
                ),
                RuntimeCurrentAppWindowProjectionAssemblyInput(
                    appID: "pid:42",
                    displayName: "Alpha",
                    groupID: "a",
                    summaryLastActiveAt: -5,
                    candidateLastActiveAt: 1_995,
                    pid: 42,
                    runningApp: currentApp,
                    windowSeeds: [
                        RuntimeAppWindowProjectionSeed(
                            windowID: "a-1",
                            title: "Alpha Window",
                            isMinimized: true,
                            lastActiveAt: 2_000,
                            ownerPID: 42,
                            cgWindowID: 42
                        )
                    ]
                )
            ]
        )

        XCTAssertEqual(payload.apps.map(\.id), ["pid:42", "pid:41"])
        XCTAssertEqual(payload.apps.map(\.groupID), ["a", "z"])
        XCTAssertTrue(payload.apps.allSatisfy { $0.windows.first?.isMinimized == true })
        XCTAssertEqual(payload.contextsByID["pid:42"]?.windowsByID["a-1"]?.cgWindowID, 42)
        XCTAssertEqual(payload.contextsByID["pid:41"]?.windowsByID["z-1"]?.ownerPID, 41)
    }

    func testRuntimeWindowPreviewProviderGuessesDarkLightAndUnknownTitleBars() {
        let darkImage = makeSolidPreviewCGImage(color: .black)
        let lightImage = makeSolidPreviewCGImage(color: .white)
        let noisyImage = makeStripedPreviewCGImage()

        XCTAssertEqual(
            RuntimeWindowPreviewProvider.guessTitleBarStyleForTesting(from: darkImage),
            .dark
        )
        XCTAssertEqual(
            RuntimeWindowPreviewProvider.guessTitleBarStyleForTesting(from: lightImage),
            .light
        )
        XCTAssertNil(RuntimeWindowPreviewProvider.guessTitleBarStyleForTesting(from: noisyImage))
    }

    func testRuntimeWindowPreviewProviderCandidateWindowIDsPreferOnlyExplicitWindowID() {
        let candidateIDs = RuntimeWindowPreviewProvider.candidateWindowIDsForTesting(
            preferredWindowID: 3,
            preferredTitle: "Inbox",
            liveWindows: [
                .init(id: 1, title: "Inbox"),
                .init(id: 2, title: "inbox"),
                .init(id: 3, title: "Draft"),
                .init(id: 4, title: nil)
            ]
        )

        XCTAssertEqual(candidateIDs, [3])
    }

    func testRuntimeWindowPreviewProviderCandidateWindowIDsUseUniqueExactTitleMatches() {
        let candidateIDs = RuntimeWindowPreviewProvider.candidateWindowIDsForTesting(
            preferredWindowID: nil,
            preferredTitle: "Inbox",
            liveWindows: [
                .init(id: 1, title: "Inbox"),
                .init(id: 2, title: "inbox"),
                .init(id: 3, title: "Draft")
            ]
        )

        XCTAssertEqual(candidateIDs, [1])
    }

    func testRuntimeWindowPreviewProviderCandidateWindowIDsAvoidArbitraryFallbackAcrossMultipleWindows() {
        let candidateIDs = RuntimeWindowPreviewProvider.candidateWindowIDsForTesting(
            preferredWindowID: nil,
            preferredTitle: "Archive",
            liveWindows: [
                .init(id: 1, title: "Inbox"),
                .init(id: 2, title: "Draft")
            ]
        )

        XCTAssertTrue(candidateIDs.isEmpty)
    }

    func testRuntimeWindowPreviewProviderOwnerPIDPathKeepsPreferredWindowFirst() {
        let preferredWindowID: CGWindowID = 777
        let candidateIDs = RuntimeWindowPreviewProvider.candidateWindowIDsForTesting(
            preferredWindowID: preferredWindowID,
            ownerPID: ProcessInfo.processInfo.processIdentifier,
            preferredTitle: "unlikely-title-\(UUID().uuidString)"
        )

        XCTAssertEqual(candidateIDs.first, preferredWindowID)
    }

    func testRuntimeWindowPreviewProviderAllowsOffScreenShareableLookupForKnownWindowIDs() {
        XCTAssertFalse(
            RuntimeWindowPreviewProvider.shareableContentOnScreenOnlyForTesting(
                preferredWindowID: 243747
            )
        )
        XCTAssertTrue(
            RuntimeWindowPreviewProvider.shareableContentOnScreenOnlyForTesting(
                preferredWindowID: nil
            )
        )
    }

    func testRuntimeWindowPreviewProviderBatchShareableLookupUsesInclusiveModeForKnownWindowIDs() {
        XCTAssertTrue(
            RuntimeWindowPreviewProvider.shareableContentOnScreenOnlyForTesting(
                preferredWindowIDs: [nil, nil]
            )
        )
        XCTAssertFalse(
            RuntimeWindowPreviewProvider.shareableContentOnScreenOnlyForTesting(
                preferredWindowIDs: [nil, 243747, nil]
            )
        )
    }

    func testRuntimeWindowPreviewProviderBridgeClassifiesLateCallbacksAfterTimeout() {
        XCTAssertEqual(
            RuntimeWindowPreviewProvider.screenCaptureBridgeLateCallbackFailureForTesting(),
            .callbackReturnedAfterTimeout
        )
    }

    func testRuntimeWindowPreviewProviderBridgeKeepsNearDeadlineCompletion() {
        XCTAssertTrue(
            RuntimeWindowPreviewProvider.screenCaptureBridgeUsesCompletedValueBeforeTimeoutMarkForTesting()
        )
    }

    func testRuntimeWindowPreviewProviderOutcomesClassifyPermissionDenied() {
        let previousOverride = ScreenCapturePermissionChecker.hasPermissionOverrideForTesting
        ScreenCapturePermissionChecker.hasPermissionOverrideForTesting = { false }
        defer {
            ScreenCapturePermissionChecker.hasPermissionOverrideForTesting = previousOverride
        }

        let outcomes = RuntimeWindowPreviewProvider.captureWindowPreviewOutcomes([
            RuntimeWindowPreviewProvider.CaptureRequest(
                preferredWindowID: 243_747,
                ownerPID: ProcessInfo.processInfo.processIdentifier,
                preferredTitle: "Inbox",
                inferTitleBarStyle: false
            )
        ])

        XCTAssertEqual(outcomes.count, 1)
        XCTAssertNil(outcomes[0].result)
        XCTAssertEqual(outcomes[0].failureReason, .permissionDenied)
    }

    func testRuntimeWindowPreviewProviderOutcomesClassifyMissingWindowBeforeShareableLookup() {
        let previousOverride = ScreenCapturePermissionChecker.hasPermissionOverrideForTesting
        ScreenCapturePermissionChecker.hasPermissionOverrideForTesting = { true }
        defer {
            ScreenCapturePermissionChecker.hasPermissionOverrideForTesting = previousOverride
        }

        let outcomes = RuntimeWindowPreviewProvider.captureWindowPreviewOutcomes([
            RuntimeWindowPreviewProvider.CaptureRequest(
                preferredWindowID: nil,
                ownerPID: 987_654,
                preferredTitle: "Missing Preview Window",
                inferTitleBarStyle: false
            )
        ])

        XCTAssertEqual(outcomes.count, 1)
        XCTAssertNil(outcomes[0].result)
        XCTAssertEqual(outcomes[0].failureReason, .windowNotFound)
    }

    func testRuntimeWindowPreviewProviderUsesNamedCaptureConcurrencyPolicy() {
        let policy = RuntimeWindowPreviewProvider.captureConcurrencyPolicyForTesting()

        XCTAssertEqual(policy, .default)
        XCTAssertEqual(policy.maxConcurrentCaptures, 4)
        XCTAssertGreaterThan(policy.maxConcurrentCaptures, 0)
        XCTAssertEqual(
            RuntimeWindowPreviewProvider.captureWorkerCountForTesting(requestCount: 1),
            1
        )
        XCTAssertEqual(
            RuntimeWindowPreviewProvider.captureWorkerCountForTesting(requestCount: 12),
            policy.maxConcurrentCaptures
        )
        XCTAssertEqual(
            RuntimeWindowPreviewProvider.captureWorkerCountForTesting(
                requestCount: 12,
                concurrencyPolicy: RuntimeWindowPreviewProvider.CaptureConcurrencyPolicy(
                    maxConcurrentCaptures: 2
                )
            ),
            2
        )
    }

    func testRuntimeWindowPreviewProviderScaledPreviewSizeAndImageDownscaleBehavior() {
        let largeSize = RuntimeWindowPreviewProvider.scaledPreviewSizeForTesting(
            sourceWidth: 2_400,
            sourceHeight: 1_200
        )
        XCTAssertEqual(largeSize.width, 1_200)
        XCTAssertEqual(largeSize.height, 600)

        let unchangedSize = RuntimeWindowPreviewProvider.scaledPreviewSizeForTesting(
            sourceWidth: 800,
            sourceHeight: 400
        )
        XCTAssertEqual(unchangedSize.width, 800)
        XCTAssertEqual(unchangedSize.height, 400)

        let minimalSize = RuntimeWindowPreviewProvider.scaledPreviewSizeForTesting(
            sourceWidth: 0.2,
            sourceHeight: 0.2
        )
        XCTAssertEqual(minimalSize.width, 1)
        XCTAssertEqual(minimalSize.height, 1)

        let largeImage = makeSolidPreviewCGImage(
            color: .systemTeal,
            size: CGSize(width: 2_000, height: 1_000)
        )
        let scaledImage = RuntimeWindowPreviewProvider.scaledPreviewImageIfNeededForTesting(largeImage)
        XCTAssertEqual(scaledImage?.width, 1_200)
        XCTAssertEqual(scaledImage?.height, 600)

        let smallImage = makeSolidPreviewCGImage(
            color: .systemOrange,
            size: CGSize(width: 600, height: 300)
        )
        let unchangedImage = RuntimeWindowPreviewProvider.scaledPreviewImageIfNeededForTesting(smallImage)
        XCTAssertEqual(unchangedImage?.width, 600)
        XCTAssertEqual(unchangedImage?.height, 300)
    }

    func testRuntimeAppIdentityGroupIDMappingCoversFallbackAndBundleShapes() {
        XCTAssertEqual(
            RuntimeAppIdentity.groupID(
                for: nil,
                fallbackName: "Notes"
            ),
            "n"
        )
        XCTAssertEqual(
            RuntimeAppIdentity.groupID(
                for: "com.example.mail",
                fallbackName: "Mail"
            ),
            "example"
        )
        XCTAssertEqual(
            RuntimeAppIdentity.groupID(
                for: "singleton",
                fallbackName: "Single"
            ),
            "singleton"
        )
        XCTAssertEqual(
            RuntimeAppIdentity.groupID(
                for: "",
                fallbackName: "Empty"
            ),
            "apps"
        )
    }

    func testRuntimeSnapshotProviderResolveCGWindowAssignmentsUsesGeometryWithDuplicateTitles() {
        let axWindows: [RuntimeSnapshotProvider.AXWindowEntryForTesting] = [
            .init(id: "ax:100:0", index: 0, title: "Document", bounds: CGRect(x: 10, y: 10, width: 600, height: 420)),
            .init(id: "ax:100:1", index: 1, title: "Document", bounds: CGRect(x: 640, y: 10, width: 600, height: 420))
        ]
        let cgWindows: [RuntimeSnapshotProvider.CGWindowEntryForTesting] = [
            .init(
                id: 22,
                title: "Document",
                bounds: CGRect(x: 640, y: 14, width: 600, height: 418)
            ),
            .init(
                id: 11,
                title: "Document",
                bounds: CGRect(x: 8, y: 8, width: 602, height: 420)
            )
        ]

        let assignments = RuntimeSnapshotProvider.resolveCGWindowAssignmentsForTesting(
            axWindows: axWindows,
            cgWindows: cgWindows
        )

        XCTAssertEqual(assignments["ax:100:0"], 11)
        XCTAssertEqual(assignments["ax:100:1"], 22)
    }

    func testRuntimeSnapshotProviderResolveCGWindowAssignmentsRequiresTitleHitAndSkipsAmbiguousMatches() {
        let axWindows: [RuntimeSnapshotProvider.AXWindowEntryForTesting] = [
            .init(id: "ax:200:2", index: 2, bounds: CGRect(x: 100, y: 100, width: 800, height: 500)),
            .init(id: "ax:200:0", index: 0, bounds: nil)
        ]
        let cgWindows: [RuntimeSnapshotProvider.CGWindowEntryForTesting] = [
            .init(id: 1, title: nil, bounds: CGRect(x: 100, y: 100, width: 800, height: 500)),
            .init(id: 2, title: nil, bounds: CGRect(x: 100, y: 100, width: 800, height: 500)),
            .init(id: 3, title: nil, bounds: CGRect(x: 100, y: 100, width: 800, height: 500)),
            .init(id: 4, title: nil, bounds: CGRect(x: 100, y: 100, width: 800, height: 500)),
            .init(id: 5, title: nil, bounds: CGRect(x: 100, y: 100, width: 800, height: 500))
        ]

        let assignments = RuntimeSnapshotProvider.resolveCGWindowAssignmentsForTesting(
            axWindows: axWindows,
            cgWindows: cgWindows
        )

        XCTAssertNil(assignments["ax:200:2"], "Ambiguous windows should remain unbound")
        XCTAssertNil(assignments["ax:200:0"], "Windows without a title hit should remain unbound")
    }

    func testRuntimeSnapshotProviderResolveCGWindowAssignmentsReportsAmbiguousDiagnostics() {
        let axWindows: [RuntimeSnapshotProvider.AXWindowEntryForTesting] = [
            .init(
                id: "ax:300:0",
                index: 0,
                title: "Document",
                bounds: CGRect(x: 100, y: 100, width: 800, height: 500)
            )
        ]
        let cgWindows: [RuntimeSnapshotProvider.CGWindowEntryForTesting] = [
            .init(
                id: 31,
                title: "Document",
                bounds: CGRect(x: 100, y: 100, width: 800, height: 500)
            ),
            .init(
                id: 32,
                title: "Document",
                bounds: CGRect(x: 100, y: 100, width: 800, height: 500)
            )
        ]

        let assignments = RuntimeSnapshotProvider.resolveCGWindowAssignmentsForTesting(
            axWindows: axWindows,
            cgWindows: cgWindows
        )
        let diagnostics = RuntimeSnapshotProvider.resolveCGWindowAssignmentDiagnosticsForTesting(
            axWindows: axWindows,
            cgWindows: cgWindows
        )

        XCTAssertTrue(assignments.isEmpty)
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics.first?.stableWindowID, "ax:300:0")
        XCTAssertEqual(diagnostics.first?.axWindowID, "ax:300:0")
        XCTAssertNil(diagnostics.first?.cgWindowID)
        XCTAssertEqual(diagnostics.first?.confidence, .ambiguous)
        XCTAssertNil(diagnostics.first?.source)
        XCTAssertEqual(diagnostics.first?.reason, .publicAssignmentAmbiguous)
        XCTAssertEqual(diagnostics.first?.candidateCount, 2)
        XCTAssertEqual(diagnostics.first?.allowedActions, WindowBindingConfidence.ambiguous.allowedActions)
        XCTAssertTrue(diagnostics.first?.isQuarantined == true)
    }

    func testRuntimeSnapshotProviderResolveCGWindowAssignmentsUsesFocusedAXStateAsPublicTieBreaker() {
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 500)
        let axWindows: [RuntimeSnapshotProvider.AXWindowEntryForTesting] = [
            .init(id: "ax:310:0", index: 0, title: "Document", bounds: bounds, isFocused: true),
            .init(id: "ax:310:1", index: 1, title: "Document", bounds: bounds)
        ]
        let cgWindows: [RuntimeSnapshotProvider.CGWindowEntryForTesting] = [
            .init(id: 311, title: "Document", bounds: bounds, isOnscreen: true),
            .init(id: 312, title: "Document", bounds: bounds, isOnscreen: true)
        ]

        let assignments = RuntimeSnapshotProvider.resolveCGWindowAssignmentsForTesting(
            axWindows: axWindows,
            cgWindows: cgWindows
        )
        let diagnostics = RuntimeSnapshotProvider.resolveCGWindowAssignmentDiagnosticsForTesting(
            axWindows: axWindows,
            cgWindows: cgWindows
        )

        XCTAssertEqual(assignments["ax:310:0"], 311)
        XCTAssertEqual(assignments["ax:310:1"], 312)
        XCTAssertTrue(diagnostics.isEmpty)
    }

    func testRuntimeSnapshotProviderResolveCGWindowAssignmentsUsesMinimizedAXStateAsPublicTieBreaker() {
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 500)
        let axWindows: [RuntimeSnapshotProvider.AXWindowEntryForTesting] = [
            .init(id: "ax:320:0", index: 0, title: "Document", bounds: bounds, isMinimized: true)
        ]
        let cgWindows: [RuntimeSnapshotProvider.CGWindowEntryForTesting] = [
            .init(id: 321, title: "Document", bounds: bounds, isOnscreen: true),
            .init(id: 322, title: "Document", bounds: bounds, isOnscreen: false)
        ]

        let assignments = RuntimeSnapshotProvider.resolveCGWindowAssignmentsForTesting(
            axWindows: axWindows,
            cgWindows: cgWindows
        )
        let diagnostics = RuntimeSnapshotProvider.resolveCGWindowAssignmentDiagnosticsForTesting(
            axWindows: axWindows,
            cgWindows: cgWindows
        )

        XCTAssertEqual(assignments["ax:320:0"], 322)
        XCTAssertTrue(diagnostics.isEmpty)
    }

    func testRuntimeSnapshotProviderPrivateExactBridgeConflictWithStickyBindingReportsDiagnosticAndUsesExactTarget() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let axWindows: [RuntimeSnapshotProvider.AXWindowEntryForTesting] = [
            .init(
                id: "ax:100:0",
                index: 0,
                title: "百度一下，你就知道",
                bounds: fullscreenBounds,
                bridgedCGWindowID: 202
            )
        ]
        let cgWindows: [RuntimeSnapshotProvider.CGWindowEntryForTesting] = [
            .init(id: 101, title: "百度一下，你就知道", bounds: fullscreenBounds),
            .init(id: 202, title: "百度一下，你就知道", bounds: fullscreenBounds)
        ]

        let assignments = RuntimeSnapshotProvider.resolveCGWindowAssignmentsForTesting(
            axWindows: axWindows,
            cgWindows: cgWindows,
            previousMatches: ["ax:100:0": 101],
            previousAXWindowIDs: ["ax:100:0"],
            previousCGWindowIDs: [101],
            pid: 100,
            appName: "Google Chrome"
        )
        let diagnostics = RuntimeSnapshotProvider.resolveCGWindowAssignmentDiagnosticsForTesting(
            axWindows: axWindows,
            cgWindows: cgWindows,
            previousMatches: ["ax:100:0": 101],
            previousAXWindowIDs: ["ax:100:0"],
            previousCGWindowIDs: [101],
            pid: 100,
            appName: "Google Chrome"
        )
        let conflictDiagnostic = diagnostics.first {
            $0.reason == .privateExactBridgeConflictsWithStickyBinding
        }

        XCTAssertEqual(assignments["ax:100:0"], 202)
        XCTAssertEqual(conflictDiagnostic?.stableWindowID, "cg:100:101")
        XCTAssertEqual(conflictDiagnostic?.axWindowID, "ax:100:0")
        XCTAssertEqual(conflictDiagnostic?.cgWindowID, 202)
        XCTAssertEqual(conflictDiagnostic?.confidence, .ambiguous)
        XCTAssertEqual(conflictDiagnostic?.source, .privateExactBridge)
        XCTAssertEqual(conflictDiagnostic?.candidateCount, 2)
        XCTAssertEqual(conflictDiagnostic?.allowedActions, WindowBindingConfidence.ambiguous.allowedActions)
        XCTAssertTrue(conflictDiagnostic?.isQuarantined == true)
    }

    func testRuntimeSnapshotProviderReportsAmbiguousFullscreenTopologyFallbackDiagnostics() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let axWindows: [RuntimeSnapshotProvider.AXWindowEntryForTesting] = [
            .init(
                id: "ax:400:0",
                index: 0,
                bounds: fullscreenBounds
            )
        ]
        let cgWindows: [RuntimeSnapshotProvider.CGWindowEntryForTesting] = [
            .init(
                id: 401,
                title: nil,
                bounds: fullscreenBounds,
                isOnscreen: false,
                spaceIDs: [12_001]
            ),
            .init(
                id: 402,
                title: nil,
                bounds: fullscreenBounds,
                isOnscreen: false,
                spaceIDs: [12_001]
            )
        ]

        let assignments = RuntimeSnapshotProvider.resolveCGWindowAssignmentsForTesting(
            axWindows: axWindows,
            cgWindows: cgWindows,
            pid: 400,
            appName: "Google Chrome"
        )
        let diagnostics = RuntimeSnapshotProvider.resolveCGWindowAssignmentDiagnosticsForTesting(
            axWindows: axWindows,
            cgWindows: cgWindows,
            pid: 400,
            appName: "Google Chrome"
        )
        let topologyDiagnostic = diagnostics.first {
            $0.reason == .fullscreenTopologyAmbiguous
        }

        XCTAssertTrue(assignments.isEmpty)
        XCTAssertEqual(topologyDiagnostic?.stableWindowID, "ax:400:0")
        XCTAssertEqual(topologyDiagnostic?.axWindowID, "ax:400:0")
        XCTAssertNil(topologyDiagnostic?.cgWindowID)
        XCTAssertEqual(topologyDiagnostic?.confidence, .ambiguous)
        XCTAssertEqual(topologyDiagnostic?.source, .fullscreenContentFallbackBinding)
        XCTAssertEqual(topologyDiagnostic?.candidateCount, 2)
        XCTAssertEqual(topologyDiagnostic?.allowedActions, WindowBindingConfidence.ambiguous.allowedActions)
        XCTAssertTrue(topologyDiagnostic?.isQuarantined == true)
    }

    func testRuntimeSnapshotProviderResolveCGWindowAssignmentsBindsSingleNewUnmatchedPairFromDelta() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let assignments = RuntimeSnapshotProvider.resolveCGWindowAssignmentsForTesting(
            axWindows: [
                .init(id: "ax:100:0", index: 0, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: "ax:100:1", index: 1, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: "ax:100:2", index: 2, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: "ax:100:3", index: 3, title: "百度一下，你就知道", bounds: fullscreenBounds)
            ],
            cgWindows: [
                .init(id: 243_747, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: 243_679, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: 240_029, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: 251_969, title: "百度一下，你就知道", bounds: fullscreenBounds)
            ],
            previousMatches: [
                "ax:100:0": 243_747,
                "ax:100:1": 243_679,
                "ax:100:2": 240_029
            ],
            previousAXWindowIDs: ["ax:100:0", "ax:100:1", "ax:100:2"],
            previousCGWindowIDs: [243_747, 243_679, 240_029],
            pid: 100,
            appName: "Google Chrome"
        )

        XCTAssertEqual(assignments["ax:100:0"], 243_747)
        XCTAssertEqual(assignments["ax:100:1"], 243_679)
        XCTAssertEqual(assignments["ax:100:2"], 240_029)
        XCTAssertEqual(assignments["ax:100:3"], 251_969)
    }

    func testRuntimeSnapshotProviderResolveCGWindowAssignmentsDoesNotGuessAcrossInitialAmbiguousSnapshot() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let assignments = RuntimeSnapshotProvider.resolveCGWindowAssignmentsForTesting(
            axWindows: [
                .init(id: "ax:100:0", index: 0, title: "百度一下，你就知道 - Google Chrome - test3", bounds: fullscreenBounds),
                .init(id: "ax:100:1", index: 1, title: "百度一下，你就知道 - Google Chrome - test2", bounds: fullscreenBounds),
                .init(id: "ax:100:2", index: 2, title: "百度一下，你就知道 - Google Chrome - test1", bounds: fullscreenBounds),
                .init(id: "ax:100:3", index: 3, title: "百度一下，你就知道 - Google Chrome - test5", bounds: fullscreenBounds)
            ],
            cgWindows: [
                .init(id: 243_747, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: 240_029, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: 240_016, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: 240_002, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: 251_969, title: "百度一下，你就知道", bounds: fullscreenBounds)
            ],
            previousMatches: [:],
            previousAXWindowIDs: [],
            previousCGWindowIDs: [],
            pid: 100,
            appName: "Google Chrome"
        )

        XCTAssertTrue(assignments.isEmpty)
    }

    func testRuntimeSnapshotProviderResolveCGWindowAssignmentsUsesPrivateExactBridgeWhenPublicSignalsRemainAmbiguous() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let assignments = RuntimeSnapshotProvider.resolveCGWindowAssignmentsForTesting(
            axWindows: [
                .init(
                    id: "ax:100:0",
                    index: 0,
                    title: "百度一下，你就知道",
                    bounds: fullscreenBounds,
                    bridgedCGWindowID: 243_747
                ),
                .init(
                    id: "ax:100:1",
                    index: 1,
                    title: "百度一下，你就知道",
                    bounds: fullscreenBounds,
                    bridgedCGWindowID: 243_679
                ),
                .init(
                    id: "ax:100:2",
                    index: 2,
                    title: "百度一下，你就知道",
                    bounds: fullscreenBounds,
                    bridgedCGWindowID: 240_029
                )
            ],
            cgWindows: [
                .init(id: 243_747, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: 243_679, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: 240_029, title: "百度一下，你就知道", bounds: fullscreenBounds)
            ],
            pid: 100,
            appName: "Google Chrome"
        )

        XCTAssertEqual(assignments["ax:100:0"], 243_747)
        XCTAssertEqual(assignments["ax:100:1"], 243_679)
        XCTAssertEqual(assignments["ax:100:2"], 240_029)
    }

    func testRuntimeSnapshotProviderResolveCGWindowAssignmentsKeepsHistoricalBindingsWhenSnapshotBecomesAmbiguous() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let assignments = RuntimeSnapshotProvider.resolveCGWindowAssignmentsForTesting(
            axWindows: [
                .init(id: "ax:100:0", index: 0, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: "ax:100:1", index: 1, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: "ax:100:2", index: 2, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: "ax:100:3", index: 3, title: "百度一下，你就知道", bounds: fullscreenBounds)
            ],
            cgWindows: [
                .init(id: 243_747, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: 243_679, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: 240_029, title: "百度一下，你就知道", bounds: fullscreenBounds),
                .init(id: 251_969, title: "百度一下，你就知道", bounds: fullscreenBounds)
            ],
            previousMatches: [
                "ax:100:0": 243_747,
                "ax:100:1": 243_679
            ],
            previousAXWindowIDs: ["ax:100:0", "ax:100:1"],
            previousCGWindowIDs: [243_747, 243_679],
            pid: 100,
            appName: "Google Chrome"
        )

        XCTAssertEqual(assignments["ax:100:0"], 243_747)
        XCTAssertEqual(assignments["ax:100:1"], 243_679)
        XCTAssertNil(assignments["ax:100:2"])
        XCTAssertNil(assignments["ax:100:3"])
    }

    func testRuntimeSnapshotProviderResolveCGWindowAssignmentsUsesExactTitlesToBreakFullscreenGeometryTies() {
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let axWindows: [RuntimeSnapshotProvider.AXWindowEntryForTesting] = [
            .init(
                id: "ax:100:0",
                index: 0,
                title: "Google 搜索 - Google Chrome - test1",
                bounds: fullscreenBounds
            ),
            .init(
                id: "ax:100:1",
                index: 1,
                title: "Google 搜索 - Google Chrome - test3",
                bounds: fullscreenBounds
            ),
            .init(
                id: "ax:100:2",
                index: 2,
                title: "Google 搜索 - Google Chrome - test5",
                bounds: fullscreenBounds
            )
        ]
        let cgWindows: [RuntimeSnapshotProvider.CGWindowEntryForTesting] = [
            .init(
                id: 243_679,
                title: "Google 搜索 - Google Chrome - test3",
                bounds: fullscreenBounds
            ),
            .init(
                id: 243_747,
                title: "Google 搜索 - Google Chrome - test1",
                bounds: fullscreenBounds
            ),
            .init(
                id: 240_029,
                title: "Google 搜索 - Google Chrome - test5",
                bounds: fullscreenBounds
            )
        ]

        let assignments = RuntimeSnapshotProvider.resolveCGWindowAssignmentsForTesting(
            axWindows: axWindows,
            cgWindows: cgWindows
        )

        XCTAssertEqual(assignments["ax:100:0"], 243_747)
        XCTAssertEqual(assignments["ax:100:1"], 243_679)
        XCTAssertEqual(assignments["ax:100:2"], 240_029)
    }

    func testRuntimeSnapshotProviderTestingAXEntriesCarryPublicWindowState() throws {
        let provider = RuntimeSnapshotProvider()
        let pid: pid_t = 22_001
        let bounds = CGRect(x: 20, y: 40, width: 900, height: 700)
        let axWindows = [
            RuntimeSnapshotProvider.AXWindowEntryForTesting(
                id: "ax:22001:0",
                index: 0,
                title: "Focused Doc",
                bounds: bounds,
                isMinimized: true,
                isFocused: true,
                isMain: false
            )
        ]
        let cgWindowsForTesting = [
            RuntimeSnapshotProvider.CGWindowEntryForTesting(
                id: 440_001,
                title: "Focused Doc",
                bounds: bounds,
                isOnscreen: true,
                alpha: 1.0,
                storeType: 1,
                spaceIDs: [1]
            )
        ]

        let mergedEntries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: axWindows,
            cgWindows: cgWindowsForTesting,
            pid: pid
        )
        XCTAssertEqual(mergedEntries.first?.isMinimized, true)

        _ = provider.resolvedStableWindowEntries(
            axWindows: [
                RuntimeAXWindowEntry(
                    index: 0,
                    id: "ax:22001:0",
                    title: "Focused Doc",
                    sourceTitle: "Focused Doc",
                    isMinimized: true,
                    isFocused: true,
                    isMain: false,
                    window: AXUIElementCreateApplication(90_202),
                    frame: bounds
                )
            ],
            cgWindows: cgWindowsForTesting.map {
                RuntimeCGWindowEntry(
                    id: $0.id,
                    title: $0.title,
                    bounds: $0.bounds,
                    isOnscreen: $0.isOnscreen,
                    alpha: $0.alpha,
                    storeType: $0.storeType,
                    spaceIDs: $0.spaceIDs
                )
            },
            pid: pid,
            appName: "FlowTab Test"
        )

        let record = try XCTUnwrap(provider.windowMappingStateByPID[pid]?.windowRecordsByCGWindowID[440_001])
        XCTAssertEqual(
            record.currentAXAttachment?.state,
            RuntimeAXWindowState(
                isMinimized: true,
                isFocused: true,
                isMain: false
            )
        )
        XCTAssertTrue(record.isMinimized)
        XCTAssertTrue(record.isFocused)
        XCTAssertFalse(record.isMain)
    }

    func testAXWindowInspectorHelpersRoundTripWindowIDsAndHandleSystemElementLookups() {
        let windowID = AXWindowInspectorForTesting.makeWindowID(pid: 123, index: 7)
        XCTAssertEqual(windowID, "ax:123:7")
        XCTAssertEqual(AXWindowInspectorForTesting.windowIndex(from: windowID, expectedPID: 123), 7)
        XCTAssertNil(AXWindowInspectorForTesting.windowIndex(from: "invalid", expectedPID: 123))
        XCTAssertNil(AXWindowInspectorForTesting.windowIndex(from: "ax:999:7", expectedPID: 123))
        XCTAssertEqual(AXWindowInspectorForTesting.fallbackTitle(index: 0), "Window #1")

        let systemElement = AXUIElementCreateSystemWide()
        let role = AXWindowInspectorForTesting.role(for: systemElement)
        let isSwitchable = AXWindowInspectorForTesting.isSwitchable(systemElement)
        if let role {
            XCTAssertEqual(isSwitchable, role == kAXWindowRole as String)
        } else {
            XCTAssertTrue(isSwitchable)
        }
        XCTAssertFalse(AXWindowInspectorForTesting.isMinimized(systemElement))
        XCTAssertFalse(AXWindowInspectorForTesting.isFocused(systemElement))
        XCTAssertFalse(AXWindowInspectorForTesting.isMain(systemElement))

        if let title = AXWindowInspectorForTesting.title(for: systemElement) {
            XCTAssertFalse(title.isEmpty)
        }
    }

    func testAXWindowInspectorPreferredWindowTitleSelectsMostSpecificCandidate() {
        let preferredTitle = AXWindowInspectorForTesting.preferredWindowTitle(
            candidates: [
                "Google Chrome",
                "新标签页 - Google Chrome - test4",
                nil
            ]
        )
        XCTAssertEqual(preferredTitle, "新标签页 - Google Chrome - test4")

        let fallbackTitle = AXWindowInspectorForTesting.preferredWindowTitle(
            candidates: [
                "Google Chrome",
                nil
            ]
        )
        XCTAssertEqual(fallbackTitle, "Google Chrome")
    }

    func testAXWindowInspectorWindowsFetchLogDetailsIncludesErrorTypeAndCounts() {
        let details = AXWindowInspectorForTesting.windowsFetchLogDetails(
            error: .cannotComplete,
            rawValueTypeDescription: "CFArray",
            rawArrayCount: 5,
            decodedCount: 0
        )

        XCTAssertEqual(
            details,
            "fetchError=-25204 rawValueType=CFArray rawArrayCount=5 decodedCount=0"
        )
    }

    func testAXWindowInspectorWindowsFetchLogDetailsIncludesRemoteScanCompleteness() {
        let details = AXWindowInspectorForTesting.windowsFetchLogDetails(
            error: .success,
            rawValueTypeDescription: "CFArray",
            rawArrayCount: 1,
            decodedCount: 1,
            remoteScanCompleteness: .partialTimedOut(scanned: 24, maximum: 1_000)
        )

        XCTAssertEqual(
            details,
            "fetchError=0 rawValueType=CFArray rawArrayCount=1 decodedCount=1 remoteScan=partialTimedOut scanned=24 maximum=1000"
        )
    }

    func testAXWindowInspectorWindowsFetchLogDetailsUsesNilRawArrayCountWhenMissing() {
        let details = AXWindowInspectorForTesting.windowsFetchLogDetails(
            error: .success,
            rawValueTypeDescription: "nil",
            rawArrayCount: nil,
            decodedCount: 0
        )

        XCTAssertEqual(
            details,
            "fetchError=0 rawValueType=nil rawArrayCount=nil decodedCount=0"
        )
    }

    func testAXTypedExtractionDecodesPointAndSizeValues() {
        var point = CGPoint(x: 12, y: 34)
        var size = CGSize(width: 56, height: 78)
        guard
            let pointValue = AXValueCreate(.cgPoint, &point),
            let sizeValue = AXValueCreate(.cgSize, &size)
        else {
            XCTFail("Expected AXValue fixtures")
            return
        }

        switch AXWindowInspectorForTesting.point(
            from: pointValue,
            attribute: kAXPositionAttribute as CFString
        ) {
        case .success(let decodedPoint):
            XCTAssertEqual(decodedPoint, point)
        case .failure(let error):
            XCTFail("Expected point extraction to succeed, got \(error)")
        }

        switch AXWindowInspectorForTesting.size(
            from: sizeValue,
            attribute: kAXSizeAttribute as CFString
        ) {
        case .success(let decodedSize):
            XCTAssertEqual(decodedSize, size)
        case .failure(let error):
            XCTFail("Expected size extraction to succeed, got \(error)")
        }
    }

    func testAXTypedExtractionReportsTypeMismatchWithoutTrapping() {
        var size = CGSize(width: 56, height: 78)
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            XCTFail("Expected AXValue fixture")
            return
        }

        switch AXWindowInspectorForTesting.point(
            from: sizeValue,
            attribute: kAXPositionAttribute as CFString
        ) {
        case .success(let point):
            XCTFail("Expected point extraction to reject size value, got \(point)")
        case .failure(let error):
            XCTAssertTrue(String(describing: error).contains("expected=AXValue<CGPoint>"))
        }

        switch AXWindowInspectorForTesting.axElement(
            from: "not-a-window" as CFString,
            attribute: kAXFocusedWindowAttribute as CFString
        ) {
        case .success:
            XCTFail("Expected AXUIElement extraction to reject CFString")
        case .failure(let error):
            XCTAssertEqual(
                String(describing: error),
                "typeMismatch attribute=AXFocusedWindow expected=AXUIElement actual=CFString"
            )
        }
    }

    func testAXTypedExtractionCountsRawCFArraysWithoutUnsafeCastAtCallSite() {
        let array = ["a", "b"] as NSArray

        XCTAssertEqual(AXWindowInspectorForTesting.rawArrayCount(from: array), 2)
        XCTAssertEqual(AXWindowInspectorForTesting.typeDescription(for: array), "CFArray")
        XCTAssertNil(AXWindowInspectorForTesting.rawArrayCount(from: "not-array" as CFString))
    }

    func testRuntimeWindowPreviewProviderPreferredCaptureSourceSizeUsesContentRectPixelScale() {
        let preferredSize = RuntimeWindowPreviewProvider.preferredCaptureSourceSizeForTesting(
            contentRect: CGRect(x: 24, y: 38, width: 1_600, height: 1_000),
            pointPixelScale: 2,
            fallbackFrame: CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        )
        XCTAssertEqual(preferredSize.width, 3_200)
        XCTAssertEqual(preferredSize.height, 2_000)

        let fallbackSize = RuntimeWindowPreviewProvider.preferredCaptureSourceSizeForTesting(
            contentRect: .zero,
            pointPixelScale: 2,
            fallbackFrame: CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        )
        XCTAssertEqual(fallbackSize.width, 1_728)
        XCTAssertEqual(fallbackSize.height, 1_079)
    }

    func testRuntimeWindowPreviewProviderTrimsTransparentPaddingFromCapturedImage() {
        let image = makePreviewCGImage(size: CGSize(width: 180, height: 120)) { context in
            context.setFillColor(NSColor.clear.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 180, height: 120))
            context.setFillColor(NSColor.systemBlue.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 120))
        }

        let trimmedImage = RuntimeWindowPreviewProvider.trimmedTransparentPaddingIfNeededForTesting(
            image
        )

        XCTAssertEqual(trimmedImage.width, 160)
        XCTAssertEqual(trimmedImage.height, 120)
    }

    @MainActor
    func testLiveSwitcherModelWindowPreviewUsesCaptureCacheAcrossReads() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "front-1", title: "Inbox", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "front-2", title: "Draft", isMinimized: false, lastActiveAt: 20)
        ]
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: currentApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let runtimeProjectionService = makeCurrentAppWindowProjectionService(
            appID: appID,
            candidate: candidate,
            context: context
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        model.frontmostApplicationOverride = { currentApp }

        var captureCallCount = 0
        model.previewCaptureOverride = { _, _, title, _ in
            captureCallCount += 1
            let imageColor: NSColor = title == "Inbox" ? .black : .white
            let titleBarStyle: WindowTitleBarStyleGuess = title == "Inbox" ? .dark : .light
            return (
                image: self.makeColorImage(color: imageColor),
                resolvedWindowID: CGWindowID(captureCallCount),
                titleBarStyle: titleBarStyle
            )
        }

        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))
        XCTAssertEqual(runtimeProjectionService.snapshotRequestCount(), 0)
        XCTAssertEqual(runtimeProjectionService.lightweightSnapshotRequestCount(), 0)

        let firstSnapshot = model.windowPreviewSnapshotForTesting()
        let secondSnapshot = model.windowPreviewSnapshotForTesting()

        XCTAssertEqual(captureCallCount, 2)
        XCTAssertEqual(firstSnapshot.count, 2)
        XCTAssertTrue(firstSnapshot.allSatisfy { $0.hasImage })
        XCTAssertEqual(
            firstSnapshot.first(where: { $0.id == "front-1" })?.titleBarStyle,
            .dark
        )
        XCTAssertEqual(
            secondSnapshot.first(where: { $0.id == "front-2" })?.titleBarStyle,
            .light
        )
    }

    @MainActor
    func testLiveSwitcherModelPreviewCacheIdentityIgnoresTitleChanges() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "front-1", title: "Inbox", isMinimized: false, lastActiveAt: 30)
        ]
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: currentApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let runtimeProjectionService = makeCurrentAppWindowProjectionService(
            appID: appID,
            candidate: candidate,
            context: context
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        model.frontmostApplicationOverride = { currentApp }

        var captureCallCount = 0
        model.previewCaptureOverride = { _, _, _, _ in
            captureCallCount += 1
            return (
                image: self.makeColorImage(color: .black),
                resolvedWindowID: 24_001,
                titleBarStyle: nil
            )
        }

        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))
        XCTAssertEqual(runtimeProjectionService.snapshotRequestCount(), 0)
        XCTAssertEqual(runtimeProjectionService.lightweightSnapshotRequestCount(), 0)
        let initialSnapshot = model.windowPreviewSnapshotForTesting()
        XCTAssertEqual(captureCallCount, 1)
        XCTAssertTrue(initialSnapshot.first?.hasImage == true)

        guard let capturedContext = model.runtimeContextsByID[appID],
              var windowContext = capturedContext.windowsByID["front-1"]
        else {
            return XCTFail("Expected runtime context after preview capture")
        }
        windowContext = RuntimeWindowContext(
            id: windowContext.id,
            title: "Inbox - Edited",
            isMinimized: windowContext.isMinimized,
            ownerPID: windowContext.ownerPID,
            cgWindowID: windowContext.cgWindowID,
            spaceIDs: windowContext.spaceIDs,
            inferredTitleBarStyle: windowContext.inferredTitleBarStyle,
            activationHandleID: windowContext.activationHandleID,
            axWindow: windowContext.axWindow,
            frame: windowContext.frame,
            allowsPublicAXRecovery: windowContext.allowsPublicAXRecovery,
            hasStickyBinding: windowContext.hasStickyBinding,
            lastConfirmationSource: windowContext.lastConfirmationSource
        )
        model.runtimeContextsByID[appID] = RuntimeAppContext(
            appID: capturedContext.appID,
            runningApp: capturedContext.runningApp,
            windowsByID: ["front-1": windowContext]
        )

        let updatedTitleSnapshot = model.windowPreviewSnapshotForTesting()
        XCTAssertEqual(captureCallCount, 1)
        XCTAssertTrue(updatedTitleSnapshot.first?.hasImage == true)
    }

    @MainActor
    func testLiveSwitcherModelFocusedWindowSessionFreezesPreviewSnapshotUntilSessionEnds() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "front-1", title: "Inbox", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "front-2", title: "Draft", isMinimized: false, lastActiveAt: 20)
        ]
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: currentApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let runtimeProjectionService = makeCurrentAppWindowProjectionService(
            appID: appID,
            candidate: candidate,
            context: context
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        model.frontmostApplicationOverride = { currentApp }

        enum PreviewPhase {
            case initial
            case invalidated
        }

        var previewPhase: PreviewPhase = .initial
        var captureCallCount = 0
        model.previewCaptureOverride = { _, _, title, _ in
            captureCallCount += 1
            switch previewPhase {
            case .initial:
                let imageColor: NSColor = title == "Inbox" ? .black : .white
                let titleBarStyle: WindowTitleBarStyleGuess = title == "Inbox" ? .dark : .light
                return (
                    image: self.makeColorImage(color: imageColor),
                    resolvedWindowID: CGWindowID(captureCallCount),
                    titleBarStyle: titleBarStyle
                )
            case .invalidated:
                return nil
            }
        }

        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))
        XCTAssertEqual(runtimeProjectionService.snapshotRequestCount(), 0)
        XCTAssertEqual(runtimeProjectionService.lightweightSnapshotRequestCount(), 0)
        let initialSnapshot = model.windowPreviewSnapshotForTesting()
        XCTAssertEqual(initialSnapshot.count, 2)
        XCTAssertTrue(initialSnapshot.allSatisfy(\.hasImage))
        XCTAssertEqual(captureCallCount, 2)

        previewPhase = .invalidated

        model.handle(.tabForward)

        let switchedSnapshot = model.windowPreviewSnapshotForTesting()
        XCTAssertEqual(captureCallCount, 2)
        XCTAssertEqual(switchedSnapshot.count, 2)
        XCTAssertTrue(switchedSnapshot.allSatisfy(\.hasImage))

        model.cancelSelection()
        XCTAssertNil(model.session)

        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))
        XCTAssertEqual(runtimeProjectionService.snapshotRequestCount(), 0)
        XCTAssertEqual(runtimeProjectionService.lightweightSnapshotRequestCount(), 0)
        let restartedSnapshot = model.windowPreviewSnapshotForTesting()
        XCTAssertEqual(restartedSnapshot.count, 2)
        XCTAssertTrue(restartedSnapshot.allSatisfy { !$0.hasImage })
        XCTAssertEqual(captureCallCount, 4)
    }

    @MainActor
    func testLiveSwitcherModelPreviewCaptureFailureStateRetriesNextGeneration() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "front-1", title: "Inbox", isMinimized: false, lastActiveAt: 30)
        ]
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: currentApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let runtimeProjectionService = makeCurrentAppWindowProjectionService(
            appID: appID,
            candidate: candidate,
            context: context
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        model.frontmostApplicationOverride = { currentApp }

        var captureCallCount = 0
        model.previewCaptureOverride = { _, _, _, _ in
            captureCallCount += 1
            return nil
        }

        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))
        XCTAssertEqual(runtimeProjectionService.snapshotRequestCount(), 0)
        XCTAssertEqual(runtimeProjectionService.lightweightSnapshotRequestCount(), 0)

        let firstSnapshot = model.windowPreviewSnapshotForTesting()
        XCTAssertEqual(firstSnapshot.count, 1)
        XCTAssertFalse(firstSnapshot[0].hasImage)
        XCTAssertEqual(captureCallCount, 1)
        guard
            case let .failed(reason, retryAfterGeneration?) =
                model.previewCaptureStatesForTesting().values.first
        else {
            return XCTFail("Expected transient preview failure state")
        }
        XCTAssertEqual(reason, .transientSystemError)
        XCTAssertEqual(retryAfterGeneration, model.previewCaptureGeneration + 1)

        _ = model.windowPreviewSnapshotForTesting()
        XCTAssertEqual(captureCallCount, 1)

        model.previewCaptureGeneration &+= 1
        _ = model.windowPreviewSnapshotForTesting()
        XCTAssertEqual(captureCallCount, 2)
    }

    @MainActor
    func testLiveSwitcherModelPreviewCaptureSkipsBindingWithoutCaptureAction() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let window = WindowCandidate(
            id: "ambiguous-window",
            title: "Ambiguous Window",
            isMinimized: false,
            lastActiveAt: 30
        )
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: currentApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 100,
            windows: [window]
        )
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                window.id: RuntimeWindowContext(
                    id: window.id,
                    title: window.title,
                    isMinimized: window.isMinimized,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 24_701,
                    bindingConfidenceOverride: .ambiguous,
                    bindingCandidateCount: 2
                )
            ]
        )
        let runtimeProjectionService = makeCurrentAppWindowProjectionService(
            appID: appID,
            candidate: candidate,
            context: context
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        model.runtimeProjectionMaintenanceEnabled = false

        model.frontmostApplicationOverride = { currentApp }

        var captureCallCount = 0
        model.previewCaptureOverride = { _, _, _, _ in
            captureCallCount += 1
            return (
                image: self.makeColorImage(color: .black),
                resolvedWindowID: 24_701,
                titleBarStyle: nil
            )
        }

        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))
        XCTAssertEqual(runtimeProjectionService.snapshotRequestCount(), 0)
        XCTAssertEqual(runtimeProjectionService.lightweightSnapshotRequestCount(), 0)

        let snapshot = model.windowPreviewSnapshotForTesting()

        XCTAssertEqual(snapshot.count, 1)
        XCTAssertFalse(snapshot[0].hasImage)
        XCTAssertEqual(captureCallCount, 0)
        guard
            case let .failed(reason, retryAfterGeneration) =
                model.previewCaptureStatesForTesting().values.first
        else {
            return XCTFail("Expected binding action preview failure state")
        }
        XCTAssertEqual(reason, .bindingActionDisallowed)
        XCTAssertNil(retryAfterGeneration)
    }

}
