import Foundation

protocol RuntimeLogTailReading: AnyObject {
    func readLines(
        from fileURLsNewestFirst: [URL],
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        previousSnapshot: RuntimeLogFileStore.ReadSnapshot?,
        currentSnapshot: RuntimeLogFileStore.ReadSnapshot,
        mode: RuntimeLogReadMode,
        cancellation: RuntimeLogReadCancellation
    ) throws -> [String]
}

final class RuntimeLogTailReader: RuntimeLogTailReading {
    static let defaultChunkSizeBytes = 64 * 1_024

    private let chunkSizeBytes: Int

    init(chunkSizeBytes: Int = defaultChunkSizeBytes) {
        self.chunkSizeBytes = max(1, chunkSizeBytes)
    }

    func readLines(
        from fileURLsNewestFirst: [URL],
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        previousSnapshot: RuntimeLogFileStore.ReadSnapshot?,
        currentSnapshot: RuntimeLogFileStore.ReadSnapshot,
        mode: RuntimeLogReadMode,
        cancellation: RuntimeLogReadCancellation
    ) throws -> [String] {
        guard limit > 0 else { return [] }
        try cancellation.checkCancellation()

        switch mode {
        case .full:
            return try readLatestLines(
                from: fileURLsNewestFirst,
                limit: limit,
                minimumLevel: minimumLevel,
                currentSnapshot: currentSnapshot,
                cancellation: cancellation
            )
        case .incremental:
            guard let previousSnapshot else { return [] }
            return try readIncrementalLines(
                from: fileURLsNewestFirst,
                limit: limit,
                minimumLevel: minimumLevel,
                previousSnapshot: previousSnapshot,
                currentSnapshot: currentSnapshot,
                cancellation: cancellation
            )
        }
    }

    private func readLatestLines(
        from fileURLsNewestFirst: [URL],
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        currentSnapshot: RuntimeLogFileStore.ReadSnapshot,
        cancellation: RuntimeLogReadCancellation
    ) throws -> [String] {
        var newestFirst: [String] = []

        for url in fileURLsNewestFirst {
            try cancellation.checkCancellation()
            let endOffset = currentSnapshot.fileOffsetsByPath[url.path] ?? 0
            guard endOffset > 0 else { continue }
            let fileLines = try readFileNewestFirst(
                at: url,
                endOffset: endOffset,
                maximumCount: limit - newestFirst.count,
                minimumLevel: minimumLevel,
                cancellation: cancellation
            )
            newestFirst.append(contentsOf: fileLines)
            if newestFirst.count >= limit {
                break
            }
        }

        return Array(newestFirst.prefix(limit).reversed())
    }

    private func readFileNewestFirst(
        at url: URL,
        endOffset: Int,
        maximumCount: Int,
        minimumLevel: RuntimeLogLevel,
        cancellation: RuntimeLogReadCancellation
    ) throws -> [String] {
        guard maximumCount > 0, endOffset > 0 else { return [] }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var position = endOffset
        var trailingFragment = Data()
        var newestFirst: [String] = []

        while position > 0, newestFirst.count < maximumCount {
            try cancellation.checkCancellation()
            let blockStart = max(0, position - chunkSizeBytes)
            let readCount = position - blockStart
            try handle.seek(toOffset: UInt64(blockStart))
            let didRead = try autoreleasepool { () throws -> Bool in
                guard let block = try handle.read(upToCount: readCount),
                      !block.isEmpty
                else {
                    return false
                }

                block.withUnsafeBytes { rawBuffer in
                    let bytes = rawBuffer.bindMemory(to: UInt8.self)
                    var segmentEnd = bytes.count
                    for index in newlineOffsets(in: bytes).reversed()
                        where newestFirst.count < maximumCount {
                        let lineBytes = UnsafeBufferPointer(
                            rebasing: bytes[(index + 1)..<segmentEnd]
                        )
                        if trailingFragment.isEmpty {
                            appendIfMatching(
                                lineBytes,
                                minimumLevel: minimumLevel,
                                to: &newestFirst
                            )
                        } else {
                            var lineData = Data(capacity:
                                lineBytes.count + trailingFragment.count
                            )
                            lineData.append(contentsOf: lineBytes)
                            lineData.append(trailingFragment)
                            trailingFragment.removeAll(keepingCapacity: true)
                            appendIfMatching(
                                lineData,
                                minimumLevel: minimumLevel,
                                to: &newestFirst
                            )
                        }
                        segmentEnd = index
                    }

                    if newestFirst.count < maximumCount {
                        var combined = Data(capacity:
                            segmentEnd + trailingFragment.count
                        )
                        combined.append(contentsOf: bytes[..<segmentEnd])
                        combined.append(trailingFragment)
                        trailingFragment = combined
                    }
                }
                return true
            }
            guard didRead else {
                break
            }
            position = blockStart
        }

        if position == 0,
           newestFirst.count < maximumCount,
           !trailingFragment.isEmpty {
            appendIfMatching(
                trailingFragment,
                minimumLevel: minimumLevel,
                to: &newestFirst
            )
        }
        return newestFirst
    }

    private func readIncrementalLines(
        from fileURLsNewestFirst: [URL],
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        previousSnapshot: RuntimeLogFileStore.ReadSnapshot,
        currentSnapshot: RuntimeLogFileStore.ReadSnapshot,
        cancellation: RuntimeLogReadCancellation
    ) throws -> [String] {
        var recentLines: [String] = []

        for url in fileURLsNewestFirst.reversed() {
            try cancellation.checkCancellation()
            let startOffset = previousSnapshot.fileOffsetsByPath[url.path] ?? 0
            let endOffset = currentSnapshot.fileOffsetsByPath[url.path] ?? 0
            guard endOffset > startOffset else { continue }

            try readFileForward(
                at: url,
                startOffset: startOffset,
                endOffset: endOffset,
                minimumLevel: minimumLevel,
                cancellation: cancellation
            ) { line in
                recentLines.append(line)
                if recentLines.count > limit {
                    recentLines.removeFirst(recentLines.count - limit)
                }
            }
        }
        return recentLines
    }

    private func readFileForward(
        at url: URL,
        startOffset: Int,
        endOffset: Int,
        minimumLevel: RuntimeLogLevel,
        cancellation: RuntimeLogReadCancellation,
        consume: (String) -> Void
    ) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(startOffset))

        var position = startOffset
        var fragment = Data()
        while position < endOffset {
            try cancellation.checkCancellation()
            let readCount = min(chunkSizeBytes, endOffset - position)
            let consumedCount = try autoreleasepool { () throws -> Int in
                guard let block = try handle.read(upToCount: readCount),
                      !block.isEmpty
                else {
                    return 0
                }

                block.withUnsafeBytes { rawBuffer in
                    let bytes = rawBuffer.bindMemory(to: UInt8.self)
                    var segmentStart = 0
                    for index in newlineOffsets(in: bytes) {
                        let lineBytes = UnsafeBufferPointer(
                            rebasing: bytes[segmentStart..<index]
                        )
                        if fragment.isEmpty {
                            if let line = matchingLine(
                                from: lineBytes,
                                minimumLevel: minimumLevel
                            ) {
                                consume(line)
                            }
                        } else {
                            fragment.append(contentsOf: lineBytes)
                            if let line = matchingLine(
                                from: fragment,
                                minimumLevel: minimumLevel
                            ) {
                                consume(line)
                            }
                            fragment.removeAll(keepingCapacity: true)
                        }
                        segmentStart = index + 1
                    }
                    fragment.append(contentsOf: bytes[segmentStart...])
                }
                return block.count
            }
            guard consumedCount > 0 else {
                break
            }
            position += consumedCount
        }

        if !fragment.isEmpty,
           let line = matchingLine(
               from: fragment,
               minimumLevel: minimumLevel
           ) {
            consume(line)
        }
    }

    private func newlineOffsets(
        in bytes: UnsafeBufferPointer<UInt8>
    ) -> [Int] {
        guard let baseAddress = bytes.baseAddress, !bytes.isEmpty else {
            return []
        }
        var offsets: [Int] = []
        offsets.reserveCapacity(max(1, bytes.count / 96))
        var searchOffset = 0
        while searchOffset < bytes.count {
            let remainingCount = bytes.count - searchOffset
            guard let match = memchr(
                baseAddress.advanced(by: searchOffset),
                Int32(0x0A),
                remainingCount
            ) else {
                break
            }
            let matchAddress = match.assumingMemoryBound(to: UInt8.self)
            let offset = baseAddress.distance(to: matchAddress)
            offsets.append(offset)
            searchOffset = offset + 1
        }
        return offsets
    }

    private func appendIfMatching(
        _ bytes: UnsafeBufferPointer<UInt8>,
        minimumLevel: RuntimeLogLevel,
        to lines: inout [String]
    ) {
        if let line = matchingLine(
            from: bytes,
            minimumLevel: minimumLevel
        ) {
            lines.append(line)
        }
    }

    private func appendIfMatching(
        _ data: Data,
        minimumLevel: RuntimeLogLevel,
        to lines: inout [String]
    ) {
        if let line = matchingLine(
            from: data,
            minimumLevel: minimumLevel
        ) {
            lines.append(line)
        }
    }

    private func matchingLine(
        from data: Data,
        minimumLevel: RuntimeLogLevel
    ) -> String? {
        data.withUnsafeBytes { rawBuffer in
            let buffer = rawBuffer.bindMemory(to: UInt8.self)
            return matchingLine(
                from: buffer,
                minimumLevel: minimumLevel
            )
        }
    }

    private func matchingLine(
        from bytes: UnsafeBufferPointer<UInt8>,
        minimumLevel: RuntimeLogLevel
    ) -> String? {
        var count = bytes.count
        guard count > 0 else { return nil }
        if bytes[count - 1] == 0x0D {
            count -= 1
        }
        guard count > 0 else { return nil }
        let normalized = UnsafeBufferPointer(rebasing: bytes[..<count])
        guard parsedLevel(from: normalized) >= minimumLevel else {
            return nil
        }
        return String(bytes: normalized, encoding: .utf8)
    }

    private func parsedLevel(
        from bytes: UnsafeBufferPointer<UInt8>
    ) -> RuntimeLogLevel {
        var timestampEnd = 0
        while timestampEnd < bytes.count,
              bytes[timestampEnd] != 0x5D {
            timestampEnd += 1
        }
        guard timestampEnd < bytes.count else { return .info }

        var index = timestampEnd + 1
        while index < bytes.count,
              bytes[index] == 0x20 || bytes[index] == 0x09 {
            index += 1
        }
        guard index < bytes.count, bytes[index] == 0x5B else {
            return .info
        }

        let levelStart = index + 1
        var levelEnd = levelStart
        while levelEnd < bytes.count, bytes[levelEnd] != 0x5D {
            levelEnd += 1
        }
        guard levelEnd < bytes.count else { return .info }

        let levelLength = levelEnd - levelStart
        if levelLength == 5,
           bytes[levelStart] == 0x44,
           bytes[levelStart + 1] == 0x45,
           bytes[levelStart + 2] == 0x42,
           bytes[levelStart + 3] == 0x55,
           bytes[levelStart + 4] == 0x47 {
            return .debug
        }
        if levelLength == 4,
           bytes[levelStart] == 0x49,
           bytes[levelStart + 1] == 0x4E,
           bytes[levelStart + 2] == 0x46,
           bytes[levelStart + 3] == 0x4F {
            return .info
        }
        if levelLength == 4,
           bytes[levelStart] == 0x57,
           bytes[levelStart + 1] == 0x41,
           bytes[levelStart + 2] == 0x52,
           bytes[levelStart + 3] == 0x4E {
            return .warning
        }
        if levelLength == 5,
           bytes[levelStart] == 0x45,
           bytes[levelStart + 1] == 0x52,
           bytes[levelStart + 2] == 0x52,
           bytes[levelStart + 3] == 0x4F,
           bytes[levelStart + 4] == 0x52 {
            return .error
        }
        return .info
    }
}
