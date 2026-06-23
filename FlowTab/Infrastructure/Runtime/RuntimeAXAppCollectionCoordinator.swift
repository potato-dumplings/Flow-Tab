import Foundation

enum RuntimeAXAppCollectionCoordinator {
    static let maxConcurrentCollections = 4

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
}
