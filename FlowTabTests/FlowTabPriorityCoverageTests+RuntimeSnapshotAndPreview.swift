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
        XCTAssertEqual(rows.first?.candidate.windows.map(\.id), ["mail-1", "mail-2"])
        XCTAssertEqual(rows.last?.candidate.id, "com.example.notes")
        XCTAssertTrue(rows.allSatisfy { $0.candidate.id != "com.example.chat" })
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

    func testRuntimeWindowPreviewProviderCandidateWindowOrderingForPreferredAndTitleMatches() {
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

        XCTAssertEqual(candidateIDs, [3, 1, 2, 4])
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
            .init(id: "ax:100:0", index: 0, bounds: CGRect(x: 10, y: 10, width: 600, height: 420)),
            .init(id: "ax:100:1", index: 1, bounds: CGRect(x: 640, y: 10, width: 600, height: 420))
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

    func testRuntimeSnapshotProviderResolveCGWindowAssignmentsSkipsAmbiguousOrLowConfidenceMatches() {
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

        XCTAssertNil(assignments["ax:200:2"], "Ambiguous high-score windows should remain unbound")
        XCTAssertNil(assignments["ax:200:0"], "Low-confidence windows should remain unbound")
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

}
