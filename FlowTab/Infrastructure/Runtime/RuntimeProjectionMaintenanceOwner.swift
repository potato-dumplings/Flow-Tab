import Foundation

struct RuntimeProjectionMaintenanceGeneration:
    RawRepresentable,
    Equatable,
    Comparable,
    Sendable,
    CustomStringConvertible
{
    let rawValue: UInt64

    static func < (
        lhs: RuntimeProjectionMaintenanceGeneration,
        rhs: RuntimeProjectionMaintenanceGeneration
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        String(rawValue)
    }
}

final class RuntimeProjectionMaintenanceOwner: @unchecked Sendable {
    typealias PriorityWork = @Sendable (
        RuntimeProjectionMaintenanceGeneration
    ) -> Void

    private struct PendingPriorityWork {
        let generation: RuntimeProjectionMaintenanceGeneration
        let perform: PriorityWork
    }

    let queue: DispatchQueue

    private let queueSpecificKey = DispatchSpecificKey<Void>()
    private let lock = NSLock()
    private var nextPriorityGeneration: UInt64 = 1
    private var pendingPriorityWork: [PendingPriorityWork] = []
    private var acceptsPriorityWork = true

    init(label: String, qos: DispatchQoS = .utility) {
        queue = DispatchQueue(label: label, qos: qos)
        queue.setSpecific(key: queueSpecificKey, value: ())
    }

    deinit {
        cancelPendingPriorityWork()
    }

    func enqueue(_ work: @escaping @Sendable () -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            drainPriorityWork()
            work()
            drainPriorityWork()
        }
    }

    @discardableResult
    func enqueuePriority(
        _ work: @escaping PriorityWork
    ) -> RuntimeProjectionMaintenanceGeneration? {
        lock.lock()
        guard acceptsPriorityWork else {
            lock.unlock()
            return nil
        }
        let generation = RuntimeProjectionMaintenanceGeneration(
            rawValue: nextPriorityGeneration
        )
        nextPriorityGeneration &+= 1
        pendingPriorityWork.append(
            PendingPriorityWork(
                generation: generation,
                perform: work
            )
        )
        lock.unlock()

        queue.async { [weak self] in
            self?.drainPriorityWork()
        }
        return generation
    }

    func performSynchronously<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueSpecificKey) != nil {
            drainPriorityWork()
            let result = try work()
            drainPriorityWork()
            return result
        }
        return try queue.sync {
            drainPriorityWork()
            let result = try work()
            drainPriorityWork()
            return result
        }
    }

    func cancelPendingPriorityWork() {
        lock.lock()
        acceptsPriorityWork = false
        pendingPriorityWork.removeAll()
        lock.unlock()
    }

    var pendingPriorityWorkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingPriorityWork.count
    }

    private func drainPriorityWork() {
        dispatchPrecondition(condition: .onQueue(queue))
        while true {
            lock.lock()
            guard acceptsPriorityWork, !pendingPriorityWork.isEmpty else {
                lock.unlock()
                return
            }
            let batch = pendingPriorityWork
            pendingPriorityWork.removeAll(keepingCapacity: true)
            lock.unlock()

            for pending in batch {
                pending.perform(pending.generation)
            }
        }
    }
}
