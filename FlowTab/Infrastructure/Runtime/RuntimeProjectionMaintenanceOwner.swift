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

struct RuntimeProjectionMaintenanceCoalescingKey:
    RawRepresentable,
    Hashable,
    Sendable
{
    let rawValue: String
}

final class RuntimeProjectionMaintenanceOwner: @unchecked Sendable {
    typealias Work = @Sendable () -> Void
    typealias PriorityWork = @Sendable (
        RuntimeProjectionMaintenanceGeneration
    ) -> Void

    private struct PendingPriorityWork {
        let coalescingKey: RuntimeProjectionMaintenanceCoalescingKey?
        let generation: RuntimeProjectionMaintenanceGeneration
        let perform: PriorityWork
    }

    let queue: DispatchQueue

    private let queueSpecificKey = DispatchSpecificKey<Void>()
    private let lock = NSLock()
    private var nextPriorityGeneration: UInt64 = 1
    private var pendingPriorityWork: [PendingPriorityWork] = []
    private var pendingCoalescedWork:
        [RuntimeProjectionMaintenanceCoalescingKey: Work] = [:]
    private var activeCoalescedWorkKeys:
        Set<RuntimeProjectionMaintenanceCoalescingKey> = []
    private var acceptsPriorityWork = true

    init(label: String, qos: DispatchQoS = .utility) {
        queue = DispatchQueue(label: label, qos: qos)
        queue.setSpecific(key: queueSpecificKey, value: ())
    }

    deinit {
        cancelPendingPriorityWork()
    }

    func enqueue(_ work: @escaping Work) {
        queue.async { [weak self] in
            guard let self else { return }
            drainPriorityWork()
            work()
            drainPriorityWork()
        }
    }

    func enqueueLatest(
        key: RuntimeProjectionMaintenanceCoalescingKey,
        _ work: @escaping Work
    ) {
        lock.lock()
        pendingCoalescedWork[key] = work
        let shouldSchedule = activeCoalescedWorkKeys.insert(key).inserted
        lock.unlock()

        guard shouldSchedule else { return }
        scheduleLatestWork(for: key)
    }

    @discardableResult
    func enqueuePriority(
        _ work: @escaping PriorityWork
    ) -> RuntimeProjectionMaintenanceGeneration? {
        enqueuePriority(coalescingKey: nil, work)
    }

    @discardableResult
    func enqueueLatestPriority(
        key: RuntimeProjectionMaintenanceCoalescingKey,
        _ work: @escaping PriorityWork
    ) -> RuntimeProjectionMaintenanceGeneration? {
        enqueuePriority(coalescingKey: key, work)
    }

    private func enqueuePriority(
        coalescingKey: RuntimeProjectionMaintenanceCoalescingKey?,
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
        var shouldScheduleDrain = true
        if let coalescingKey,
            let existingIndex = pendingPriorityWork.firstIndex(where: {
                $0.coalescingKey == coalescingKey
            })
        {
            pendingPriorityWork.remove(at: existingIndex)
            shouldScheduleDrain = false
        }
        pendingPriorityWork.append(
            PendingPriorityWork(
                coalescingKey: coalescingKey,
                generation: generation,
                perform: work
            )
        )
        lock.unlock()

        if shouldScheduleDrain {
            queue.async { [weak self] in
                self?.drainPriorityWork()
            }
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

    var pendingCoalescedWorkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingCoalescedWork.count
    }

    private func scheduleLatestWork(
        for key: RuntimeProjectionMaintenanceCoalescingKey
    ) {
        queue.async { [weak self] in
            self?.performLatestWork(for: key)
        }
    }

    private func performLatestWork(
        for key: RuntimeProjectionMaintenanceCoalescingKey
    ) {
        dispatchPrecondition(condition: .onQueue(queue))
        drainPriorityWork()

        lock.lock()
        guard let work = pendingCoalescedWork.removeValue(forKey: key) else {
            activeCoalescedWorkKeys.remove(key)
            lock.unlock()
            return
        }
        lock.unlock()

        work()
        drainPriorityWork()

        lock.lock()
        let shouldSchedule = pendingCoalescedWork[key] != nil
        if !shouldSchedule {
            activeCoalescedWorkKeys.remove(key)
        }
        lock.unlock()

        if shouldSchedule {
            scheduleLatestWork(for: key)
        }
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
