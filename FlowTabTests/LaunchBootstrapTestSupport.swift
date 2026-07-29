import Foundation
@testable import FlowTab

final class LaunchBootstrapLogWriteRecorder {
    struct Snapshot {
        let didObserveClear: Bool
        let appendCount: Int
        let lastChange: RuntimeLogChange?

        var description: String {
            "didObserveClear=\(didObserveClear) "
                + "appendCount=\(appendCount) "
                + "lastGeneration="
                + "\(lastChange?.generation.description ?? "nil") "
                + "lastKind="
                + "\(lastChange?.kind.rawValue ?? "nil")"
        }
    }

    private let lock = NSLock()
    private let expectedAppendCount: Int
    private let onReady: () -> Void
    private var didObserveClear = false
    private var appendCount = 0
    private var lastChange: RuntimeLogChange?
    private var didNotify = false
    private var isCancelled = false

    init(
        expectedAppendCount: Int,
        onReady: @escaping () -> Void
    ) {
        self.expectedAppendCount =
            expectedAppendCount
        self.onReady = onReady
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            didObserveClear: didObserveClear,
            appendCount: appendCount,
            lastChange: lastChange
        )
    }

    func observe(_ change: RuntimeLogChange) {
        var shouldNotify = false
        lock.lock()
        if !isCancelled {
            lastChange = change
            switch change.kind {
            case .cleared:
                didObserveClear = true
                appendCount = 0
            case .appended:
                if didObserveClear {
                    appendCount += 1
                }
            case .flushed:
                break
            }
            if
                didObserveClear,
                appendCount >= expectedAppendCount,
                !didNotify
            {
                didNotify = true
                shouldNotify = true
            }
        }
        lock.unlock()
        if shouldNotify {
            onReady()
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }
}
