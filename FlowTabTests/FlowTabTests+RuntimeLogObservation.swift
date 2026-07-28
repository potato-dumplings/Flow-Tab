import Combine
import Foundation
import XCTest
@testable import FlowTab

extension FlowTabTests {
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
            description: "append, flush, and clear changes published"
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
        await fulfillment(of: [changesPublished], timeout: 1)

        XCTAssertEqual(
            recorder.changes,
            [
                RuntimeLogChange(generation: 1, kind: .appended),
                RuntimeLogChange(generation: 2, kind: .flushed),
                RuntimeLogChange(generation: 3, kind: .cleared)
            ]
        )
        XCTAssertEqual(clearChange, recorder.changes.last)

        observation.cancel()
        store.append("[00:00:00.001] [INFO] [UnitTest] after-cancel")
        _ = await store.readRecentLines(limit: 10, minimumLevel: .debug)
        XCTAssertEqual(recorder.changes.count, 3)
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
        let initialApplied = expectation(description: "initial snapshot applied")
        viewModel.$lines
            .filter { $0.contains(where: { $0.contains(initialMarker) }) }
            .prefix(1)
            .sink { _ in initialApplied.fulfill() }
            .store(in: &cancellables)

        viewModel.start(minimumLevel: .debug)
        await fulfillment(of: [initialApplied], timeout: 1)

        let appendApplied = expectation(description: "append event applied")
        viewModel.$lines
            .filter { $0.contains(where: { $0.contains(appendedMarker) }) }
            .prefix(1)
            .sink { _ in appendApplied.fulfill() }
            .store(in: &cancellables)
        store.append("[00:00:00.001] [WARN] [UnitTest] \(appendedMarker)")
        await fulfillment(of: [appendApplied], timeout: 1)

        await viewModel.clearStoredLogs(minimumLevel: .debug)
        XCTAssertTrue(viewModel.lines.isEmpty)

        let postClearApplied = expectation(
            description: "subscription remains active after clear"
        )
        viewModel.$lines
            .filter { $0.contains(where: { $0.contains(postClearMarker) }) }
            .prefix(1)
            .sink { _ in postClearApplied.fulfill() }
            .store(in: &cancellables)
        store.append("[00:00:00.002] [ERROR] [UnitTest] \(postClearMarker)")
        await fulfillment(of: [postClearApplied], timeout: 1)

        viewModel.stop()
    }

    @MainActor
    func testRuntimeLogViewModelRejectsStaleDuplicateAndCancelledEvidence()
        async
    {
        let source = ControlledRuntimeLogLinesSource()
        let viewModel = RuntimeLogLinesViewModel(diagnostics: source)
        let firstReadRequested = expectation(
            description: "initial read requested after subscription"
        )
        let laterReadRequested = expectation(
            description: "later generation requests another read"
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
        let freshLinesApplied = expectation(description: "fresh read applied")
        viewModel.$lines
            .dropFirst()
            .sink { lines in
                publishedLines.append(lines)
                if lines == ["fresh"] {
                    freshLinesApplied.fulfill()
                }
            }
            .store(in: &cancellables)

        viewModel.start(minimumLevel: .debug)
        await fulfillment(of: [firstReadRequested], timeout: 1)

        source.emit(RuntimeLogChange(generation: 1, kind: .appended))
        source.completeNextRead(with: ["stale"])
        await fulfillment(of: [laterReadRequested], timeout: 1)
        source.completeNextRead(with: ["fresh"])
        await fulfillment(of: [freshLinesApplied], timeout: 1)

        XCTAssertFalse(publishedLines.contains(["stale"]))
        XCTAssertEqual(viewModel.lines, ["fresh"])
        XCTAssertEqual(source.readRequestCount, 2)

        source.emit(RuntimeLogChange(generation: 1, kind: .flushed))
        source.emit(RuntimeLogChange(generation: 0, kind: .appended))
        await Task.yield()
        XCTAssertEqual(source.readRequestCount, 2)

        viewModel.stop()
        XCTAssertFalse(source.hasObserver)
        source.emit(RuntimeLogChange(generation: 2, kind: .appended))
        await Task.yield()
        XCTAssertEqual(source.readRequestCount, 2)
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
    private(set) var readRequestCount = 0

    private let observerBox = RuntimeLogObserverBox()
    private var pendingReads: [
        CheckedContinuation<[String], Never>
    ] = []
    private var generation: UInt64 = 0

    var hasObserver: Bool {
        observerBox.hasObserver
    }

    func observeChanges(
        _ observer: @escaping (RuntimeLogChange) -> Void
    ) -> RuntimeLogChangeObservation {
        observerBox.install(observer)
        return RuntimeLogChangeObservation(
            baselineGeneration: generation
        ) { [observerBox] in
            observerBox.cancel()
        }
    }

    func readRecentLines(
        limit _: Int,
        minimumLevel _: RuntimeLogLevel,
        since _: RuntimeLogFileStore.ReadSnapshot?
    ) async -> [String] {
        readRequestCount += 1
        onReadRequested?(readRequestCount)
        return await withCheckedContinuation { continuation in
            pendingReads.append(continuation)
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

    func completeNextRead(with lines: [String]) {
        guard !pendingReads.isEmpty else {
            return XCTFail("Missing pending runtime-log read")
        }
        pendingReads.removeFirst().resume(returning: lines)
    }
}

private final class RuntimeLogObserverBox {
    private let lock = NSLock()
    private var observer: ((RuntimeLogChange) -> Void)?

    var hasObserver: Bool {
        lock.lock()
        defer { lock.unlock() }
        return observer != nil
    }

    func install(_ observer: @escaping (RuntimeLogChange) -> Void) {
        lock.lock()
        self.observer = observer
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        observer = nil
        lock.unlock()
    }

    func emit(_ change: RuntimeLogChange) {
        lock.lock()
        let callback = observer
        lock.unlock()
        callback?(change)
    }
}
