import Foundation

enum RuntimeLogChangeKind: String, CaseIterable, Hashable {
    case appended
    case flushed
    case cleared
}

struct RuntimeLogChange: Equatable {
    let generation: UInt64
    let kind: RuntimeLogChangeKind
}

enum RuntimeLogReadMode: String, Equatable {
    case full
    case incremental
}

struct RuntimeLogReadBatch: Equatable {
    let lines: [String]
    let snapshot: RuntimeLogFileStore.ReadSnapshot
    let coveredChangeGeneration: UInt64
    let mode: RuntimeLogReadMode
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

final class RuntimeLogChangeHub {
    private struct Registration {
        let kinds: Set<RuntimeLogChangeKind>
        let observer: (RuntimeLogChange) -> Void
    }

    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var registrations: [UUID: Registration] = [:]

    var currentGeneration: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    func observe(
        kinds: Set<RuntimeLogChangeKind>,
        _ observer: @escaping (RuntimeLogChange) -> Void
    ) -> RuntimeLogChangeObservation {
        let observerID = UUID()
        lock.lock()
        registrations[observerID] = Registration(
            kinds: kinds,
            observer: observer
        )
        let baselineGeneration = generation
        lock.unlock()

        return RuntimeLogChangeObservation(
            baselineGeneration: baselineGeneration
        ) { [weak self] in
            self?.removeObserver(observerID)
        }
    }

    @discardableResult
    func publish(_ kind: RuntimeLogChangeKind) -> RuntimeLogChange {
        lock.lock()
        generation &+= 1
        let change = RuntimeLogChange(
            generation: generation,
            kind: kind
        )
        let observers = registrations.values.compactMap { registration in
            registration.kinds.contains(kind) ? registration.observer : nil
        }
        lock.unlock()

        for observer in observers {
            observer(change)
        }
        return change
    }

    private func removeObserver(_ observerID: UUID) {
        lock.lock()
        registrations.removeValue(forKey: observerID)
        lock.unlock()
    }
}

final class RuntimeLogReadCancellation {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
    }
}

protocol RuntimeLogLinesProviding: AnyObject {
    func observeChanges(
        kinds: Set<RuntimeLogChangeKind>,
        _ observer: @escaping (RuntimeLogChange) -> Void
    ) -> RuntimeLogChangeObservation

    func readRecentBatch(
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        since snapshot: RuntimeLogFileStore.ReadSnapshot?
    ) async throws -> RuntimeLogReadBatch

    func clearAndWait() async throws -> RuntimeLogChange
}

extension RuntimeLogLinesProviding {
    func observeChanges(
        _ observer: @escaping (RuntimeLogChange) -> Void
    ) -> RuntimeLogChangeObservation {
        observeChanges(
            kinds: Set(RuntimeLogChangeKind.allCases),
            observer
        )
    }

    func readRecentLines(
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        since snapshot: RuntimeLogFileStore.ReadSnapshot? = nil
    ) async -> [String] {
        do {
            return try await readRecentBatch(
                limit: limit,
                minimumLevel: minimumLevel,
                since: snapshot
            ).lines
        } catch {
            return []
        }
    }
}
