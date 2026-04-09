import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    func testRuntimeSnapshotProviderAssemblySelectsPrimaryRowsAndFiltersMinimizedOnlyApps() {
        let rows = RuntimeSnapshotProvider.assembleSnapshotRowsForTesting(
            apps: [
                RuntimeSnapshotProvider.SnapshotAssemblyApp(
                    pid: 10,
                    bundleIdentifier: "com.example.mail",
                    localizedName: "Mail",
                    launchDate: Date(timeIntervalSince1970: 100)
                ),
                RuntimeSnapshotProvider.SnapshotAssemblyApp(
                    pid: 11,
                    bundleIdentifier: "com.example.mail",
                    localizedName: "Mail",
                    launchDate: Date(timeIntervalSince1970: 200)
                ),
                RuntimeSnapshotProvider.SnapshotAssemblyApp(
                    pid: 20,
                    bundleIdentifier: "com.example.chat",
                    localizedName: "Chat",
                    launchDate: Date(timeIntervalSince1970: 150)
                ),
                RuntimeSnapshotProvider.SnapshotAssemblyApp(
                    pid: 30,
                    bundleIdentifier: "com.example.notes",
                    localizedName: "Notes",
                    launchDate: Date(timeIntervalSince1970: 50)
                )
            ],
            windowsByPID: [
                10: [
                    RuntimeSnapshotProvider.SnapshotAssemblyWindow(
                        windowID: "mail-legacy",
                        title: "Inbox",
                        isMinimized: false,
                        cgWindowID: 10
                    )
                ],
                11: [
                    RuntimeSnapshotProvider.SnapshotAssemblyWindow(
                        windowID: "mail-1",
                        title: "Inbox",
                        isMinimized: false,
                        cgWindowID: 11
                    ),
                    RuntimeSnapshotProvider.SnapshotAssemblyWindow(
                        windowID: "mail-2",
                        title: "Draft",
                        isMinimized: false,
                        cgWindowID: 12
                    )
                ],
                20: [
                    RuntimeSnapshotProvider.SnapshotAssemblyWindow(
                        windowID: "chat-1",
                        title: "Standup",
                        isMinimized: true,
                        cgWindowID: 20
                    )
                ]
            ],
            rankByPID: [11: 0, 20: 1, 10: 2, 30: 3],
            hideMinimizedAppsFromAppLayer: true,
            now: 1_000
        )

        XCTAssertEqual(rows.map(\.pid), [11, 30])
        XCTAssertEqual(rows.first?.candidate.id, "com.example.mail")
        XCTAssertEqual(rows.first?.candidate.windows.map(\.id), ["mail-1", "mail-2", "mail-legacy"])
        XCTAssertEqual(rows.last?.candidate.id, "com.example.notes")
        XCTAssertTrue(rows.allSatisfy { $0.candidate.id != "com.example.chat" })
    }

    func testRuntimeSnapshotProviderMergedWindowStatsCombinesCountsAcrossProcessIDs() {
        let mergedStats = RuntimeSnapshotProvider.mergedWindowStatsForTesting(
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

    func testRuntimeSnapshotProviderWindowListKeepsSpaceBackedEntriesAfterAXDisappearsWithoutStickyBinding() {
        let mergedEntries = RuntimeSnapshotProvider.resolveWindowEntriesForTesting(
            axWindows: [],
            cgWindows: [
                .init(
                    id: 243_747,
                    title: "Recovered Window",
                    bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
                    isOnscreen: false,
                    spaceIDs: [11_679]
                )
            ],
            previousMatches: [:],
            previousAXWindowIDs: ["ax:18405:0"],
            previousCGWindowIDs: [240_029],
            pid: 18405,
            appName: "Google Chrome"
        )

        XCTAssertEqual(mergedEntries.map(\.windowID), ["cg:18405:243747"])
        XCTAssertEqual(mergedEntries.first?.title, "Recovered Window")
        XCTAssertEqual(mergedEntries.first?.cgWindowID, 243_747)
        XCTAssertNil(mergedEntries.first?.lastConfirmationSource)
    }

    func testRuntimeSnapshotProviderWindowListDeduplicatesUnmatchedAXEntriesSharingSameSpaceBinding() {
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
                    spaceIDs: [11_679]
                )
            ],
            pid: 18405,
            appName: "Google Chrome"
        )

        XCTAssertEqual(mergedEntries.map(\.windowID), ["cg:18405:288544"])
        XCTAssertEqual(mergedEntries.first?.cgWindowID, 288_544)
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

    func testRuntimeSnapshotProviderWindowListKeepsStickyMatchesWhenAXTitlesChange() {
        let provider = RuntimeSnapshotProvider()
        let pid: pid_t = 18405
        let appName = "Google Chrome"
        let fullscreenBounds = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)

        let firstAXWindows = [
            RuntimeSnapshotProvider.AXWindowEntry(
                index: 0,
                id: "ax:18405:0",
                title: "Doc A",
                sourceTitle: "Doc A",
                isMinimized: false,
                window: AXUIElementCreateApplication(90_001),
                frame: fullscreenBounds
            ),
            RuntimeSnapshotProvider.AXWindowEntry(
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
            RuntimeSnapshotProvider.CGWindowEntry(
                id: 240_001,
                title: "Doc A",
                bounds: fullscreenBounds,
                isOnscreen: true,
                alpha: 1.0,
                storeType: 1
            ),
            RuntimeSnapshotProvider.CGWindowEntry(
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
            RuntimeSnapshotProvider.AXWindowEntry(
                index: 0,
                id: "ax:18405:0",
                title: "Doc A (Updated)",
                sourceTitle: "Doc A (Updated)",
                isMinimized: false,
                window: firstAXWindows[0].window,
                frame: fullscreenBounds
            ),
            RuntimeSnapshotProvider.AXWindowEntry(
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
            RuntimeSnapshotProvider.CGWindowEntry(
                id: 240_001,
                title: nil,
                bounds: fullscreenBounds,
                isOnscreen: true,
                alpha: 1.0,
                storeType: 1
            ),
            RuntimeSnapshotProvider.CGWindowEntry(
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

    func testRuntimeSnapshotProviderAssemblyIncludesMinimizedAppsWhenFilterDisabledAndUsesFallbackGroup() {
        let rows = RuntimeSnapshotProvider.assembleSnapshotRowsForTesting(
            apps: [
                RuntimeSnapshotProvider.SnapshotAssemblyApp(
                    pid: 41,
                    bundleIdentifier: nil,
                    localizedName: "Zulu",
                    launchDate: Date(timeIntervalSince1970: 100)
                ),
                RuntimeSnapshotProvider.SnapshotAssemblyApp(
                    pid: 42,
                    bundleIdentifier: nil,
                    localizedName: "Alpha",
                    launchDate: Date(timeIntervalSince1970: 100)
                )
            ],
            windowsByPID: [
                41: [
                    RuntimeSnapshotProvider.SnapshotAssemblyWindow(
                        windowID: "z-1",
                        title: "Zulu Window",
                        isMinimized: true,
                        cgWindowID: 41
                    )
                ],
                42: [
                    RuntimeSnapshotProvider.SnapshotAssemblyWindow(
                        windowID: "a-1",
                        title: "Alpha Window",
                        isMinimized: true,
                        cgWindowID: 42
                    )
                ]
            ],
            rankByPID: [41: 5, 42: 5],
            hideMinimizedAppsFromAppLayer: false,
            now: 2_000
        )

        XCTAssertEqual(rows.map(\.pid), [42, 41])
        XCTAssertEqual(rows.map(\.candidate.groupID), ["a", "z"])
        XCTAssertTrue(rows.allSatisfy { $0.candidate.windows.first?.isMinimized == true })
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

    func testRuntimeSnapshotProviderGroupIDMappingCoversFallbackAndBundleShapes() {
        XCTAssertEqual(
            RuntimeSnapshotProvider.groupIDForTesting(
                bundleIdentifier: nil,
                fallbackName: "Notes"
            ),
            "n"
        )
        XCTAssertEqual(
            RuntimeSnapshotProvider.groupIDForTesting(
                bundleIdentifier: "com.example.mail",
                fallbackName: "Mail"
            ),
            "example"
        )
        XCTAssertEqual(
            RuntimeSnapshotProvider.groupIDForTesting(
                bundleIdentifier: "singleton",
                fallbackName: "Single"
            ),
            "singleton"
        )
        XCTAssertEqual(
            RuntimeSnapshotProvider.groupIDForTesting(
                bundleIdentifier: "",
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
        let model = LiveSwitcherModel()
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "front-1", title: "Inbox", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "front-2", title: "Draft", isMinimized: false, lastActiveAt: 20)
        ]
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )

        model.frontmostApplicationOverride = { currentApp }
        model.snapshotProviderOverride = {
            RuntimeSnapshot(
                apps: [
                    AppSwitchCandidate(
                        id: appID,
                        displayName: currentApp.localizedName ?? "Current App",
                        groupID: "current",
                        lastActiveAt: 100,
                        windows: windows
                    )
                ],
                contextsByID: [appID: context]
            )
        }

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
    func testLiveSwitcherModelFocusedWindowSessionFreezesPreviewSnapshotUntilSessionEnds() {
        let model = LiveSwitcherModel()
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "front-1", title: "Inbox", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "front-2", title: "Draft", isMinimized: false, lastActiveAt: 20)
        ]
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )

        model.frontmostApplicationOverride = { currentApp }
        model.snapshotProviderOverride = {
            RuntimeSnapshot(
                apps: [
                    AppSwitchCandidate(
                        id: appID,
                        displayName: currentApp.localizedName ?? "Current App",
                        groupID: "current",
                        lastActiveAt: 100,
                        windows: windows
                    )
                ],
                contextsByID: [appID: context]
            )
        }

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
        XCTAssertEqual(captureCallCount, 2)

        previewPhase = .invalidated

        let initialSnapshot = model.windowPreviewSnapshotForTesting()
        XCTAssertEqual(initialSnapshot.count, 2)
        XCTAssertTrue(initialSnapshot.allSatisfy(\.hasImage))

        model.handle(.tabForward)

        let switchedSnapshot = model.windowPreviewSnapshotForTesting()
        XCTAssertEqual(captureCallCount, 2)
        XCTAssertEqual(switchedSnapshot.count, 2)
        XCTAssertTrue(switchedSnapshot.allSatisfy(\.hasImage))

        model.cancelSelection()
        XCTAssertNil(model.session)

        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))
        XCTAssertEqual(captureCallCount, 4)

        let restartedSnapshot = model.windowPreviewSnapshotForTesting()
        XCTAssertEqual(restartedSnapshot.count, 2)
        XCTAssertTrue(restartedSnapshot.allSatisfy { !$0.hasImage })
    }

}
