import Foundation
import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testRuntimeLogTailReaderHandlesChunkBoundariesUTF8AndLineEndings()
        throws
    {
        let fixture = try RuntimeLogReaderFixture()
        defer { fixture.remove() }
        let longMessage = String(repeating: "边界🙂", count: 40)
        let expectedLines = [
            "[00:00:00.000] [DEBUG] [UnitTest] first",
            "[00:00:00.001] [INFO] [UnitTest] \(longMessage)",
            "[00:00:00.002] [WARN] [UnitTest] warning",
            "[00:00:00.003] [ERROR] [UnitTest] last mentions [DEBUG]"
        ]
        let data = Data(
            (expectedLines[0] + "\n"
                + expectedLines[1] + "\r\n"
                + expectedLines[2] + "\n"
                + expectedLines[3] + "\r\n").utf8
        )
        try data.write(to: fixture.logURL)
        let snapshot = RuntimeLogFileStore.ReadSnapshot(
            fileOffsetsByPath: [fixture.logURL.path: data.count],
            storageEpoch: 0
        )
        let reader = RuntimeLogTailReader(chunkSizeBytes: 7)

        let allLines = try reader.readLines(
            from: [fixture.logURL],
            limit: 10,
            minimumLevel: .debug,
            previousSnapshot: nil,
            currentSnapshot: snapshot,
            mode: .full,
            cancellation: RuntimeLogReadCancellation()
        )
        XCTAssertEqual(allLines, expectedLines)

        let warningLines = try reader.readLines(
            from: [fixture.logURL],
            limit: 10,
            minimumLevel: .warning,
            previousSnapshot: nil,
            currentSnapshot: snapshot,
            mode: .full,
            cancellation: RuntimeLogReadCancellation()
        )
        XCTAssertEqual(warningLines, Array(expectedLines.suffix(2)))
    }

    func testRuntimeLogTailReaderStopsAtLatestThreeHundredMatchingLines()
        throws
    {
        let fixture = try RuntimeLogReaderFixture()
        defer { fixture.remove() }
        let lines = (1...360).map {
            "[00:00:00.000] [INFO] [UnitTest] marker-"
                + String(format: "%03d", $0)
        }
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        try data.write(to: fixture.logURL)
        let snapshot = RuntimeLogFileStore.ReadSnapshot(
            fileOffsetsByPath: [fixture.logURL.path: data.count],
            storageEpoch: 0
        )

        let result = try RuntimeLogTailReader(chunkSizeBytes: 31).readLines(
            from: [fixture.logURL],
            limit: 300,
            minimumLevel: .info,
            previousSnapshot: nil,
            currentSnapshot: snapshot,
            mode: .full,
            cancellation: RuntimeLogReadCancellation()
        )

        XCTAssertEqual(result.count, 300)
        XCTAssertTrue(result.first?.hasSuffix("marker-061") == true)
        XCTAssertTrue(result.last?.hasSuffix("marker-360") == true)
    }

    func testRuntimeLogStoreReadsFullThenIncrementalAndFallsBackAfterTruncation()
        async throws
    {
        let fixture = try RuntimeLogReaderFixture()
        defer { fixture.remove() }
        let store = RuntimeLogFileStore(
            logsDirectoryURL: fixture.logsDirectory
        )
        let firstLine = "[00:00:00.000] [INFO] [UnitTest] first"
        let secondLine = "[00:00:00.001] [WARN] [UnitTest] second"
        let postTruncationLine =
            "[00:00:00.002] [ERROR] [UnitTest] post-truncation"

        store.append(firstLine)
        let firstBatch = try await store.readRecentBatch(
            limit: 300,
            minimumLevel: .debug
        )
        XCTAssertEqual(firstBatch.mode, .full)
        XCTAssertEqual(firstBatch.lines, [firstLine])

        store.append(secondLine)
        let incrementalBatch = try await store.readRecentBatch(
            limit: 300,
            minimumLevel: .debug,
            since: firstBatch.snapshot
        )
        XCTAssertEqual(incrementalBatch.mode, .incremental)
        XCTAssertEqual(incrementalBatch.lines, [secondLine])
        XCTAssertGreaterThan(
            incrementalBatch.coveredChangeGeneration,
            firstBatch.coveredChangeGeneration
        )

        let activePath = try XCTUnwrap(
            incrementalBatch.snapshot.fileOffsetsByPath.keys.first
        )
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: activePath))
        try handle.truncate(atOffset: 0)
        try handle.close()
        store.append(postTruncationLine)

        let fallbackBatch = try await store.readRecentBatch(
            limit: 300,
            minimumLevel: .debug,
            since: incrementalBatch.snapshot
        )
        XCTAssertEqual(fallbackBatch.mode, .full)
        XCTAssertEqual(fallbackBatch.lines, [postTruncationLine])

        let clearChange = try await store.clearAndWait()
        let clearedBatch = try await store.readRecentBatch(
            limit: 300,
            minimumLevel: .debug,
            since: fallbackBatch.snapshot
        )
        XCTAssertEqual(clearedBatch.mode, .full)
        XCTAssertTrue(clearedBatch.lines.isEmpty)
        XCTAssertGreaterThanOrEqual(
            clearedBatch.coveredChangeGeneration,
            clearChange.generation
        )
    }

    func testRuntimeLogStoreKeepsIncrementalModeAcrossNewFileAndFallsBackAfterRetention()
        async throws
    {
        let fixture = try RuntimeLogReaderFixture()
        defer { fixture.remove() }
        let policy = RuntimeLogStoragePolicy(
            maxFileSizeBytes: 200,
            maxLogFiles: 2,
            flushDelay: 0,
            immediateFlushThreshold: 1,
            readChunkSizeBytes: 64
        )
        let store = RuntimeLogFileStore(
            logsDirectoryURL: fixture.logsDirectory,
            policy: policy
        )
        func line(_ marker: String) -> String {
            "[00:00:00.000] [DEBUG] [UnitTest] \(marker) "
                + String(repeating: "x", count: 120)
        }

        let firstLine = line("first-file")
        store.append(firstLine)
        let firstBatch = try await store.readRecentBatch(
            limit: 300,
            minimumLevel: .debug
        )
        XCTAssertEqual(firstBatch.mode, .full)

        let secondLine = line("new-file")
        store.append(secondLine)
        let newFileBatch = try await store.readRecentBatch(
            limit: 300,
            minimumLevel: .debug,
            since: firstBatch.snapshot
        )
        XCTAssertEqual(newFileBatch.mode, .incremental)
        XCTAssertEqual(newFileBatch.lines, [secondLine])

        let thirdLine = line("retained-file")
        store.append(thirdLine)
        let retentionBatch = try await store.readRecentBatch(
            limit: 300,
            minimumLevel: .debug,
            since: newFileBatch.snapshot
        )
        XCTAssertEqual(retentionBatch.mode, .full)
        XCTAssertEqual(retentionBatch.lines, [secondLine, thirdLine])
    }

    func testRuntimeLogObservationRegistrationBypassesBlockedFileReadAndQueuedCancellation()
        async throws
    {
        let fixture = try RuntimeLogReaderFixture()
        defer { fixture.remove() }
        let readStarted = expectation(
            description: "unmetCondition=runtimeLogTailReadStarted"
        )
        let reader = GatedRuntimeLogTailReader(readStarted: readStarted)
        let store = RuntimeLogFileStore(
            logsDirectoryURL: fixture.logsDirectory,
            tailReader: reader
        )

        let firstRead = Task {
            try await store.readRecentBatch(
                limit: 300,
                minimumLevel: .debug
            )
        }
        await fulfillment(of: [readStarted], timeout: 1)

        let observation = store.observeChanges(kinds: [.flushed, .cleared]) {
            _ in
        }
        XCTAssertEqual(observation.baselineGeneration, 0)

        let cancelledRead = Task {
            try await store.readRecentBatch(
                limit: 300,
                minimumLevel: .debug
            )
        }
        await Task.yield()
        cancelledRead.cancel()
        reader.releaseFirstRead()

        _ = try await firstRead.value
        do {
            _ = try await cancelledRead.value
            XCTFail("Cancelled queued read unexpectedly completed")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected queued-read error: \(error)")
        }
        XCTAssertEqual(reader.invocationCount, 1)
        XCTAssertEqual(reader.maximumConcurrentReads, 1)
        observation.cancel()
    }

    func testRuntimeLogStoreEnforcesInjectedRetentionAndPrivatePermissions()
        async throws
    {
        let fixture = try RuntimeLogReaderFixture()
        defer { fixture.remove() }
        let policy = RuntimeLogStoragePolicy(
            maxFileSizeBytes: 180,
            maxLogFiles: 3,
            flushDelay: 0,
            immediateFlushThreshold: 1,
            readChunkSizeBytes: 16
        )
        let store = RuntimeLogFileStore(
            logsDirectoryURL: fixture.logsDirectory,
            policy: policy
        )

        for index in 1...7 {
            store.append(
                "[00:00:00.000] [DEBUG] [UnitTest] marker-\(index)-"
                    + String(repeating: "x", count: 100)
            )
            _ = try await store.readRecentBatch(
                limit: 300,
                minimumLevel: .debug
            )
        }

        let managedFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.logsDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "log" }
        XCTAssertEqual(managedFiles.count, 3)
        let latest = try await store.readRecentBatch(
            limit: 300,
            minimumLevel: .debug
        )
        XCTAssertTrue(latest.lines.last?.contains("marker-7-") == true)
        XCTAssertEqual(try fixture.permissions(at: fixture.logsDirectory), 0o700)
        for fileURL in managedFiles {
            XCTAssertEqual(try fixture.permissions(at: fileURL), 0o600)
        }
    }

    func testRuntimeLogStoreRetainsLatestDataAcrossTwentyMegabyteRotation()
        async throws
    {
        let fixture = try RuntimeLogReaderFixture()
        defer { fixture.remove() }
        let store = RuntimeLogFileStore(
            logsDirectoryURL: fixture.logsDirectory
        )
        let payload = String(repeating: "x", count: 9_000)

        for fileIndex in 1...22 {
            for lineIndex in 1...100 {
                store.append(
                    "[00:00:00.000] [DEBUG] [UnitTest] "
                        + "file-\(fileIndex)-line-\(lineIndex) \(payload)"
                )
            }
            _ = try await store.readRecentBatch(
                limit: 1,
                minimumLevel: .debug
            )
        }

        let managedFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.logsDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ).filter { $0.pathExtension == "log" }
        let retainedByteCount = try managedFiles.reduce(into: 0) {
            byteCount,
            fileURL in
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            byteCount += values.fileSize ?? 0
        }
        let latest = try await store.readRecentBatch(
            limit: 1,
            minimumLevel: .debug
        )

        XCTAssertEqual(managedFiles.count, 20)
        XCTAssertLessThanOrEqual(retainedByteCount, 20_000_000)
        XCTAssertTrue(latest.lines.last?.contains("file-22-line-100") == true)
        XCTAssertEqual(try fixture.permissions(at: fixture.logsDirectory), 0o700)
        for fileURL in managedFiles {
            XCTAssertEqual(try fixture.permissions(at: fileURL), 0o600)
        }
    }
}

private final class RuntimeLogReaderFixture {
    let root: URL
    let logsDirectory: URL
    let logURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FlowTabRuntimeLogReader-\(UUID().uuidString)",
            isDirectory: true
        )
        logsDirectory = root.appendingPathComponent("FlowTab/logs", isDirectory: true)
        logURL = root.appendingPathComponent("reader.log", isDirectory: false)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        return try XCTUnwrap(
            attributes[.posixPermissions] as? NSNumber
        ).intValue & 0o777
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class GatedRuntimeLogTailReader: RuntimeLogTailReading {
    private let condition = NSCondition()
    private let readStarted: XCTestExpectation
    private var released = false
    private var activeReads = 0
    private(set) var invocationCount = 0
    private(set) var maximumConcurrentReads = 0

    init(readStarted: XCTestExpectation) {
        self.readStarted = readStarted
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
        condition.lock()
        invocationCount += 1
        activeReads += 1
        maximumConcurrentReads = max(maximumConcurrentReads, activeReads)
        if invocationCount == 1 {
            readStarted.fulfill()
            while !released {
                condition.wait()
            }
        }
        activeReads -= 1
        condition.unlock()
        try cancellation.checkCancellation()
        return []
    }

    func releaseFirstRead() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}
