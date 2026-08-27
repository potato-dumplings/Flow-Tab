import Foundation

struct RuntimeLogStoragePolicy: Equatable {
    let maxFileSizeBytes: Int
    let maxLogFiles: Int
    let flushDelay: TimeInterval
    let immediateFlushThreshold: Int
    let readChunkSizeBytes: Int

    static let runtimeLogs = RuntimeLogStoragePolicy(
        maxFileSizeBytes: 1_000_000,
        maxLogFiles: 20,
        flushDelay: 0.05,
        immediateFlushThreshold: 120,
        readChunkSizeBytes: RuntimeLogTailReader.defaultChunkSizeBytes
    )
}

final class RuntimeLogFileStore {
    static let shared = RuntimeLogFileStore()
    static let privacyFingerprintKeyFileName = ".runtime-log-fingerprint-key"
    static let privacyFormatMarkerFileName = ".runtime-log-privacy-v1"
    static let directoryPermissions = 0o700
    static let filePermissions = 0o600
    static let fingerprintKeyByteCount = 32

    struct ReadSnapshot: Equatable {
        let fileOffsetsByPath: [String: Int]
        let storageEpoch: UInt64

        var fileSizesByPath: [String: Int] {
            fileOffsetsByPath
        }
    }

    private static let fileNameTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
    private static let logFilePrefix: String = {
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        let rawName = (displayName?.isEmpty == false ? displayName : bundleName) ?? "FlowTab"
        let sanitized = rawName.replacingOccurrences(
            of: #"[^A-Za-z0-9_-]"#,
            with: "_",
            options: .regularExpression
        )
        return "\(sanitized)_"
    }()
    private static let logFileExtension = ".log"

    private let queue = DispatchQueue(label: "FlowTab.RuntimeLogFileStore", qos: .utility)
    private let policy: RuntimeLogStoragePolicy
    private let tailReader: any RuntimeLogTailReading
    private let changeHub: RuntimeLogChangeHub
    let fileManager: FileManager
    let logsDirectoryURL: URL
    var activeLogURL: URL?

    private var pendingLines: [String] = []
    private var flushWorkItem: DispatchWorkItem?
    private var storageEpoch: UInt64 = 0
    private var storageReady = false

    var logsDirectoryPath: String {
        logsDirectoryURL.path
    }

    init(
        logsDirectoryURL: URL,
        fileManager: FileManager = .default,
        policy: RuntimeLogStoragePolicy = .runtimeLogs,
        tailReader: (any RuntimeLogTailReading)? = nil,
        changeHub: RuntimeLogChangeHub = RuntimeLogChangeHub()
    ) {
        self.fileManager = fileManager
        self.logsDirectoryURL = logsDirectoryURL
        self.policy = policy
        self.tailReader = tailReader
            ?? RuntimeLogTailReader(chunkSizeBytes: policy.readChunkSizeBytes)
        self.changeHub = changeHub
        activeLogURL = nil
        do {
            try prepareStorageLocked()
            try enforceMaxLogFilesLocked()
            storageReady = true
        } catch {
            storageReady = false
        }
    }

    private convenience init() {
        let fileManager = FileManager.default
        let fallbackURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fallbackURL
        self.init(
            logsDirectoryURL: baseURL.appendingPathComponent(
                "FlowTab/logs",
                isDirectory: true
            ),
            fileManager: fileManager
        )
    }

    func append(_ line: String) {
        queue.async {
            self.pendingLines.append(line)
            self.changeHub.publish(.appended)
            if self.pendingLines.count >= self.policy.immediateFlushThreshold {
                self.flushWorkItem?.cancel()
                self.flushWorkItem = nil
                self.flushLocked()
            } else {
                self.scheduleFlushLocked()
            }
        }
    }

    func loadOrCreatePrivacyFingerprintKey() -> Data {
        queue.sync {
            do {
                try ensureStorageReadyLocked()
                let keyURL = logsDirectoryURL.appendingPathComponent(
                    Self.privacyFingerprintKeyFileName,
                    isDirectory: false
                )
                if fileManager.fileExists(atPath: keyURL.path) {
                    let existingKey = try Data(contentsOf: keyURL)
                    if existingKey.count == Self.fingerprintKeyByteCount {
                        try secureFilePermissionsLocked(at: keyURL)
                        return existingKey
                    }
                }

                let keyData = Self.makeRandomFingerprintKey()
                try replaceSecureFileLocked(at: keyURL, contents: keyData)
                return keyData
            } catch {
                storageReady = false
                return Self.makeRandomFingerprintKey()
            }
        }
    }

    func clear() {
        queue.async {
            do {
                _ = try self.clearLocked()
            } catch {}
        }
    }

    @discardableResult
    func clearAndWait() async throws -> RuntimeLogChange {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try self.clearLocked())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func observeChanges(
        kinds: Set<RuntimeLogChangeKind>,
        _ observer: @escaping (RuntimeLogChange) -> Void
    ) -> RuntimeLogChangeObservation {
        changeHub.observe(kinds: kinds, observer)
    }

    func observeChanges(
        _ observer: @escaping (RuntimeLogChange) -> Void
    ) -> RuntimeLogChangeObservation {
        observeChanges(
            kinds: Set(RuntimeLogChangeKind.allCases),
            observer
        )
    }

    func makeReadSnapshot() async -> ReadSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                do {
                    try self.flushPendingLinesLocked()
                } catch {}
                continuation.resume(returning: self.makeReadSnapshotLocked())
            }
        }
    }

    func readRecentBatch(
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        since snapshot: ReadSnapshot? = nil
    ) async throws -> RuntimeLogReadBatch {
        let cancellation = RuntimeLogReadCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        try cancellation.checkCancellation()
                        try self.flushPendingLinesLocked()
                        try cancellation.checkCancellation()

                        let currentSnapshot = self.makeReadSnapshotLocked()
                        let mode = self.readMode(
                            since: snapshot,
                            currentSnapshot: currentSnapshot
                        )
                        let fileURLs = self.orderedLogFileURLsNewestFirstLocked()
                        let lines = try self.tailReader.readLines(
                            from: fileURLs,
                            limit: limit,
                            minimumLevel: minimumLevel,
                            previousSnapshot: snapshot,
                            currentSnapshot: currentSnapshot,
                            mode: mode,
                            cancellation: cancellation
                        )
                        try cancellation.checkCancellation()
                        continuation.resume(
                            returning: RuntimeLogReadBatch(
                                lines: lines,
                                snapshot: currentSnapshot,
                                coveredChangeGeneration:
                                    self.changeHub.currentGeneration,
                                mode: mode
                            )
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func readRecentLines(
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        since snapshot: ReadSnapshot? = nil
    ) async -> [String] {
        do {
            return try await readRecentBatch(
                limit: limit,
                minimumLevel: minimumLevel,
                since: snapshot
            ).lines
        } catch {
            return []
        }
    }

    private func clearLocked() throws -> RuntimeLogChange {
        flushWorkItem?.cancel()
        flushWorkItem = nil
        pendingLines.removeAll(keepingCapacity: false)
        try ensureStorageReadyLocked()
        do {
            try clearFilesLocked()
            storageEpoch &+= 1
            return changeHub.publish(.cleared)
        } catch {
            storageReady = false
            throw error
        }
    }

    private func scheduleFlushLocked() {
        guard flushWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.flushWorkItem = nil
            self.flushLocked()
        }
        flushWorkItem = workItem
        queue.asyncAfter(deadline: .now() + policy.flushDelay, execute: workItem)
    }

    private func flushLocked() {
        do {
            try flushPendingLinesLocked()
        } catch {
            storageReady = false
        }
    }

    private func flushPendingLinesLocked() throws {
        guard !pendingLines.isEmpty else {
            try ensureStorageReadyLocked()
            return
        }
        try ensureStorageReadyLocked()

        let lineCount = pendingLines.count
        let block = pendingLines.joined(separator: "\n") + "\n"
        do {
            let targetLogURL = try targetLogURLLocked(
                appendingByteCount: block.utf8.count
            )
            try appendToFileLocked(block, to: targetLogURL)
        } catch {
            storageReady = false
            activeLogURL = nil
            throw error
        }
        pendingLines.removeFirst(lineCount)
        changeHub.publish(.flushed)
    }

    private func ensureStorageReadyLocked() throws {
        guard !storageReady else { return }
        try prepareStorageLocked()
        try enforceMaxLogFilesLocked()
        storageReady = true
        storageEpoch &+= 1
    }

    private func appendToFileLocked(_ block: String, to url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try createSecureFileLocked(at: url, contents: Data(block.utf8))
            return
        }

        try secureFilePermissionsLocked(at: url)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(block.utf8))
    }

    private func targetLogURLLocked(appendingByteCount: Int) throws -> URL {
        let currentURL = try ensureActiveLogFileLocked()
        let currentSize = fileSizeLocked(for: currentURL)
        if currentSize + appendingByteCount <= policy.maxFileSizeBytes {
            return currentURL
        }
        return try createNewActiveLogFileLocked()
    }

    private func ensureActiveLogFileLocked() throws -> URL {
        if let activeLogURL, fileManager.fileExists(atPath: activeLogURL.path) {
            return activeLogURL
        }
        return try createNewActiveLogFileLocked()
    }

    private func createNewActiveLogFileLocked() throws -> URL {
        let timestamp = Self.fileNameTimestampFormatter.string(from: Date())
        var candidateName = "\(Self.logFilePrefix)\(timestamp)\(Self.logFileExtension)"
        var candidateURL = logsDirectoryURL.appendingPathComponent(
            candidateName,
            isDirectory: false
        )
        var suffix = 1

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateName = "\(Self.logFilePrefix)\(timestamp)-\(suffix)\(Self.logFileExtension)"
            candidateURL = logsDirectoryURL.appendingPathComponent(
                candidateName,
                isDirectory: false
            )
            suffix += 1
        }

        try createSecureFileLocked(at: candidateURL, contents: Data())
        activeLogURL = candidateURL
        try enforceMaxLogFilesLocked()
        return candidateURL
    }

    private func enforceMaxLogFilesLocked() throws {
        let fileURLs = orderedLogFileURLsOldestFirstLocked()
        var existingCount = fileURLs.count
        guard existingCount > policy.maxLogFiles else { return }

        for url in fileURLs where existingCount > policy.maxLogFiles {
            if url == activeLogURL { continue }
            try fileManager.removeItem(at: url)
            existingCount -= 1
        }
    }

    private func clearFilesLocked() throws {
        var firstError: Error?
        for logURL in allManagedLogFileURLsLocked()
            where fileManager.fileExists(atPath: logURL.path) {
            do {
                try fileManager.removeItem(at: logURL)
            } catch {
                firstError = firstError ?? error
            }
        }
        activeLogURL = nil
        if let firstError {
            throw firstError
        }
    }

    private func readMode(
        since snapshot: ReadSnapshot?,
        currentSnapshot: ReadSnapshot
    ) -> RuntimeLogReadMode {
        guard let snapshot,
              snapshot.storageEpoch == currentSnapshot.storageEpoch,
              Set(snapshot.fileOffsetsByPath.keys).isSubset(
                  of: Set(currentSnapshot.fileOffsetsByPath.keys)
              )
        else {
            return .full
        }
        for (path, previousOffset) in snapshot.fileOffsetsByPath {
            guard let currentOffset = currentSnapshot.fileOffsetsByPath[path],
                  currentOffset >= previousOffset
            else {
                return .full
            }
        }
        return .incremental
    }

    private func makeReadSnapshotLocked() -> ReadSnapshot {
        var fileOffsetsByPath: [String: Int] = [:]
        for url in allManagedLogFileURLsLocked() {
            fileOffsetsByPath[url.path] = fileSizeLocked(for: url)
        }
        return ReadSnapshot(
            fileOffsetsByPath: fileOffsetsByPath,
            storageEpoch: storageEpoch
        )
    }

    func allManagedLogFileURLsLocked() -> [URL] {
        guard fileManager.fileExists(atPath: logsDirectoryURL.path),
              let urls = try? fileManager.contentsOfDirectory(
                  at: logsDirectoryURL,
                  includingPropertiesForKeys: [
                      .contentModificationDateKey,
                      .creationDateKey
                  ],
                  options: [.skipsHiddenFiles]
              )
        else {
            return []
        }
        return urls.filter {
            $0.lastPathComponent.hasPrefix(Self.logFilePrefix)
                && $0.lastPathComponent.hasSuffix(Self.logFileExtension)
        }
    }

    private func orderedLogFileURLsOldestFirstLocked() -> [URL] {
        Array(orderedLogFileURLsNewestFirstLocked().reversed())
    }

    private func orderedLogFileURLsNewestFirstLocked() -> [URL] {
        allManagedLogFileURLsLocked().sorted { leftURL, rightURL in
            let leftDate = modifiedDateLocked(for: leftURL) ?? Date.distantPast
            let rightDate = modifiedDateLocked(for: rightURL) ?? Date.distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return leftURL.lastPathComponent > rightURL.lastPathComponent
        }
    }

    private func modifiedDateLocked(for url: URL) -> Date? {
        guard let values = try? url.resourceValues(
            forKeys: [.contentModificationDateKey, .creationDateKey]
        ) else {
            return nil
        }
        return values.contentModificationDate ?? values.creationDate
    }

    private func fileSizeLocked(for url: URL) -> Int {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return size.intValue
    }
}
