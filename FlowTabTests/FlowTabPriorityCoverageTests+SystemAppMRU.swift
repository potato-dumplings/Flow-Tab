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

    func testSystemAppMRUStateRestoresAppIDOrderAcrossNewProcessIdentifiers() {
        let snapshot = SystemAppMRUSnapshot(
            generation: 7,
            orderedAppIDs: ["app.previous", "app.current", "app.stale"],
            source: .activation,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        var state = SystemAppMRUState(snapshot: snapshot)
        let relaunchedApps = [
            mruRunningApp(appID: "app.current", pid: 1_001, launchedAt: 20),
            mruRunningApp(appID: "app.previous", pid: 2_002, launchedAt: 10)
        ]

        XCTAssertEqual(
            state.prepareForRanking(
                runningApplications: relaunchedApps,
                frontmostAppID: nil,
                fallbackRankByPID: [1_001: 0, 2_002: 1]
            ),
            .restoreReconciliation
        )
        let rankByPID = state.rankByPID(for: relaunchedApps)

        XCTAssertEqual(state.orderedAppIDs, ["app.previous", "app.current"])
        XCTAssertEqual(rankByPID[2_002], 0)
        XCTAssertEqual(rankByPID[1_001], 1)
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
        let snapshot = SystemAppMRUSnapshot(
            generation: 3,
            orderedAppIDs: ["app.one", "app.hidden", "app.three"],
            source: .activation,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let state = SystemAppMRUState(snapshot: snapshot)
        let visibleApps = [
            mruRunningApp(appID: "app.one", pid: 11, launchedAt: 1),
            mruRunningApp(appID: "app.three", pid: 33, launchedAt: 3)
        ]

        let rankByPID = state.rankByPID(for: visibleApps)

        XCTAssertEqual(rankByPID[11], 0)
        XCTAssertEqual(rankByPID[33], 1)
        XCTAssertEqual(state.orderedAppIDs, ["app.one", "app.hidden", "app.three"])
    }

    func testSystemAppMRUFileStateStoreRoundTripsAndCorruptDataRequiresRecovery() throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = temporaryDirectoryURL.appendingPathComponent("mru.json")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        let store = SystemAppMRUFileStateStore(fileURL: fileURL)
        let snapshot = SystemAppMRUSnapshot(
            generation: 9,
            orderedAppIDs: ["app.two", "app.one"],
            source: .activation,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        try store.save(snapshot)
        XCTAssertEqual(try store.load(), snapshot)

        try Data("{invalid".utf8).write(to: fileURL, options: .atomic)
        XCTAssertThrowsError(try store.load())
    }

    func testSystemAppMRUTrackerPersistsActivationAndReloadsCanonicalOrder() {
        let initialSnapshot = SystemAppMRUSnapshot(
            generation: 4,
            orderedAppIDs: ["app.one", "app.two"],
            source: .bootstrap,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let store = InMemorySystemAppMRUStateStore(snapshot: initialSnapshot)
        let firstTracker = SystemAppMRUTracker(stateStore: store)

        firstTracker.recordActivation(appID: "app.two")

        XCTAssertEqual(store.snapshot?.orderedAppIDs, ["app.two", "app.one"])
        XCTAssertEqual(store.snapshot?.generation, 5)
        let relaunchedTracker = SystemAppMRUTracker(stateStore: store)
        XCTAssertEqual(relaunchedTracker.trackedAppIDOrder(), ["app.two", "app.one"])
    }

    func testSystemAppMRUStateRejectsUnsupportedPersistenceSchema() {
        let snapshot = SystemAppMRUSnapshot(
            generation: 50,
            orderedAppIDs: ["app.old"],
            source: .activation,
            updatedAt: Date(timeIntervalSince1970: 100),
            schemaVersion: SystemAppMRUSnapshot.currentSchemaVersion + 1
        )

        let state = SystemAppMRUState(snapshot: snapshot)

        XCTAssertTrue(state.requiresBootstrapFallback)
        XCTAssertEqual(state.orderedAppIDs, [])
    }

    func testUITestLaunchOptionsResetMRUUnlessRelaunchPreservesIt() {
        let previousArguments = FlowTabTestLaunchOptions.argumentsOverrideForTesting
        let previousEnvironment = FlowTabTestLaunchOptions.environmentOverrideForTesting
        defer {
            FlowTabTestLaunchOptions.argumentsOverrideForTesting = previousArguments
            FlowTabTestLaunchOptions.environmentOverrideForTesting = previousEnvironment
        }
        FlowTabTestLaunchOptions.environmentOverrideForTesting = [
            FlowTabTestLaunchOptions.uiTestingEnvironmentKey:
                FlowTabTestLaunchOptions.uiTestingEnvironmentValue
        ]

        FlowTabTestLaunchOptions.argumentsOverrideForTesting = [
            "FlowTab",
            "--flowtab-ui-reset-defaults"
        ]
        XCTAssertTrue(FlowTabTestLaunchOptions.resetsSystemAppMRUOnLaunch)

        FlowTabTestLaunchOptions.argumentsOverrideForTesting = [
            "FlowTab",
            "--flowtab-ui-reset-defaults",
            "--flowtab-ui-preserve-system-app-mru"
        ]
        XCTAssertFalse(FlowTabTestLaunchOptions.resetsSystemAppMRUOnLaunch)
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

private final class InMemorySystemAppMRUStateStore: SystemAppMRUStatePersisting {
    var snapshot: SystemAppMRUSnapshot?

    init(snapshot: SystemAppMRUSnapshot?) {
        self.snapshot = snapshot
    }

    func load() throws -> SystemAppMRUSnapshot? {
        snapshot
    }

    func save(_ snapshot: SystemAppMRUSnapshot) throws {
        self.snapshot = snapshot
    }
}
