import Foundation
import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testRuntimeDiagnosticsPersistsRedactedMetadataForSensitiveValues() async throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("FlowTabTests-\(UUID().uuidString)", isDirectory: true)
        let logsDirectory = temporaryRoot.appendingPathComponent("FlowTab/logs", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let store = RuntimeLogFileStore(logsDirectoryURL: logsDirectory)
        let diagnostics = RuntimeDiagnostics(fileStore: store)
        let title = "Payroll Q4 – Confidential"
        let query = "acquisition target"
        let path = "{user-home}/Documents/board-plan.pdf"
        let numericPath = "/123/456"
        diagnostics.log(
            level: .error,
            category: RuntimeLogCategory.preview.rawValue,
            message: "capture failed title=\(title) query=\(query) path=\(path) backupPath=\(numericPath) candidates=11,22,33 reason=windowNotFound"
        )

        let persistedLines = await diagnostics.readRecentLines(limit: 10, minimumLevel: .debug)
        let line = try XCTUnwrap(persistedLines.first)
        XCTAssertFalse(line.contains(title))
        XCTAssertFalse(line.contains(query))
        XCTAssertFalse(line.contains(path))
        XCTAssertFalse(line.contains(numericPath))
        XCTAssertFalse(line.contains("11,22,33"))
        XCTAssertFalse(line.contains("windowNotFound"))
        XCTAssertFalse(line.contains("title="))
        XCTAssertFalse(line.contains("query="))
        XCTAssertFalse(line.contains("path="))
        XCTAssertFalse(line.contains("backupPath="))
        XCTAssertFalse(line.contains("candidates="))
        XCTAssertFalse(line.contains("reason="))
        XCTAssertTrue(line.contains("message.type=structured"))
        XCTAssertTrue(line.contains("message.fieldCount=6"))
        XCTAssertTrue(line.contains("field0.name.type=field-name"))
        XCTAssertTrue(line.contains("field0.name.fingerprint="))
        XCTAssertTrue(line.contains("field0.value.type=window-title"))
        XCTAssertTrue(line.contains("field0.value.length=\(title.count)"))
        XCTAssertTrue(line.contains("field0.value.count=1"))
        XCTAssertTrue(line.contains("field0.value.fingerprint="))
        XCTAssertTrue(line.contains("field1.value.type=search-text"))
        XCTAssertTrue(line.contains("field1.value.length=\(query.count)"))
        XCTAssertTrue(line.contains("field2.value.type=file-path"))
        XCTAssertTrue(line.contains("field2.value.length=\(path.count)"))
        XCTAssertTrue(line.contains("field3.value.type=file-path"))
        XCTAssertTrue(line.contains("field3.value.length=\(numericPath.count)"))
        XCTAssertTrue(line.contains("field4.value.type=text"))
        XCTAssertTrue(line.contains("field4.value.count=3"))
        XCTAssertTrue(line.contains("field4.value.fingerprint="))
        XCTAssertTrue(line.contains("field5.value.type=text"))
        XCTAssertTrue(line.contains("field5.value.fingerprint="))
    }

    func testRuntimeDiagnosticsFingerprintIsStableAcrossStoreRestart() async throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("FlowTabTests-\(UUID().uuidString)", isDirectory: true)
        let logsDirectory = temporaryRoot.appendingPathComponent("FlowTab/logs", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let title = "Stable Private Window"
        let firstStore = RuntimeLogFileStore(logsDirectoryURL: logsDirectory)
        let firstDiagnostics = RuntimeDiagnostics(fileStore: firstStore)
        firstDiagnostics.log(level: .error, category: "Preview", message: "failed title=\(title)")
        let firstLines = await firstDiagnostics.readRecentLines(limit: 10, minimumLevel: .debug)
        let firstLine = try XCTUnwrap(firstLines.first)
        let firstFingerprint = try XCTUnwrap(runtimeLogFingerprint(field: "field0.value", line: firstLine))

        try await firstDiagnostics.clearAndWait()
        let restartedStore = RuntimeLogFileStore(logsDirectoryURL: logsDirectory)
        let restartedDiagnostics = RuntimeDiagnostics(fileStore: restartedStore)
        restartedDiagnostics.log(level: .error, category: "Preview", message: "failed title=\(title)")
        let restartedLines = await restartedDiagnostics.readRecentLines(limit: 10, minimumLevel: .debug)
        let restartedLine = try XCTUnwrap(restartedLines.first)
        let restartedFingerprint = try XCTUnwrap(
            runtimeLogFingerprint(field: "field0.value", line: restartedLine)
        )

        XCTAssertEqual(restartedFingerprint, firstFingerprint)
    }

    func testRuntimeLogStoreMigratesLegacyLogsAndEnforcesPrivatePermissions() async throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("FlowTabTests-\(UUID().uuidString)", isDirectory: true)
        let logsDirectory = temporaryRoot.appendingPathComponent("FlowTab/logs", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        try fileManager.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        let legacyLogURL = logsDirectory.appendingPathComponent("FlowTab_legacy.log")
        try Data("private legacy title".utf8).write(to: legacyLogURL)
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: legacyLogURL.path)

        let store = RuntimeLogFileStore(logsDirectoryURL: logsDirectory)
        XCTAssertFalse(fileManager.fileExists(atPath: legacyLogURL.path))

        let diagnostics = RuntimeDiagnostics(fileStore: store)
        diagnostics.log(level: .error, category: "UnitTest", message: "permission-check title=Secret")
        _ = await diagnostics.readRecentLines(limit: 10, minimumLevel: .debug)

        XCTAssertEqual(try posixPermissions(at: logsDirectory), 0o700)
        let privateFiles = try fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.pathExtension == "log"
                || $0.lastPathComponent == RuntimeLogFileStore.privacyFingerprintKeyFileName
                || $0.lastPathComponent == RuntimeLogFileStore.privacyFormatMarkerFileName
        }
        XCTAssertEqual(privateFiles.filter { $0.pathExtension == "log" }.count, 1)
        XCTAssertTrue(
            privateFiles.contains { $0.lastPathComponent == RuntimeLogFileStore.privacyFingerprintKeyFileName }
        )
        XCTAssertTrue(
            privateFiles.contains { $0.lastPathComponent == RuntimeLogFileStore.privacyFormatMarkerFileName }
        )
        for fileURL in privateFiles {
            XCTAssertEqual(try posixPermissions(at: fileURL), 0o600, fileURL.lastPathComponent)
        }
    }

    func testRuntimeDiagnosticSessionRequiresExplicitStartAndExpires() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        userDefaults.set(true, forKey: AppPreferenceKeys.enableVerboseDiagnostics)

        XCTAssertFalse(RuntimeDiagnosticSessionStore.isActive(userDefaults: userDefaults, now: startDate))
        XCTAssertNil(userDefaults.object(forKey: AppPreferenceKeys.enableVerboseDiagnostics))

        let expirationDate = RuntimeDiagnosticSessionStore.start(
            userDefaults: userDefaults,
            now: startDate
        )
        XCTAssertEqual(
            expirationDate.timeIntervalSince(startDate),
            RuntimeDiagnosticSessionStore.duration,
            accuracy: 0.001
        )
        XCTAssertTrue(
            RuntimeDiagnosticSessionStore.isActive(
                userDefaults: userDefaults,
                now: expirationDate.addingTimeInterval(-1)
            )
        )
        XCTAssertFalse(
            RuntimeDiagnosticSessionStore.isActive(
                userDefaults: userDefaults,
                now: expirationDate.addingTimeInterval(1)
            )
        )
        XCTAssertNil(userDefaults.object(forKey: AppPreferenceKeys.diagnosticSessionExpiration))
    }

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

    private func runtimeLogFingerprint(field: String, line: String) -> String? {
        let expression = try? NSRegularExpression(pattern: "\(NSRegularExpression.escapedPattern(for: field))\\.fingerprint=([0-9a-f]+)")
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard
            let match = expression?.firstMatch(in: line, range: range),
            let fingerprintRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        return String(line[fingerprintRange])
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }
}
