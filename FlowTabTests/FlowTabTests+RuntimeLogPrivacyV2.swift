import Foundation
import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testRuntimeLogPrivacyV2RoundTripsEmptyAndAllPrivacyTypes() throws {
        let formatter = RuntimeLogPrivacyFormatter(
            keyData: Data(repeating: 0x41, count: 32)
        )
        let codec = RuntimeLogPrivacyCodec()

        let emptyEnvelope = formatter.makeEnvelope(for: "")
        let emptyRecord = codec.encode(emptyEnvelope)
        XCTAssertTrue(emptyRecord.hasPrefix("privacy=v2 m=0,0,"))
        XCTAssertTrue(emptyRecord.hasSuffix(" e=- f=-"))
        XCTAssertEqual(codec.decode(emptyRecord), emptyEnvelope)

        let message = """
        projected query=needle tabTitle=Browser title title=Window title path=/private/example url=https://example.invalid bundleID=com.example.secret errorDescription=failed identifier=window-42 fallback=value
        """
        let envelope = formatter.makeEnvelope(for: message)
        let record = codec.encode(envelope)
        let decoded = try XCTUnwrap(codec.decode(record))
        XCTAssertEqual(decoded, envelope)
        XCTAssertEqual(decoded.fields.count, 9)
        for code in ["t", "s", "b", "w", "p", "u", "a", "e", "i"] {
            XCTAssertTrue(record.contains(",\(code),"), "Missing privacy type code \(code)")
        }
        XCTAssertFalse(record.contains("projected"))
        XCTAssertFalse(record.contains("query"))
        XCTAssertFalse(record.contains("needle"))
        XCTAssertFalse(record.contains("com.example.secret"))

        let expanded = codec.expandedMessage(for: decoded)
        XCTAssertTrue(expanded.contains("message.type=structured"))
        XCTAssertTrue(expanded.contains("message.fieldCount=9"))
        XCTAssertTrue(expanded.contains("field0.value.type=search-text"))
        XCTAssertTrue(expanded.contains("field8.value.type=text"))
        XCTAssertTrue(
            expanded.contains(
                "message.fingerprint=\(formatter.stableFingerprint(for: message))"
            )
        )
        let onDiskFingerprint = try XCTUnwrap(
            record.split(separator: " ")[1]
                .split(separator: ",")
                .last
        )
        XCTAssertEqual(onDiskFingerprint.count, 16)
        XCTAssertFalse(onDiskFingerprint.contains("="))

        for category in RuntimeLogCategory.allCases {
            let compactLine = codec.encodeLine(
                timestamp: "12:34:56.789",
                level: .debug,
                category: category.rawValue,
                envelope: envelope
            )
            XCTAssertTrue(compactLine.hasPrefix("[0QYV85][D]["))
            XCTAssertEqual(
                codec.expandLineForDisplay(compactLine),
                "[12:34:56.789] [DEBUG] [\(category.rawValue)] "
                    + expanded
            )
        }
        let escapedCategoryLine = codec.encodeLine(
            timestamp: "12:34:56.789",
            level: .warning,
            category: "~custom",
            envelope: envelope
        )
        XCTAssertTrue(escapedCategoryLine.hasPrefix("[0QYV85][W][~~custom]"))
        XCTAssertEqual(
            codec.expandLineForDisplay(escapedCategoryLine),
            "[12:34:56.789] [WARN] [~custom] " + expanded
        )
        let previousCompactHeader = "[123456789][DEBUG][~B]" + codec.encode(envelope)
        XCTAssertEqual(
            codec.expandLineForDisplay(previousCompactHeader),
            "[12:34:56.789] [DEBUG] [Projection] " + expanded
        )
    }

    func testRuntimeDiagnosticsWritesOneCompactV2RecordPerCallAndExpandsOnRead()
        async throws
    {
        let fixture = try RuntimeLogPrivacyV2Fixture()
        defer { fixture.remove() }
        let store = RuntimeLogFileStore(logsDirectoryURL: fixture.logsDirectory)
        let diagnostics = RuntimeDiagnostics(fileStore: store)
        let messages = [
            "projection assembled secretTitle=Payroll-Confidential count=1,2,3",
            "projection updated secretPath=/private/board-plan.pdf identifier=window-42",
            "projection committed query=acquisition-target bundleID=com.example.private"
        ]

        for message in messages {
            diagnostics.log(level: .debug, category: "Projection", message: message)
        }
        let batch = try await diagnostics.readRecentBatch(
            limit: 10,
            minimumLevel: .debug
        )

        let rawLines = try fixture.rawLogLines()
        XCTAssertEqual(rawLines.count, messages.count)
        XCTAssertTrue(rawLines.allSatisfy { $0.contains("]privacy=v2 m=") })
        XCTAssertTrue(rawLines.allSatisfy { $0.contains("][D][B]") })
        for sensitiveText in [
            "projection assembled",
            "secretTitle",
            "Payroll-Confidential",
            "secretPath",
            "/private/board-plan.pdf",
            "acquisition-target",
            "com.example.private"
        ] {
            XCTAssertFalse(
                rawLines.contains { $0.contains(sensitiveText) },
                "Persisted v2 record leaked \(sensitiveText)"
            )
        }

        XCTAssertEqual(batch.lines.count, messages.count)
        XCTAssertTrue(batch.lines.allSatisfy { $0.contains("message.type=structured") })
        XCTAssertTrue(batch.lines[0].contains("field0.value.type=window-title"))
        XCTAssertTrue(batch.lines[1].contains("field0.value.type=file-path"))
        XCTAssertTrue(batch.lines[2].contains("field0.value.type=search-text"))
    }

    func testRuntimeLogTailReaderExpandsMixedV1V2AndPreservesMalformedV2()
        throws
    {
        let fixture = try RuntimeLogPrivacyV2Fixture()
        defer { fixture.remove() }
        let logURL = fixture.logsDirectory.appendingPathComponent(
            "mixed.log",
            isDirectory: false
        )
        let formatter = RuntimeLogPrivacyFormatter(
            keyData: Data(repeating: 0x22, count: 32)
        )
        let codec = RuntimeLogPrivacyCodec()
        let envelope = formatter.makeEnvelope(
            for: "投影完成🙂 title=私密窗口 identifier=42"
        )
        let v1Line = "[00:00:00.000] [INFO] [UnitTest] v1-readable-line"
        let v2Line = codec.encodeLine(
            timestamp: "00:00:00.001",
            level: .debug,
            category: "UnitTest",
            envelope: envelope
        )
        let malformedLine =
            "[00:00:00.002] [WARN] [UnitTest] privacy=v2 m=broken e=- f=-"
        let data = Data(
            (v1Line + "\r\n" + v2Line + "\n" + malformedLine + "\r\n").utf8
        )
        try data.write(to: logURL)
        let snapshot = RuntimeLogFileStore.ReadSnapshot(
            fileOffsetsByPath: [logURL.path: data.count],
            storageEpoch: 0
        )

        let lines = try RuntimeLogTailReader(chunkSizeBytes: 7).readLines(
            from: [logURL],
            limit: 300,
            minimumLevel: .debug,
            previousSnapshot: nil,
            currentSnapshot: snapshot,
            mode: .full,
            cancellation: RuntimeLogReadCancellation()
        )

        XCTAssertEqual(lines[0], v1Line)
        XCTAssertEqual(
            lines[1],
            "[00:00:00.001] [DEBUG] [UnitTest] "
                + codec.expandedMessage(for: envelope)
        )
        XCTAssertEqual(lines[2], malformedLine)
    }

    func testRuntimeLogPrivacyV2ProjectionEncodingFitsQuarterOfExpandedBytes() {
        let formatter = RuntimeLogPrivacyFormatter(
            keyData: Data(repeating: 0x7A, count: 32)
        )
        let codec = RuntimeLogPrivacyCodec()
        let message = """
        projection repair committed bundleID=com.example.browser appIdentifier=browser-runtime generation=184467 updatedWindowIDs=101,102,103,104 visibleWindowIDs=101,103 removedWindowIDs=99,100 selectedTitle=Quarterly Planning – Confidential selectedPath=/Users/example/Documents/private-plan.txt selectedURL=https://example.invalid/private/search query=confidential planning errorDescription=none fallbackReason=stable
        """
        let envelope = formatter.makeEnvelope(for: message)
        let compactByteCount = codec.encode(envelope).utf8.count
        let expandedByteCount = codec.expandedMessage(for: envelope).utf8.count

        XCTAssertLessThanOrEqual(compactByteCount * 4, expandedByteCount)
    }

    func testRuntimeLogStoreUpgradesV1MarkerWithoutReplacingLogsOrKey()
        throws
    {
        let fixture = try RuntimeLogPrivacyV2Fixture(createLogsDirectory: false)
        defer { fixture.remove() }
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: fixture.logsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        let v1MarkerURL = fixture.logsDirectory.appendingPathComponent(
            RuntimeLogFileStore.privacyFormatMarkerFileName
        )
        let v2MarkerURL = fixture.logsDirectory.appendingPathComponent(
            RuntimeLogFileStore.privacyV2FormatMarkerFileName
        )
        let keyURL = fixture.logsDirectory.appendingPathComponent(
            RuntimeLogFileStore.privacyFingerprintKeyFileName
        )
        let logURL = fixture.logsDirectory.appendingPathComponent(
            fixture.managedLogFileName,
            isDirectory: false
        )
        let keyData = Data((0..<32).map(UInt8.init))
        let oldLogData = Data(
            "[00:00:00.000] [ERROR] [UnitTest] v1-safe-record\n".utf8
        )
        try Data("1\n".utf8).write(to: v1MarkerURL)
        try keyData.write(to: keyURL)
        try oldLogData.write(to: logURL)
        for url in [v1MarkerURL, keyURL, logURL] {
            try fileManager.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: url.path
            )
        }

        _ = RuntimeLogFileStore(logsDirectoryURL: fixture.logsDirectory)

        XCTAssertEqual(try Data(contentsOf: keyURL), keyData)
        XCTAssertEqual(try Data(contentsOf: logURL), oldLogData)
        XCTAssertTrue(fileManager.fileExists(atPath: v1MarkerURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: v2MarkerURL.path))
        XCTAssertEqual(try fixture.permissions(at: fixture.logsDirectory), 0o700)
        for url in [v1MarkerURL, v2MarkerURL, keyURL, logURL] {
            XCTAssertEqual(try fixture.permissions(at: url), 0o600)
        }
    }
}

private final class RuntimeLogPrivacyV2Fixture {
    let root: URL
    let logsDirectory: URL

    init(createLogsDirectory: Bool = true) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FlowTabRuntimeLogPrivacyV2-\(UUID().uuidString)",
            isDirectory: true
        )
        logsDirectory = root.appendingPathComponent("FlowTab/logs", isDirectory: true)
        if createLogsDirectory {
            try FileManager.default.createDirectory(
                at: logsDirectory,
                withIntermediateDirectories: true
            )
        }
    }

    var managedLogFileName: String {
        let displayName = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String
        let bundleName = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleName"
        ) as? String
        let rawName = (displayName?.isEmpty == false ? displayName : bundleName)
            ?? "FlowTab"
        let sanitized = rawName.replacingOccurrences(
            of: #"[^A-Za-z0-9_-]"#,
            with: "_",
            options: .regularExpression
        )
        return "\(sanitized)_20260101_000000.log"
    }

    func rawLogLines() throws -> [String] {
        let logURLs = try FileManager.default.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try logURLs.flatMap { url in
            try String(contentsOf: url, encoding: .utf8)
                .split(whereSeparator: \.isNewline)
                .map(String.init)
        }
    }

    func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(
            attributes[.posixPermissions] as? NSNumber
        ).intValue & 0o777
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
