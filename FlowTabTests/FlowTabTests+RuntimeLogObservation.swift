import Combine
import Foundation
import XCTest
@testable import FlowTab

private enum RuntimeLogObservationWatchdogPolicy {
    static let eventDelivery: TimeInterval = 1
}

extension FlowTabTests {
    func testRuntimeLogObservationWatchdogPolicyPreservesEventDeliveryBound() {
        let eventDelivery =
            RuntimeLogObservationWatchdogPolicy.eventDelivery

        XCTAssertEqual(eventDelivery, 1)
        XCTAssertTrue(eventDelivery.isFinite)
        XCTAssertGreaterThan(eventDelivery, 0)
    }

    func testRuntimeLogStorePublishesMonotonicChangesAndCancelsObservation()
        async throws
    {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent(
                "FlowTabLogObservation-\(UUID().uuidString)",
                isDirectory: true
            )
        let logsDirectory = temporaryRoot
            .appendingPathComponent("FlowTab/logs", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let store = RuntimeLogFileStore(logsDirectoryURL: logsDirectory)
        let recorder = RuntimeLogChangeRecorder()
        let changesPublished = expectation(
            description:
                "unmetCondition=runtimeLogChangesPublished "
                + "expectedKinds=appended,flushed,cleared"
        )
        changesPublished.expectedFulfillmentCount = 3
        let observation = store.observeChanges { change in
            recorder.record(change)
            changesPublished.fulfill()
        }

        XCTAssertEqual(observation.baselineGeneration, 0)
        store.append("[00:00:00.000] [INFO] [UnitTest] first")
        _ = await store.readRecentLines(limit: 10, minimumLevel: .debug)
        let clearChange = try await store.clearAndWait()
        await fulfillment(
            of: [changesPublished],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )

        let observedChanges = recorder.changes
        XCTAssertEqual(
            observedChanges,
            [
                RuntimeLogChange(generation: 1, kind: .appended),
                RuntimeLogChange(generation: 2, kind: .flushed),
                RuntimeLogChange(generation: 3, kind: .cleared)
            ],
            "unmetCondition=orderedRuntimeLogChanges "
                + "finalChanges=\(observedChanges)"
        )
        XCTAssertEqual(clearChange, observedChanges.last)

        observation.cancel()
        store.append("[00:00:00.001] [INFO] [UnitTest] after-cancel")
        _ = await store.readRecentLines(limit: 10, minimumLevel: .debug)
        XCTAssertEqual(recorder.changes.count, 3)
    }

    @MainActor
    func testRuntimeLogViewModelUsesFullThenIncrementalReadsAcrossActivations()
        async
    {
        let source = ControlledRuntimeLogLinesSource()
        let viewModel = RuntimeLogLinesViewModel(diagnostics: source)
        var cancellables: Set<AnyCancellable> = []

        viewModel.updateActivity(
            isActive: false,
            minimumLevel: .warning
        )
        await Task.yield()

        XCTAssertFalse(source.hasObserver)
        XCTAssertTrue(source.readRequests.isEmpty)

        let firstReadRequested = expectation(
            description: "unmetCondition=firstActiveRuntimeLogReadRequested"
        )
        let secondReadRequested = expectation(
            description: "unmetCondition=secondActiveRuntimeLogReadRequested"
        )
        source.onReadRequested = { requestCount in
            if requestCount == 1 {
                firstReadRequested.fulfill()
            } else if requestCount == 2 {
                secondReadRequested.fulfill()
            }
        }

        viewModel.updateActivity(
            isActive: true,
            minimumLevel: .warning
        )
        await fulfillment(
            of: [firstReadRequested],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )

        XCTAssertTrue(source.hasObserver)
        XCTAssertEqual(
            source.readRequests,
            [
                RuntimeLogReadRequest(
                    limit: DiagnosticsRefreshPolicy.runtimeLogs.lineLimit,
                    minimumLevel: .warning,
                    usesSnapshot: false
                )
            ]
        )

        viewModel.updateActivity(
            isActive: true,
            minimumLevel: .warning
        )
        await Task.yield()
        XCTAssertEqual(source.readRequestCount, 1)

        let firstActiveLinesApplied = expectation(
            description: "unmetCondition=firstActiveRuntimeLogLinesApplied"
        )
        viewModel.$lines
            .filter { $0 == ["first-active"] }
            .prefix(1)
            .sink { _ in firstActiveLinesApplied.fulfill() }
            .store(in: &cancellables)
        source.completeNextRead(with: ["first-active"])
        await fulfillment(
            of: [firstActiveLinesApplied],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )
        XCTAssertEqual(viewModel.lines, ["first-active"])

        viewModel.updateActivity(
            isActive: false,
            minimumLevel: .warning
        )
        XCTAssertFalse(source.hasObserver)

        source.emit(RuntimeLogChange(generation: 1, kind: .flushed))
        await Task.yield()
        XCTAssertEqual(source.readRequestCount, 1)

        viewModel.updateActivity(
            isActive: true,
            minimumLevel: .warning
        )
        await fulfillment(
            of: [secondReadRequested],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )

        XCTAssertEqual(
            source.readRequests,
            [
                RuntimeLogReadRequest(
                    limit: DiagnosticsRefreshPolicy.runtimeLogs.lineLimit,
                    minimumLevel: .warning,
                    usesSnapshot: false
                ),
                RuntimeLogReadRequest(
                    limit: DiagnosticsRefreshPolicy.runtimeLogs.lineLimit,
                    minimumLevel: .warning,
                    usesSnapshot: true
                )
            ]
        )

        let secondActiveLinesApplied = expectation(
            description: "unmetCondition=secondActiveRuntimeLogLinesApplied"
        )
        viewModel.$lines
            .filter { $0 == ["first-active", "second-active"] }
            .prefix(1)
            .sink { _ in secondActiveLinesApplied.fulfill() }
            .store(in: &cancellables)
        source.completeNextRead(with: ["second-active"])
        await fulfillment(
            of: [secondActiveLinesApplied],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )
        XCTAssertEqual(
            viewModel.lines,
            ["first-active", "second-active"]
        )

        viewModel.updateActivity(
            isActive: false,
            minimumLevel: .warning
        )
    }

    @MainActor
    func testRuntimeLogViewModelInvalidatesInflightReadAfterDeactivation()
        async
    {
        let source = ControlledRuntimeLogLinesSource()
        let viewModel = RuntimeLogLinesViewModel(diagnostics: source)
        let firstReadRequested = expectation(
            description: "unmetCondition=runtimeLogReadRequestedBeforeDeactivation"
        )
        let secondReadRequested = expectation(
            description: "unmetCondition=runtimeLogReadRequestedAfterReactivation"
        )
        source.onReadRequested = { requestCount in
            if requestCount == 1 {
                firstReadRequested.fulfill()
            } else if requestCount == 2 {
                secondReadRequested.fulfill()
            }
        }

        var publishedLines: [[String]] = []
        var cancellables: Set<AnyCancellable> = []
        let freshLinesApplied = expectation(
            description: "unmetCondition=reactivatedRuntimeLogLinesApplied"
        )
        viewModel.$lines
            .dropFirst()
            .sink { lines in
                publishedLines.append(lines)
                if lines == ["fresh-after-reactivation"] {
                    freshLinesApplied.fulfill()
                }
            }
            .store(in: &cancellables)

        viewModel.updateActivity(isActive: true, minimumLevel: .error)
        await fulfillment(
            of: [firstReadRequested],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )

        viewModel.updateActivity(isActive: false, minimumLevel: .error)
        source.completeNextRead(with: ["cancelled-while-hidden"])
        viewModel.updateActivity(isActive: true, minimumLevel: .error)
        await fulfillment(
            of: [secondReadRequested],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )

        source.completeNextRead(with: ["fresh-after-reactivation"])
        await fulfillment(
            of: [freshLinesApplied],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )

        XCTAssertFalse(publishedLines.contains(["cancelled-while-hidden"]))
        XCTAssertEqual(viewModel.lines, ["fresh-after-reactivation"])
        viewModel.updateActivity(isActive: false, minimumLevel: .error)
    }

    @MainActor
    func testRuntimeLogViewModelReloadsLevelOnlyWhileActive()
        async
    {
        let source = ControlledRuntimeLogLinesSource()
        let viewModel = RuntimeLogLinesViewModel(diagnostics: source)
        let errorReadRequested = expectation(
            description: "unmetCondition=activeErrorRuntimeLogReadRequested"
        )
        let debugReadRequested = expectation(
            description: "unmetCondition=activeDebugRuntimeLogReadRequested"
        )
        source.onReadRequested = { requestCount in
            if requestCount == 1 {
                errorReadRequested.fulfill()
            } else if requestCount == 2 {
                debugReadRequested.fulfill()
            }
        }

        viewModel.updateActivity(isActive: false, minimumLevel: .warning)
        viewModel.updateActivity(isActive: false, minimumLevel: .error)
        await Task.yield()
        XCTAssertTrue(source.readRequests.isEmpty)

        viewModel.updateActivity(isActive: true, minimumLevel: .error)
        await fulfillment(
            of: [errorReadRequested],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )
        XCTAssertEqual(source.readRequests.last?.minimumLevel, .error)
        source.completeNextRead(with: ["error"])
        await Task.yield()

        viewModel.updateActivity(isActive: true, minimumLevel: .debug)
        await fulfillment(
            of: [debugReadRequested],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )
        XCTAssertEqual(source.readRequests.last?.minimumLevel, .debug)
        source.completeNextRead(with: ["debug"])

        viewModel.updateActivity(isActive: false, minimumLevel: .debug)
        viewModel.updateActivity(isActive: false, minimumLevel: .info)
        await Task.yield()
        XCTAssertEqual(source.readRequestCount, 2)
    }

    @MainActor
    func testRuntimeLogViewModelPresentsLatestConfiguredLineLimitAfterReentry()
        async throws
    {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent(
                "FlowTabLogLatestProjection-\(UUID().uuidString)",
                isDirectory: true
            )
        let logsDirectory = temporaryRoot
            .appendingPathComponent("FlowTab/logs", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let store = RuntimeLogFileStore(logsDirectoryURL: logsDirectory)
        let diagnostics = RuntimeDiagnostics(fileStore: store)
        let lineLimit = DiagnosticsRefreshPolicy.runtimeLogs.lineLimit

        for index in 1...(lineLimit + 5) {
            store.append(
                "[00:00:00.000] [DEBUG] [UnitTest] filtered-"
                    + String(format: "%03d", index)
            )
            store.append(
                "[00:00:00.000] [INFO] [UnitTest] marker-"
                    + String(format: "%03d", index)
            )
        }
        _ = await store.readRecentLines(limit: 1, minimumLevel: .debug)

        let viewModel = RuntimeLogLinesViewModel(diagnostics: diagnostics)
        var cancellables: Set<AnyCancellable> = []
        let firstProjectionApplied = expectation(
            description: "unmetCondition=firstLatestRuntimeLogProjectionApplied"
        )
        viewModel.$lines
            .filter {
                $0.count == lineLimit
                    && $0.first?.contains("marker-006") == true
                    && $0.last?.contains("marker-305") == true
            }
            .prefix(1)
            .sink { _ in firstProjectionApplied.fulfill() }
            .store(in: &cancellables)
        viewModel.updateActivity(isActive: true, minimumLevel: .info)
        await fulfillment(
            of: [firstProjectionApplied],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )
        XCTAssertEqual(viewModel.lines.count, lineLimit)

        viewModel.updateActivity(isActive: false, minimumLevel: .info)
        store.append("[00:00:00.001] [DEBUG] [UnitTest] filtered-306")
        store.append("[00:00:00.001] [INFO] [UnitTest] marker-306")
        _ = await store.readRecentLines(limit: 1, minimumLevel: .debug)
        let secondProjectionApplied = expectation(
            description: "unmetCondition=secondLatestRuntimeLogProjectionApplied"
        )
        viewModel.$lines
            .filter {
                $0.count == lineLimit
                    && $0.first?.contains("marker-007") == true
                    && $0.last?.contains("marker-306") == true
            }
            .prefix(1)
            .sink { _ in secondProjectionApplied.fulfill() }
            .store(in: &cancellables)
        viewModel.updateActivity(isActive: true, minimumLevel: .info)
        await fulfillment(
            of: [secondProjectionApplied],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )
        XCTAssertEqual(viewModel.lines.count, lineLimit)

        viewModel.updateActivity(isActive: false, minimumLevel: .info)
    }

    @MainActor
    func testRuntimeLogViewModelAppliesInitialAppendAndClearEvidence()
        async throws
    {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent(
                "FlowTabLogViewModel-\(UUID().uuidString)",
                isDirectory: true
            )
        let logsDirectory = temporaryRoot
            .appendingPathComponent("FlowTab/logs", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let store = RuntimeLogFileStore(logsDirectoryURL: logsDirectory)
        let diagnostics = RuntimeDiagnostics(fileStore: store)
        let initialMarker = "initial-\(UUID().uuidString)"
        let appendedMarker = "appended-\(UUID().uuidString)"
        let postClearMarker = "post-clear-\(UUID().uuidString)"
        store.append("[00:00:00.000] [INFO] [UnitTest] \(initialMarker)")
        _ = await store.readRecentLines(limit: 10, minimumLevel: .debug)

        let viewModel = RuntimeLogLinesViewModel(diagnostics: diagnostics)
        var cancellables: Set<AnyCancellable> = []
        let initialApplied = expectation(
            description: "unmetCondition=initialRuntimeLogSnapshotApplied"
        )
        viewModel.$lines
            .filter { $0.contains(where: { $0.contains(initialMarker) }) }
            .prefix(1)
            .sink { _ in initialApplied.fulfill() }
            .store(in: &cancellables)

        viewModel.updateActivity(isActive: true, minimumLevel: .debug)
        await fulfillment(
            of: [initialApplied],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )
        XCTAssertTrue(
            viewModel.lines.contains(where: { $0.contains(initialMarker) }),
            "unmetCondition=initialRuntimeLogMarkerVisible "
                + "marker=\(initialMarker) finalLines=\(viewModel.lines)"
        )

        let appendApplied = expectation(
            description: "unmetCondition=appendedRuntimeLogMarkerApplied"
        )
        viewModel.$lines
            .filter { $0.contains(where: { $0.contains(appendedMarker) }) }
            .prefix(1)
            .sink { _ in appendApplied.fulfill() }
            .store(in: &cancellables)
        store.append("[00:00:00.001] [WARN] [UnitTest] \(appendedMarker)")
        await fulfillment(
            of: [appendApplied],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )
        XCTAssertTrue(
            viewModel.lines.contains(where: { $0.contains(appendedMarker) }),
            "unmetCondition=appendedRuntimeLogMarkerVisible "
                + "marker=\(appendedMarker) finalLines=\(viewModel.lines)"
        )

        await viewModel.clearStoredLogs(minimumLevel: .debug)
        XCTAssertTrue(viewModel.lines.isEmpty)

        let postClearApplied = expectation(
            description:
                "unmetCondition=postClearRuntimeLogMarkerApplied"
        )
        viewModel.$lines
            .filter { $0.contains(where: { $0.contains(postClearMarker) }) }
            .prefix(1)
            .sink { _ in postClearApplied.fulfill() }
            .store(in: &cancellables)
        store.append("[00:00:00.002] [ERROR] [UnitTest] \(postClearMarker)")
        await fulfillment(
            of: [postClearApplied],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )
        XCTAssertTrue(
            viewModel.lines.contains(where: { $0.contains(postClearMarker) }),
            "unmetCondition=postClearRuntimeLogMarkerVisible "
                + "marker=\(postClearMarker) finalLines=\(viewModel.lines)"
        )

        viewModel.updateActivity(isActive: false, minimumLevel: .debug)
    }

    @MainActor
    func testRuntimeLogViewModelRejectsStaleDuplicateAndCancelledEvidence()
        async
    {
        let source = ControlledRuntimeLogLinesSource()
        let viewModel = RuntimeLogLinesViewModel(diagnostics: source)
        let firstReadRequested = expectation(
            description:
                "unmetCondition=initialRuntimeLogReadRequestedAfterSubscription"
        )
        let laterReadRequested = expectation(
            description:
                "unmetCondition=laterRuntimeLogGenerationReadRequested"
        )
        source.onReadRequested = { requestCount in
            if requestCount == 1 {
                XCTAssertTrue(source.hasObserver)
                firstReadRequested.fulfill()
            } else if requestCount == 2 {
                laterReadRequested.fulfill()
            }
        }

        var publishedLines: [[String]] = []
        var cancellables: Set<AnyCancellable> = []
        let freshLinesApplied = expectation(
            description: "unmetCondition=freshRuntimeLogReadApplied"
        )
        viewModel.$lines
            .dropFirst()
            .sink { lines in
                publishedLines.append(lines)
                if lines == ["fresh"] {
                    freshLinesApplied.fulfill()
                }
            }
            .store(in: &cancellables)

        viewModel.updateActivity(isActive: true, minimumLevel: .debug)
        await fulfillment(
            of: [firstReadRequested],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )
        XCTAssertEqual(
            source.readRequestCount,
            1,
            "unmetCondition=initialRuntimeLogReadRequested "
                + "finalReadRequestCount=\(source.readRequestCount) "
                + "hasObserver=\(source.hasObserver)"
        )

        source.emit(RuntimeLogChange(generation: 1, kind: .appended))
        await Task.yield()
        XCTAssertEqual(source.readRequestCount, 1)

        source.emit(RuntimeLogChange(generation: 2, kind: .flushed))
        source.completeNextRead(with: ["stale"])
        await fulfillment(
            of: [laterReadRequested],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )
        XCTAssertEqual(
            source.readRequestCount,
            2,
            "unmetCondition=laterRuntimeLogReadRequested "
                + "finalReadRequestCount=\(source.readRequestCount) "
                + "hasObserver=\(source.hasObserver)"
        )
        source.completeNextRead(with: ["fresh"], mode: .full)
        await fulfillment(
            of: [freshLinesApplied],
            timeout: RuntimeLogObservationWatchdogPolicy.eventDelivery
        )

        XCTAssertFalse(
            publishedLines.contains(["stale"]),
            "unmetCondition=staleRuntimeLogReadRejected "
                + "finalPublishedLines=\(publishedLines)"
        )
        XCTAssertEqual(
            viewModel.lines,
            ["fresh"],
            "unmetCondition=freshRuntimeLogReadVisible "
                + "finalLines=\(viewModel.lines)"
        )
        XCTAssertEqual(source.readRequestCount, 2)

        source.emit(RuntimeLogChange(generation: 2, kind: .flushed))
        source.emit(RuntimeLogChange(generation: 3, kind: .appended))
        await Task.yield()
        XCTAssertEqual(source.readRequestCount, 2)

        viewModel.updateActivity(isActive: false, minimumLevel: .debug)
        XCTAssertFalse(source.hasObserver)
        source.emit(RuntimeLogChange(generation: 4, kind: .flushed))
        await Task.yield()
        XCTAssertEqual(source.readRequestCount, 2)
    }

    @MainActor
    func testRuntimeLogViewModelKeepsOneReadAcrossOneHundredActivityCycles()
        async
    {
        let source = ControlledRuntimeLogLinesSource()
        let viewModel = RuntimeLogLinesViewModel(diagnostics: source)
        let firstReadRequested = expectation(
            description: "unmetCondition=firstLifecycleReadRequested"
        )
        let replacementReadRequested = expectation(
            description: "unmetCondition=replacementLifecycleReadRequested"
        )
        source.onReadRequested = { requestCount in
            if requestCount == 1 {
                firstReadRequested.fulfill()
            } else if requestCount == 2 {
                replacementReadRequested.fulfill()
            }
        }

        viewModel.updateActivity(isActive: true, minimumLevel: .debug)
        await fulfillment(of: [firstReadRequested], timeout: 1)

        for _ in 0..<100 {
            viewModel.updateActivity(isActive: false, minimumLevel: .debug)
            viewModel.updateActivity(isActive: true, minimumLevel: .debug)
        }
        await Task.yield()
        XCTAssertEqual(source.readRequestCount, 1)
        XCTAssertEqual(source.pendingReadCount, 1)

        source.completeNextRead(with: ["cancelled-owner"])
        await fulfillment(of: [replacementReadRequested], timeout: 1)
        XCTAssertEqual(source.pendingReadCount, 1)
        source.completeNextRead(with: ["current-owner"])
        await Task.yield()
        XCTAssertEqual(viewModel.lines, ["current-owner"])

        viewModel.updateActivity(isActive: false, minimumLevel: .debug)
    }

    @MainActor
    func testRuntimeLogViewModelDefersCachedCatchUpUntilReentrySettles()
        async
    {
        let source = ControlledRuntimeLogLinesSource()
        let viewModel = RuntimeLogLinesViewModel(
            diagnostics: source,
            refreshPolicy: DiagnosticsRefreshPolicy(
                lineLimit: 300,
                cachedReadDelayNanoseconds: 50_000_000
            )
        )
        let initialReadRequested = expectation(
            description: "unmetCondition=initialCachedRuntimeLogReadRequested"
        )
        let settledReadRequested = expectation(
            description: "unmetCondition=settledRuntimeLogReadRequested"
        )
        source.onReadRequested = { requestCount in
            if requestCount == 1 {
                initialReadRequested.fulfill()
            } else if requestCount == 2 {
                settledReadRequested.fulfill()
            }
        }

        viewModel.updateActivity(isActive: true, minimumLevel: .debug)
        await fulfillment(of: [initialReadRequested], timeout: 1)
        source.completeNextRead(with: ["cached"])
        await Task.yield()
        viewModel.updateActivity(isActive: false, minimumLevel: .debug)
        source.emit(RuntimeLogChange(generation: 1, kind: .flushed))

        for _ in 0..<100 {
            viewModel.updateActivity(isActive: true, minimumLevel: .debug)
            viewModel.updateActivity(isActive: false, minimumLevel: .debug)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(source.readRequestCount, 1)

        viewModel.updateActivity(isActive: true, minimumLevel: .debug)
        await fulfillment(of: [settledReadRequested], timeout: 1)
        source.completeNextRead(with: ["fresh"])
        await Task.yield()
        XCTAssertEqual(viewModel.lines, ["cached", "fresh"])
        viewModel.updateActivity(isActive: false, minimumLevel: .debug)
    }

    @MainActor
    func testRuntimeLogViewModelRetainsLastValidLinesAfterReadFailure()
        async
    {
        let source = ControlledRuntimeLogLinesSource()
        let viewModel = RuntimeLogLinesViewModel(diagnostics: source)
        let firstReadRequested = expectation(
            description: "unmetCondition=initialValidReadRequested"
        )
        let failingReadRequested = expectation(
            description: "unmetCondition=failingIncrementalReadRequested"
        )
        source.onReadRequested = { requestCount in
            if requestCount == 1 {
                firstReadRequested.fulfill()
            } else if requestCount == 2 {
                failingReadRequested.fulfill()
            }
        }

        viewModel.updateActivity(isActive: true, minimumLevel: .info)
        await fulfillment(of: [firstReadRequested], timeout: 1)
        source.completeNextRead(with: ["last-valid"])
        await Task.yield()
        XCTAssertEqual(viewModel.lines, ["last-valid"])

        source.emit(RuntimeLogChange(generation: 1, kind: .flushed))
        await fulfillment(of: [failingReadRequested], timeout: 1)
        source.failNextRead()
        await Task.yield()
        XCTAssertEqual(viewModel.lines, ["last-valid"])

        viewModel.updateActivity(isActive: false, minimumLevel: .info)
    }
}

private final class RuntimeLogChangeRecorder {
    private let lock = NSLock()
    private var storage: [RuntimeLogChange] = []

    var changes: [RuntimeLogChange] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ change: RuntimeLogChange) {
        lock.lock()
        storage.append(change)
        lock.unlock()
    }
}

private final class ControlledRuntimeLogLinesSource:
    RuntimeLogLinesProviding
{
    var onReadRequested: ((Int) -> Void)?
    private(set) var readRequests: [RuntimeLogReadRequest] = []

    var readRequestCount: Int {
        readRequests.count
    }

    var pendingReadCount: Int {
        pendingReads.count
    }

    private let observerBox = RuntimeLogObserverBox()
    private struct PendingRead {
        let continuation:
            CheckedContinuation<RuntimeLogReadBatch, Error>
        let requestGeneration: UInt64
        let requestedSnapshot:
            RuntimeLogFileStore.ReadSnapshot?
    }

    private var pendingReads: [PendingRead] = []
    private var generation: UInt64 = 0
    private var snapshotOffset = 0

    var hasObserver: Bool {
        observerBox.hasObserver
    }

    func observeChanges(
        kinds: Set<RuntimeLogChangeKind>,
        _ observer: @escaping (RuntimeLogChange) -> Void
    ) -> RuntimeLogChangeObservation {
        observerBox.install(kinds: kinds, observer)
        return RuntimeLogChangeObservation(
            baselineGeneration: generation
        ) { [observerBox] in
            observerBox.cancel()
        }
    }

    func readRecentBatch(
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        since snapshot: RuntimeLogFileStore.ReadSnapshot?
    ) async throws -> RuntimeLogReadBatch {
        readRequests.append(
            RuntimeLogReadRequest(
                limit: limit,
                minimumLevel: minimumLevel,
                usesSnapshot: snapshot != nil
            )
        )
        onReadRequested?(readRequestCount)
        return try await withCheckedThrowingContinuation { continuation in
            pendingReads.append(
                PendingRead(
                    continuation: continuation,
                    requestGeneration: generation,
                    requestedSnapshot: snapshot
                )
            )
        }
    }

    func clearAndWait() async throws -> RuntimeLogChange {
        generation &+= 1
        let change = RuntimeLogChange(
            generation: generation,
            kind: .cleared
        )
        observerBox.emit(change)
        return change
    }

    func emit(_ change: RuntimeLogChange) {
        generation = max(generation, change.generation)
        observerBox.emit(change)
    }

    func completeNextRead(
        with lines: [String],
        mode: RuntimeLogReadMode? = nil
    ) {
        guard !pendingReads.isEmpty else {
            return XCTFail("Missing pending runtime-log read")
        }
        let pendingRead = pendingReads.removeFirst()
        snapshotOffset += 1
        pendingRead.continuation.resume(
            returning: RuntimeLogReadBatch(
                lines: lines,
                snapshot: RuntimeLogFileStore.ReadSnapshot(
                    fileOffsetsByPath: ["controlled.log": snapshotOffset],
                    storageEpoch: 0
                ),
                coveredChangeGeneration:
                    pendingRead.requestGeneration,
                mode: mode
                    ?? (pendingRead.requestedSnapshot == nil
                        ? .full
                        : .incremental)
            )
        )
    }

    func failNextRead() {
        guard !pendingReads.isEmpty else {
            return XCTFail("Missing pending runtime-log read")
        }
        pendingReads.removeFirst().continuation.resume(
            throwing: ControlledRuntimeLogReadError.failed
        )
    }
}

private enum ControlledRuntimeLogReadError: Error {
    case failed
}

private struct RuntimeLogReadRequest: Equatable {
    let limit: Int
    let minimumLevel: RuntimeLogLevel
    let usesSnapshot: Bool
}

private final class RuntimeLogObserverBox {
    private let lock = NSLock()
    private var observer: ((RuntimeLogChange) -> Void)?
    private var observedKinds: Set<RuntimeLogChangeKind> = []

    var hasObserver: Bool {
        lock.lock()
        defer { lock.unlock() }
        return observer != nil
    }

    func install(
        kinds: Set<RuntimeLogChangeKind>,
        _ observer: @escaping (RuntimeLogChange) -> Void
    ) {
        lock.lock()
        observedKinds = kinds
        self.observer = observer
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        observer = nil
        observedKinds = []
        lock.unlock()
    }

    func emit(_ change: RuntimeLogChange) {
        lock.lock()
        let callback = observedKinds.contains(change.kind)
            ? observer
            : nil
        lock.unlock()
        callback?(change)
    }
}
