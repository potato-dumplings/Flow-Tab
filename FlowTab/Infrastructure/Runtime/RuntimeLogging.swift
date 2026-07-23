import Foundation

enum RuntimeLogLevel: String, CaseIterable, Comparable, Identifiable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"

    var id: String { rawValue }

    var displayName: String {
        rawValue
    }

    private var priority: Int {
        switch self {
        case .debug:
            return 0
        case .info:
            return 1
        case .warning:
            return 2
        case .error:
            return 3
        }
    }

    static func < (lhs: RuntimeLogLevel, rhs: RuntimeLogLevel) -> Bool {
        lhs.priority < rhs.priority
    }
}

enum RuntimeLogPreferencesStore {
    static let defaultLevel: RuntimeLogLevel = .error

    static func resolve(rawValue: String) -> RuntimeLogLevel {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return RuntimeLogLevel(rawValue: normalized) ?? defaultLevel
    }

    static func loadMinimumLevel(userDefaults: UserDefaults = .standard) -> RuntimeLogLevel {
        let rawValue = userDefaults.string(forKey: AppPreferenceKeys.runtimeLogLevel) ?? defaultLevel.rawValue
        let resolved = resolve(rawValue: rawValue)
        if rawValue != resolved.rawValue {
            userDefaults.set(resolved.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        }
        return resolved
    }
}

enum RuntimeLogCategory: String, CaseIterable, Identifiable {
    case activation = "Activation"
    case app = "App"
    case autoEnter = "AutoEnter"
    case ax = "AX"
    case axMatch = "AXMatch"
    case axObserver = "AXObserver"
    case hotKey = "HotKey"
    case inputTrace = "InputTrace"
    case manual = "Manual"
    case permission = "Permission"
    case preview = "Preview"
    case projection = "Projection"
    case recency = "Recency"
    case runtimeFacts = "RuntimeFacts"
    case search = "Search"
    case searchInput = "SearchInput"
    case searchModel = "SearchModel"
    case searchTrace = "SearchTrace"
    case session = "Session"
    case switcherLayout = "SwitcherLayout"
    case uiTest = "UITest"

    var id: String { rawValue }

    var isVerboseOnlyBelowWarning: Bool {
        switch self {
        case .activation,
             .autoEnter,
             .ax,
             .axMatch,
             .axObserver,
             .hotKey,
             .inputTrace,
             .manual,
             .preview,
             .projection,
             .recency,
             .runtimeFacts,
             .search,
             .searchInput,
             .searchModel,
             .searchTrace,
             .session,
             .switcherLayout:
            return true
        case .app,
             .permission,
             .uiTest:
            return false
        }
    }

    static func resolve(_ category: String) -> RuntimeLogCategory? {
        allCases.first { $0.rawValue == category }
    }
}

final class RuntimeDiagnostics {
    static let shared = RuntimeDiagnostics()
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private let fileStore: RuntimeLogFileStore
    private let privacyFormatter: RuntimeLogPrivacyFormatter

    init(fileStore: RuntimeLogFileStore = .shared) {
        self.fileStore = fileStore
        privacyFormatter = RuntimeLogPrivacyFormatter(
            keyData: fileStore.loadOrCreatePrivacyFingerprintKey()
        )
    }

    static func formattedTimestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    static var logsDirectoryPath: String {
        RuntimeLogFileStore.shared.logsDirectoryPath
    }

    func log(level: RuntimeLogLevel, category: String, message: String) {
        let timestamp = Date()
        let persistedMessage: String
#if FLOWTAB_TESTING
        let usesUnredactedMessages = FlowTabTestLaunchOptions.isRunningUITests
            && !FlowTabTestLaunchOptions.requiresRedactedRuntimeLogs
        persistedMessage = usesUnredactedMessages ? message : privacyFormatter.redact(message)
#else
        persistedMessage = privacyFormatter.redact(message)
#endif
        let displayLine = "[\(Self.formattedTimestamp(timestamp))] [\(level.rawValue)] [\(category)] \(persistedMessage)"
        fileStore.append(displayLine)
    }

    func makeReadSnapshot() async -> RuntimeLogFileStore.ReadSnapshot {
        await fileStore.makeReadSnapshot()
    }

    func readRecentLines(
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        since snapshot: RuntimeLogFileStore.ReadSnapshot? = nil
    ) async -> [String] {
        await fileStore.readRecentLines(limit: limit, minimumLevel: minimumLevel, since: snapshot)
    }

    func clear() {
        fileStore.clear()
    }

    func clearAndWait() async throws {
        try await fileStore.clearAndWait()
    }
}

final class RuntimeLogFileStore {
    static let shared = RuntimeLogFileStore()
    static let privacyFingerprintKeyFileName = ".runtime-log-fingerprint-key"
    static let privacyFormatMarkerFileName = ".runtime-log-privacy-v1"

    struct ReadSnapshot {
        let fileSizesByPath: [String: Int]
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
        let sanitized = rawName
            .replacingOccurrences(
                of: #"[^A-Za-z0-9_-]"#,
                with: "_",
                options: .regularExpression
            )
        return "\(sanitized)_"
    }()
    private static let logFileExtension = ".log"
    static let directoryPermissions = 0o700
    static let filePermissions = 0o600
    static let fingerprintKeyByteCount = 32

    private let queue = DispatchQueue(label: "FlowTab.RuntimeLogFileStore", qos: .utility)
    let fileManager: FileManager
    private let maxFileSizeBytes = 1_000_000
    private let maxLogFiles = 5
    private let flushDelay: TimeInterval = 0.05
    private let immediateFlushThreshold = 120
    let logsDirectoryURL: URL
    var activeLogURL: URL?
    private var pendingLines: [String] = []
    private var flushWorkItem: DispatchWorkItem?

    var logsDirectoryPath: String {
        logsDirectoryURL.path
    }

    init(logsDirectoryURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.logsDirectoryURL = logsDirectoryURL
        activeLogURL = nil
        try? prepareStorageLocked()
    }

    private convenience init() {
        let fileManager = FileManager.default
        let fallbackURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fallbackURL
        self.init(
            logsDirectoryURL: baseURL.appendingPathComponent("FlowTab/logs", isDirectory: true),
            fileManager: fileManager
        )
    }

    func append(_ line: String) {
        queue.async {
            self.pendingLines.append(line)
            if self.pendingLines.count >= self.immediateFlushThreshold {
                self.flushWorkItem?.cancel()
                self.flushWorkItem = nil
                self.flushLocked()
                return
            }
            self.scheduleFlushLocked()
        }
    }

    func loadOrCreatePrivacyFingerprintKey() -> Data {
        queue.sync {
            do {
                try prepareStorageLocked()
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
                return Self.makeRandomFingerprintKey()
            }
        }
    }

    func clear() {
        queue.async {
            self.flushWorkItem?.cancel()
            self.flushWorkItem = nil
            self.pendingLines.removeAll(keepingCapacity: false)
            try? self.clearFilesLocked()
        }
    }

    func clearAndWait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.flushWorkItem?.cancel()
                self.flushWorkItem = nil
                self.pendingLines.removeAll(keepingCapacity: false)
                do {
                    try self.clearFilesLocked()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func makeReadSnapshot() async -> ReadSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                try? self.prepareStorageLocked()
                self.flushWorkItem?.cancel()
                self.flushWorkItem = nil
                self.flushLocked()
                continuation.resume(returning: self.makeReadSnapshotLocked())
            }
        }
    }

    func readRecentLines(
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        since snapshot: ReadSnapshot? = nil
    ) async -> [String] {
        await withCheckedContinuation { continuation in
            queue.async {
                try? self.prepareStorageLocked()
                self.flushWorkItem?.cancel()
                self.flushWorkItem = nil
                self.flushLocked()
                let lines: [String]
                if let snapshot {
                    lines = self.readRecentLinesSinceSnapshotLocked(
                        limit: limit,
                        minimumLevel: minimumLevel,
                        snapshot: snapshot
                    )
                } else {
                    lines = self.readRecentLinesLocked(limit: limit, minimumLevel: minimumLevel)
                }
                continuation.resume(returning: lines)
            }
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
        queue.asyncAfter(deadline: .now() + flushDelay, execute: workItem)
    }

    private func flushLocked() {
        guard !pendingLines.isEmpty else { return }
        let block = pendingLines.joined(separator: "\n") + "\n"
        pendingLines.removeAll(keepingCapacity: true)

        do {
            try prepareStorageLocked()
            let targetLogURL = try targetLogURLLocked(appendingByteCount: block.utf8.count)
            try appendToFileLocked(block, to: targetLogURL)
            try enforceMaxLogFilesLocked()
        } catch {}
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
        if currentSize + appendingByteCount <= maxFileSizeBytes {
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
        var candidateURL = logsDirectoryURL.appendingPathComponent(candidateName, isDirectory: false)
        var suffix = 1

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateName = "\(Self.logFilePrefix)\(timestamp)-\(suffix)\(Self.logFileExtension)"
            candidateURL = logsDirectoryURL.appendingPathComponent(candidateName, isDirectory: false)
            suffix += 1
        }

        try createSecureFileLocked(at: candidateURL, contents: Data())
        activeLogURL = candidateURL
        return candidateURL
    }

    private func enforceMaxLogFilesLocked() throws {
        let fileURLs = orderedLogFileURLsOldestFirstLocked()
        var existingCount = fileURLs.count
        guard existingCount > maxLogFiles else { return }

        for url in fileURLs {
            if existingCount <= maxLogFiles {
                break
            }
            if url == activeLogURL {
                continue
            }
            try fileManager.removeItem(at: url)
            existingCount -= 1
        }
    }

    private func fileSizeLocked(for url: URL) -> Int {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return size.intValue
    }

    private func clearFilesLocked() throws {
        var firstError: Error?
        for logURL in allManagedLogFileURLsLocked() {
            if fileManager.fileExists(atPath: logURL.path) {
                do {
                    try fileManager.removeItem(at: logURL)
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }
        }
        activeLogURL = nil
        if let firstError {
            throw firstError
        }
    }

    private func makeReadSnapshotLocked() -> ReadSnapshot {
        var fileSizesByPath: [String: Int] = [:]
        for url in allManagedLogFileURLsLocked() {
            fileSizesByPath[url.path] = fileSizeLocked(for: url)
        }
        return ReadSnapshot(fileSizesByPath: fileSizesByPath)
    }

    func allManagedLogFileURLsLocked() -> [URL] {
        guard fileManager.fileExists(atPath: logsDirectoryURL.path) else { return [] }
        guard let urls = try? fileManager.contentsOfDirectory(
            at: logsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.filter { isManagedLogFileNameLocked($0.lastPathComponent) }
    }

    private func isManagedLogFileNameLocked(_ fileName: String) -> Bool {
        fileName.hasPrefix(Self.logFilePrefix) && fileName.hasSuffix(Self.logFileExtension)
    }

    private func orderedLogFileURLsOldestFirstLocked() -> [URL] {
        Array(orderedLogFileURLsNewestFirstLocked().reversed())
    }

    private func readRecentLinesLocked(limit: Int, minimumLevel: RuntimeLogLevel) -> [String] {
        guard limit > 0 else { return [] }

        var recentLinesNewestFirst: [String] = []
        let targetCount = limit * 2
        let tailBytesPerFile = min(maxFileSizeBytes, max(64_000, limit * 1_024))

        for url in orderedLogFileURLsNewestFirstLocked() {
            let fileTailLines = readTailLinesLocked(from: url, maximumBytes: tailBytesPerFile)
            guard !fileTailLines.isEmpty else { continue }

            for line in fileTailLines.reversed() {
                if parsedLogLevelLocked(from: line) >= minimumLevel {
                    recentLinesNewestFirst.append(line)
                }
                if recentLinesNewestFirst.count >= targetCount {
                    break
                }
            }

            if recentLinesNewestFirst.count >= targetCount {
                break
            }
        }

        let limitedNewestFirst = Array(recentLinesNewestFirst.prefix(limit))
        return Array(limitedNewestFirst.reversed())
    }

    private func readRecentLinesSinceSnapshotLocked(
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        snapshot: ReadSnapshot
    ) -> [String] {
        guard limit > 0 else { return [] }

        var recentLinesNewestFirst: [String] = []
        let targetCount = limit * 2
        let tailBytesPerFile = min(maxFileSizeBytes, max(64_000, limit * 1_024))

        for url in orderedLogFileURLsNewestFirstLocked() {
            let currentSize = fileSizeLocked(for: url)
            guard currentSize > 0 else { continue }

            let originalStartOffset = min(snapshot.fileSizesByPath[url.path] ?? 0, currentSize)
            guard originalStartOffset < currentSize else { continue }

            let boundedStartOffset = max(originalStartOffset, currentSize - tailBytesPerFile)
            let shouldDropLeadingPartialLine = boundedStartOffset > originalStartOffset
            let appendedLines = readLinesLocked(
                from: url,
                startOffset: boundedStartOffset,
                dropLeadingPartialLine: shouldDropLeadingPartialLine
            )
            guard !appendedLines.isEmpty else { continue }

            for line in appendedLines.reversed() {
                if parsedLogLevelLocked(from: line) >= minimumLevel {
                    recentLinesNewestFirst.append(line)
                }
                if recentLinesNewestFirst.count >= targetCount {
                    break
                }
            }

            if recentLinesNewestFirst.count >= targetCount {
                break
            }
        }

        let limitedNewestFirst = Array(recentLinesNewestFirst.prefix(limit))
        return Array(limitedNewestFirst.reversed())
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
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]) else {
            return nil
        }
        return values.contentModificationDate ?? values.creationDate
    }

    private func readTailLinesLocked(from url: URL, maximumBytes: Int) -> [String] {
        guard maximumBytes > 0 else { return [] }
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: url.path),
            let sizeValue = attributes[.size] as? NSNumber
        else {
            return []
        }

        let fileSize = sizeValue.intValue
        guard fileSize > 0 else { return [] }

        let readSize = min(fileSize, maximumBytes)
        let offset = max(0, fileSize - readSize)

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            guard let data = try handle.readToEnd(), !data.isEmpty else {
                return []
            }
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                return []
            }

            var lines = text
                .split(whereSeparator: \.isNewline)
                .map(String.init)

            if offset > 0, !lines.isEmpty {
                lines.removeFirst()
            }
            return lines
        } catch {
            return []
        }
    }

    private func readLinesLocked(from url: URL, startOffset: Int, dropLeadingPartialLine: Bool) -> [String] {
        guard startOffset >= 0 else { return [] }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(startOffset))
            guard let data = try handle.readToEnd(), !data.isEmpty else {
                return []
            }
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                return []
            }

            var lines = text
                .split(whereSeparator: \.isNewline)
                .map(String.init)

            if dropLeadingPartialLine, !lines.isEmpty {
                lines.removeFirst()
            }

            return lines
        } catch {
            return []
        }
    }

    private func parsedLogLevelLocked(from line: String) -> RuntimeLogLevel {
        let segments = line.split(separator: "]", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return .info }
        let levelToken = segments[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard levelToken.hasPrefix("[") else { return .info }
        let rawValue = String(levelToken.dropFirst())
        return RuntimeLogLevel(rawValue: rawValue) ?? .info
    }
}

enum RuntimeLog {
    private static var isDiagnosticSessionActive: Bool {
        RuntimeDiagnosticSessionStore.readIsActive()
    }

    private static var minimumLevel: RuntimeLogLevel {
        RuntimeLogPreferencesStore.loadMinimumLevel()
    }

    private static func shouldRecord(level: RuntimeLogLevel, category: String) -> Bool {
        guard level >= minimumLevel else { return false }
        if level < .warning {
            return isDiagnosticSessionActive
        }
        return true
    }

    private static func emit(
        level: RuntimeLogLevel,
        category: String,
        message: @autoclosure () -> String
    ) {
        guard shouldRecord(level: level, category: category) else { return }
        RuntimeDiagnostics.shared.log(level: level, category: category, message: message())
    }

    private static func emit(
        level: RuntimeLogLevel,
        category: RuntimeLogCategory,
        message: @autoclosure () -> String
    ) {
        emit(level: level, category: category.rawValue, message: message())
    }

    static func debug(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: .debug, category: category, message: message())
    }

    static func debug(_ category: RuntimeLogCategory, _ message: @autoclosure () -> String) {
        emit(level: .debug, category: category, message: message())
    }

    static func isDebugEnabled(for category: String) -> Bool {
        shouldRecord(level: .debug, category: category)
    }

    static func isDebugEnabled(for category: RuntimeLogCategory) -> Bool {
        shouldRecord(level: .debug, category: category.rawValue)
    }

    static func info(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: .info, category: category, message: message())
    }

    static func info(_ category: RuntimeLogCategory, _ message: @autoclosure () -> String) {
        emit(level: .info, category: category, message: message())
    }

    static func warning(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: .warning, category: category, message: message())
    }

    static func warning(_ category: RuntimeLogCategory, _ message: @autoclosure () -> String) {
        emit(level: .warning, category: category, message: message())
    }

    static func error(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: .error, category: category, message: message())
    }

    static func error(_ category: RuntimeLogCategory, _ message: @autoclosure () -> String) {
        emit(level: .error, category: category, message: message())
    }
}
