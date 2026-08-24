import Foundation

enum RuntimeAXAppCollectionCoordinator {
    static let maxConcurrentCollections = 4
    private static let defaultCompletionWatchdogSeconds: TimeInterval = 4

    struct Cancellation {
        fileprivate let readIsCancelled: () -> Bool

        var isCancelled: Bool {
            readIsCancelled()
        }
    }

    static func collect<Result>(
        count: Int,
        completionWatchdogSeconds: TimeInterval = defaultCompletionWatchdogSeconds,
        collect: @escaping (Int) -> Result
    ) -> [Result] {
        self.collect(
            count: count,
            completionWatchdogSeconds: completionWatchdogSeconds
        ) { index, _ in
            collect(index)
        }
    }

    static func collect<Result>(
        count: Int,
        completionWatchdogSeconds: TimeInterval = defaultCompletionWatchdogSeconds,
        collect: @escaping (Int, Cancellation) -> Result
    ) -> [Result] {
        guard count > 0 else { return [] }
        precondition(
            completionWatchdogSeconds.isFinite && completionWatchdogSeconds > 0,
            "AX app collection watchdog must be finite and positive."
        )

        let group = DispatchGroup()
        let state = RuntimeAXAppCollectionBatchState<Result>(count: count)
        let workerCount = min(maxConcurrentCollections, count)
        let cancellation = Cancellation {
            state.isClosed
        }

        for _ in 0..<workerCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                while let index = state.claimNextIndex() {
                    let result = collect(index, cancellation)
                    state.record(result: result, at: index)
                }
            }
        }

        let completionResult = group.wait(
            timeout: .now() + completionWatchdogSeconds
        )
        let snapshot = state.closeAndSnapshot()
        if completionResult == .timedOut {
            RuntimeLog.warning(
                .ax,
                [
                    "app collection watchdog expired",
                    "completed=\(snapshot.results.count)",
                    "total=\(count)",
                    "watchdogMs=\(Int(completionWatchdogSeconds * 1_000))"
                ].joined(separator: " ")
            )
        }
        return snapshot.results
    }
}

private final class RuntimeAXAppCollectionBatchState<Result>: @unchecked Sendable {
    struct Snapshot {
        let results: [Result]
    }

    private let lock = NSLock()
    private let count: Int
    private var nextIndex = 0
    private var indexedResults: [(index: Int, result: Result)] = []
    private var closed = false

    init(count: Int) {
        self.count = count
    }

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    func claimNextIndex() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, nextIndex < count else { return nil }
        defer { nextIndex += 1 }
        return nextIndex
    }

    func record(result: Result, at index: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        indexedResults.append((index, result))
    }

    func closeAndSnapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        closed = true
        return Snapshot(
            results: indexedResults
                .sorted { $0.index < $1.index }
                .map(\.result)
        )
    }
}
