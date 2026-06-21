import Foundation

enum RuntimeAXAppCollectionCoordinator {
    static let maxConcurrentCollections = 4

    struct PressureResultForTesting {
        let orderedResults: [Int]
        let elapsedMs: Double
        let configuredConcurrency: Int
        let maxInFlight: Int
    }

    static func collect<Result>(
        count: Int,
        collect: @escaping (Int) -> Result
    ) -> [Result] {
        guard count > 1 else {
            return (0..<count).map { collect($0) }
        }

        let group = DispatchGroup()
        let resultLock = NSLock()
        let concurrencyLimit = min(maxConcurrentCollections, count)
        let concurrencyGate = DispatchSemaphore(value: concurrencyLimit)
        var results = Array<Result?>(repeating: nil, count: count)

        for index in 0..<count {
            concurrencyGate.wait()
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer {
                    concurrencyGate.signal()
                    group.leave()
                }
                let result = collect(index)
                resultLock.lock()
                results[index] = result
                resultLock.unlock()
            }
        }

        group.wait()
        return results.compactMap { $0 }
    }

    static func pressureResultForTesting(
        taskCount: Int,
        delayNanoseconds: UInt64
    ) -> PressureResultForTesting {
        let inFlightLock = NSLock()
        var inFlight = 0
        var maxInFlight = 0
        let startNs = DispatchTime.now().uptimeNanoseconds

        let orderedResults: [Int] = collect(count: taskCount) { index in
            inFlightLock.lock()
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            inFlightLock.unlock()

            Thread.sleep(forTimeInterval: Double(delayNanoseconds) / 1_000_000_000.0)

            inFlightLock.lock()
            inFlight -= 1
            inFlightLock.unlock()
            return index
        }
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000.0

        return PressureResultForTesting(
            orderedResults: orderedResults,
            elapsedMs: elapsedMs,
            configuredConcurrency: min(maxConcurrentCollections, taskCount),
            maxInFlight: maxInFlight
        )
    }
}
