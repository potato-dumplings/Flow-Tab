import AppKit
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testSystemAppMRUStateBootstrapUsesFrontmostThenGlobalFallbackAndLaunchOrder() {
        var state = SystemAppMRUState()
        let apps = [
            mruRunningApp(appID: "app.front", pid: 10, launchedAt: 1),
            mruRunningApp(appID: "app.window-top", pid: 20, launchedAt: 2),
            mruRunningApp(appID: "app.newer", pid: 30, launchedAt: 4),
            mruRunningApp(appID: "app.older", pid: 40, launchedAt: 3)
        ]

        XCTAssertEqual(
            state.prepareForRanking(
                runningApplications: apps,
                frontmostAppID: "app.front",
                fallbackRankByPID: [20: 0]
            ),
            .bootstrap
        )
        XCTAssertEqual(
            state.orderedAppIDs,
            ["app.front", "app.window-top", "app.newer", "app.older"]
        )

        XCTAssertNil(
            state.prepareForRanking(
                runningApplications: apps,
                frontmostAppID: "app.front",
                fallbackRankByPID: [40: 0, 30: 1, 20: 2]
            )
        )
        XCTAssertEqual(
            state.orderedAppIDs,
            ["app.front", "app.window-top", "app.newer", "app.older"]
        )
    }

    func testSystemAppMRUStateNewSessionRebuildsOrderAcrossProcessIdentifiers() {
        var state = SystemAppMRUState()
        let relaunchedApps = [
            mruRunningApp(appID: "app.current", pid: 1_001, launchedAt: 20),
            mruRunningApp(appID: "app.previous", pid: 2_002, launchedAt: 10)
        ]

        XCTAssertEqual(
            state.reconcileSystemOrder(
                ["app.current", "app.previous"],
                runningApplications: relaunchedApps
            ),
            .systemOrder
        )
        let rankByPID = state.rankByPID(for: relaunchedApps)

        XCTAssertEqual(state.orderedAppIDs, ["app.current", "app.previous"])
        XCTAssertEqual(rankByPID[1_001], 0)
        XCTAssertEqual(rankByPID[2_002], 1)
        XCTAssertEqual(state.generation, 1)
    }

    func testSystemAppMRUStateNewSessionUsesSystemOrderAsItsInitialOrder() {
        var state = SystemAppMRUState()
        let runningApps = [
            mruRunningApp(appID: "app.expected-next", pid: 1_001, launchedAt: 10),
            mruRunningApp(appID: "app.other", pid: 2_002, launchedAt: 20),
            mruRunningApp(appID: "app.launch-frontmost", pid: 3_003, launchedAt: 30)
        ]

        XCTAssertEqual(
            state.reconcileSystemOrder(
                ["app.expected-next", "app.other", "app.launch-frontmost"],
                runningApplications: runningApps
            ),
            .systemOrder
        )
        XCTAssertEqual(
            state.orderedAppIDs,
            ["app.expected-next", "app.other", "app.launch-frontmost"]
        )
    }

    func testSystemAppMRUStateSystemOrderReplacesSessionBootstrapFallbackOrder() {
        var state = SystemAppMRUState()
        let runningApps = [
            mruRunningApp(appID: "app.current", pid: 101, launchedAt: 40),
            mruRunningApp(appID: "app.expected-next", pid: 202, launchedAt: 30),
            mruRunningApp(appID: "app.other", pid: 303, launchedAt: 20),
            mruRunningApp(appID: "app.terminal", pid: 404, launchedAt: 10)
        ]
        XCTAssertEqual(
            state.prepareForRanking(
                runningApplications: runningApps,
                frontmostAppID: "app.current",
                fallbackRankByPID: [404: 0, 202: 1, 303: 2]
            ),
            .bootstrap
        )
        XCTAssertEqual(
            state.orderedAppIDs,
            ["app.current", "app.terminal", "app.expected-next", "app.other"]
        )

        XCTAssertEqual(
            state.reconcileSystemOrder(
                ["app.current", "app.expected-next", "app.other", "app.terminal"],
                runningApplications: runningApps
            ),
            .systemOrder
        )
        XCTAssertEqual(
            state.orderedAppIDs,
            ["app.current", "app.expected-next", "app.other", "app.terminal"]
        )
        XCTAssertEqual(state.generation, 2)
    }

    func testSystemAppMRUStateAppliesLaunchActivationTerminationAndMultiProcessRules() {
        var state = SystemAppMRUState()
        let initialApps = [
            mruRunningApp(appID: "app.alpha", pid: 101, launchedAt: 2),
            mruRunningApp(appID: "app.beta", pid: 202, launchedAt: 1)
        ]
        XCTAssertEqual(
            state.prepareForRanking(
                runningApplications: initialApps,
                frontmostAppID: "app.alpha",
                fallbackRankByPID: [:]
            ),
            .bootstrap
        )

        XCTAssertEqual(state.recordLaunch(appID: "app.gamma", isCurrentProcess: false), .launch)
        XCTAssertEqual(state.orderedAppIDs, ["app.alpha", "app.beta", "app.gamma"])
        XCTAssertEqual(
            state.recordActivation(appID: "app.gamma", isCurrentProcess: false),
            .activation
        )
        XCTAssertEqual(state.orderedAppIDs, ["app.gamma", "app.alpha", "app.beta"])

        let withSecondGammaProcess = initialApps + [
            mruRunningApp(appID: "app.gamma", pid: 303, launchedAt: 3),
            mruRunningApp(appID: "app.gamma", pid: 304, launchedAt: 4)
        ]
        let rankByPID = state.rankByPID(for: withSecondGammaProcess)
        XCTAssertEqual(rankByPID[303], 0)
        XCTAssertEqual(rankByPID[304], 0)

        XCTAssertNil(
            state.recordTermination(
                appID: "app.gamma",
                isCurrentProcess: false,
                hasRemainingProcess: true
            )
        )
        XCTAssertEqual(
            state.recordTermination(
                appID: "app.beta",
                isCurrentProcess: false,
                hasRemainingProcess: false
            ),
            .termination
        )
        XCTAssertEqual(state.orderedAppIDs, ["app.gamma", "app.alpha"])
    }

    func testSystemAppMRUStateFilteringPreservesCanonicalRelativeOrder() {
        var state = SystemAppMRUState()
        let allApps = [
            mruRunningApp(appID: "app.one", pid: 11, launchedAt: 1),
            mruRunningApp(appID: "app.hidden", pid: 22, launchedAt: 2),
            mruRunningApp(appID: "app.three", pid: 33, launchedAt: 3)
        ]
        XCTAssertEqual(
            state.reconcileSystemOrder(
                ["app.one", "app.hidden", "app.three"],
                runningApplications: allApps
            ),
            .systemOrder
        )
        let visibleApps = [
            mruRunningApp(appID: "app.one", pid: 11, launchedAt: 1),
            mruRunningApp(appID: "app.three", pid: 33, launchedAt: 3)
        ]

        let rankByPID = state.rankByPID(for: visibleApps)

        XCTAssertEqual(rankByPID[11], 0)
        XCTAssertEqual(rankByPID[33], 1)
        XCTAssertEqual(state.orderedAppIDs, ["app.one", "app.hidden", "app.three"])
    }

    func testSystemAppMRULegacyPersistenceRemovesPreviousProcessState() throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        let legacyDirectoryURL = temporaryDirectoryURL
            .appendingPathComponent("FlowTab/runtime", isDirectory: true)
        try FileManager.default.createDirectory(
            at: legacyDirectoryURL,
            withIntermediateDirectories: true
        )
        let legacyFileURL = legacyDirectoryURL.appendingPathComponent(
            "system-app-mru-Flow_Tab_UITest.json"
        )
        try Data("legacy".utf8).write(to: legacyFileURL)

        try SystemAppMRULegacyPersistence.removePersistedState(
            applicationSupportDirectoryURL: temporaryDirectoryURL,
            installationURL: URL(fileURLWithPath: "/Applications/Flow Tab UITest.app")
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyFileURL.path))
    }

    func testSystemAppMRUTrackerStartsFreshForEachProcessSession() {
        let firstSession = SystemAppMRUTracker()
        firstSession.recordActivation(appID: "app.one")
        XCTAssertEqual(firstSession.trackedAppIDOrder(), ["app.one"])

        let nextSession = SystemAppMRUTracker()

        XCTAssertEqual(nextSession.trackedAppIDOrder(), [])
        XCTAssertTrue(nextSession.requiresBootstrapFallback())
    }

    @MainActor
    func testSystemAppMRUTrackerKeepsKnownOrderWhenFallbackSampleChanges() throws {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let candidateApps = NSWorkspace.shared.runningApplications.filter { app in
            app.processIdentifier != currentPID
                && app.processIdentifier != frontmostPID
                && app.activationPolicy == .regular
                && !app.isTerminated
                && app.bundleIdentifier != nil
        }

        guard candidateApps.count >= 2 else {
            throw XCTSkip("Two background regular applications are required for MRU fallback coverage.")
        }

        let apps = Array(candidateApps.prefix(2))
        let firstPID = apps[0].processIdentifier
        let secondPID = apps[1].processIdentifier
        let tracker = SystemAppMRUTracker()

        let initialRanks = tracker.rankByPID(
            for: apps,
            fallbackRankByPID: [firstPID: 0, secondPID: 1]
        )
        let refreshedRanks = tracker.rankByPID(
            for: apps,
            fallbackRankByPID: [firstPID: 1, secondPID: 0]
        )

        XCTAssertEqual(
            orderedPIDs(apps: apps, rankByPID: refreshedRanks),
            orderedPIDs(apps: apps, rankByPID: initialRanks),
            "Maintenance fallback samples must not reorder applications without an application event."
        )
    }

    @MainActor
    func testRuntimeSystemAppOrderProviderResolvesRegularRunningApplications() throws {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSWorkspace.shared.runningApplications.filter { app in
            app.processIdentifier != currentPID
                && app.activationPolicy == .regular
                && !app.isTerminated
        }
        guard !runningApps.isEmpty else {
            throw XCTSkip("A regular running application is required for system order coverage.")
        }

        let orderedPIDs = try XCTUnwrap(
            RuntimeSystemAppOrderProvider.collectOrderedPIDs(for: runningApps)
        )
        XCTAssertFalse(orderedPIDs.isEmpty)
        XCTAssertTrue(Set(orderedPIDs).isSubset(of: Set(runningApps.map(\.processIdentifier))))
    }

    private func orderedPIDs(
        apps: [NSRunningApplication],
        rankByPID: [pid_t: Int]
    ) -> [pid_t] {
        apps
            .map(\.processIdentifier)
            .sorted { lhs, rhs in
                let lhsRank = rankByPID[lhs] ?? Int.max
                let rhsRank = rankByPID[rhs] ?? Int.max
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs < rhs
            }
    }

    private func mruRunningApp(
        appID: String,
        pid: pid_t,
        launchedAt: TimeInterval,
        isCurrentProcess: Bool = false
    ) -> SystemAppMRURunningApplication {
        SystemAppMRURunningApplication(
            appID: appID,
            pid: pid,
            launchDate: Date(timeIntervalSince1970: launchedAt),
            isCurrentProcess: isCurrentProcess
        )
    }
}
