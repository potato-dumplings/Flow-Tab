#if FLOWTAB_TESTING
import Foundation

struct FlowTabUITestMockWindowPreviewLatencyPolicy:
    Equatable,
    Sendable
{
    static let minimumMilliseconds = 1
    static let maximumMilliseconds = 1_000

    let milliseconds: Int

    init(rawMilliseconds: Int) {
        milliseconds = min(
            Self.maximumMilliseconds,
            max(
                Self.minimumMilliseconds,
                rawMilliseconds
            )
        )
    }

    var interval: TimeInterval {
        TimeInterval(milliseconds) / 1_000
    }
}

enum FlowTabUITestMockWindowPreviewLatencyOutcome:
    String,
    Equatable,
    Sendable
{
    case elapsed
    case cancelled
}

struct FlowTabUITestMockWindowPreviewLatencyEvidence:
    Equatable,
    Sendable
{
    let ownerGeneration: UInt64
    let batchGeneration: UInt64
    let requestCount: Int
    let policy:
        FlowTabUITestMockWindowPreviewLatencyPolicy
    let outcome:
        FlowTabUITestMockWindowPreviewLatencyOutcome

    var logFields: String {
        "ownerGeneration=\(ownerGeneration) "
            + "batchGeneration=\(batchGeneration) "
            + "outcome=\(outcome.rawValue) "
            + "delayMs=\(policy.milliseconds) "
            + "requests=\(requestCount)"
    }
}

protocol FlowTabUITestMockWindowPreviewLatencyWaiting:
    AnyObject
{
    func wait(
        for interval: TimeInterval
    ) -> FlowTabUITestMockWindowPreviewLatencyOutcome
    func cancel()
}

private final class
    FlowTabUITestMockWindowPreviewDeadlineWaiter:
    FlowTabUITestMockWindowPreviewLatencyWaiting,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var nextWaitGeneration: UInt64 = 0
    private var waiters:
        [UInt64: DispatchSemaphore] = [:]
    private var isCancelled = false

    func wait(
        for interval: TimeInterval
    ) -> FlowTabUITestMockWindowPreviewLatencyOutcome {
        let semaphore = DispatchSemaphore(value: 0)
        let waitGeneration: UInt64

        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return .cancelled
        }
        nextWaitGeneration &+= 1
        waitGeneration = nextWaitGeneration
        waiters[waitGeneration] = semaphore
        lock.unlock()

        let waitResult = semaphore.wait(
            timeout: .now() + interval
        )

        lock.lock()
        waiters.removeValue(
            forKey: waitGeneration
        )
        let cancelled = isCancelled
        lock.unlock()

        if cancelled || waitResult == .success {
            return .cancelled
        }
        return .elapsed
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        let activeWaiters = Array(waiters.values)
        waiters.removeAll()
        lock.unlock()

        for waiter in activeWaiters {
            waiter.signal()
        }
    }

    deinit {
        cancel()
    }
}

final class FlowTabUITestMockWindowPreviewLatencyOwner:
    @unchecked Sendable
{
    typealias EvidenceHandler =
        @Sendable (
            FlowTabUITestMockWindowPreviewLatencyEvidence
        ) -> Void

    let generation: UInt64
    let policy:
        FlowTabUITestMockWindowPreviewLatencyPolicy

    private let lock = NSLock()
    private let waiter:
        any FlowTabUITestMockWindowPreviewLatencyWaiting
    private let onEvidence: EvidenceHandler
    private var batchGeneration: UInt64 = 0
    private var isCancelled = false

    init(
        generation: UInt64,
        policy:
            FlowTabUITestMockWindowPreviewLatencyPolicy,
        waiter:
            (any FlowTabUITestMockWindowPreviewLatencyWaiting)? =
                nil,
        onEvidence: @escaping EvidenceHandler
    ) {
        self.generation = generation
        self.policy = policy
        self.waiter = waiter
            ?? FlowTabUITestMockWindowPreviewDeadlineWaiter()
        self.onEvidence = onEvidence
    }

    @discardableResult
    func waitBeforeCapture(
        requestCount: Int
    ) -> FlowTabUITestMockWindowPreviewLatencyEvidence {
        let batch: UInt64

        lock.lock()
        batchGeneration &+= 1
        batch = batchGeneration
        let cancelledBeforeWait = isCancelled
        lock.unlock()

        let waitOutcome =
            cancelledBeforeWait
            ? .cancelled
            : waiter.wait(for: policy.interval)

        lock.lock()
        let outcome:
            FlowTabUITestMockWindowPreviewLatencyOutcome =
                isCancelled ? .cancelled : waitOutcome
        lock.unlock()

        let evidence =
            FlowTabUITestMockWindowPreviewLatencyEvidence(
                ownerGeneration: generation,
                batchGeneration: batch,
                requestCount: requestCount,
                policy: policy,
                outcome: outcome
            )
        onEvidence(evidence)
        return evidence
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        lock.unlock()
        waiter.cancel()
    }

    deinit {
        cancel()
    }
}
#endif
