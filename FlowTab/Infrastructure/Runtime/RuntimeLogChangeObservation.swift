import Foundation

enum RuntimeLogChangeKind: String, Equatable {
    case appended
    case flushed
    case cleared
}

struct RuntimeLogChange: Equatable {
    let generation: UInt64
    let kind: RuntimeLogChangeKind
}

final class RuntimeLogChangeObservation {
    let baselineGeneration: UInt64

    private let lock = NSLock()
    private var cancellation: (() -> Void)?

    init(
        baselineGeneration: UInt64,
        cancellation: @escaping () -> Void
    ) {
        self.baselineGeneration = baselineGeneration
        self.cancellation = cancellation
    }

    func cancel() {
        lock.lock()
        let action = cancellation
        cancellation = nil
        lock.unlock()
        action?()
    }

    deinit {
        cancel()
    }
}

protocol RuntimeLogLinesProviding: AnyObject {
    func observeChanges(
        _ observer: @escaping (RuntimeLogChange) -> Void
    ) -> RuntimeLogChangeObservation

    func readRecentLines(
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        since snapshot: RuntimeLogFileStore.ReadSnapshot?
    ) async -> [String]

    func clearAndWait() async throws -> RuntimeLogChange
}
