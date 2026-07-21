import Foundation
import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testRuntimeLogClearAndWaitDeletesFilesAndRestartReadsNoEntries() async throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("FlowTabTests-\(UUID().uuidString)", isDirectory: true)
        let logsDirectory = temporaryRoot.appendingPathComponent("FlowTab/logs", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let store = RuntimeLogFileStore(logsDirectoryURL: logsDirectory)
        let marker = "runtime-log-clear-\(UUID().uuidString)"
        store.append("[00:00:00.000] [ERROR] [UnitTest] \(marker)")

        let writtenLines = await store.readRecentLines(limit: 10, minimumLevel: .debug)
        XCTAssertTrue(writtenLines.contains { $0.contains(marker) })
        let filesBeforeClear = try fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(filesBeforeClear.contains { $0.pathExtension == "log" })

        try await store.clearAndWait()

        let filesAfterClear = try fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(filesAfterClear.contains { $0.pathExtension == "log" })

        let restartedStore = RuntimeLogFileStore(logsDirectoryURL: logsDirectory)
        let restartedLines = await restartedStore.readRecentLines(limit: 10, minimumLevel: .debug)
        XCTAssertTrue(restartedLines.isEmpty)
    }
}
