import Foundation

enum RuntimeLogLevel: String, CaseIterable, Comparable, Identifiable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"

    var id: String { rawValue }
    var displayName: String { rawValue }

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

enum RuntimeLogRecordingPolicy {
    static func shouldRecord(
        level: RuntimeLogLevel,
        minimumLevel: RuntimeLogLevel
    ) -> Bool {
        level >= minimumLevel
    }
}

enum RuntimeLogPreferencesStore {
    static let defaultLevel: RuntimeLogLevel = .error

    static func resolve(rawValue: String) -> RuntimeLogLevel {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return RuntimeLogLevel(rawValue: normalized) ?? defaultLevel
    }

    static func loadMinimumLevel(
        userDefaults: UserDefaults = .standard
    ) -> RuntimeLogLevel {
        let rawValue = userDefaults.string(
            forKey: AppPreferenceKeys.runtimeLogLevel
        ) ?? defaultLevel.rawValue
        let resolved = resolve(rawValue: rawValue)
        if rawValue != resolved.rawValue {
            userDefaults.set(
                resolved.rawValue,
                forKey: AppPreferenceKeys.runtimeLogLevel
            )
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

    static func resolve(_ category: String) -> RuntimeLogCategory? {
        allCases.first { $0.rawValue == category }
    }
}

final class RuntimeDiagnostics: RuntimeLogLinesProviding {
    static let shared = RuntimeDiagnostics()
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private let fileStore: RuntimeLogFileStore
    private let privacyFormatter: RuntimeLogPrivacyFormatter
    private let privacyCodec = RuntimeLogPrivacyCodec()
#if FLOWTAB_TESTING
    private let usesUnredactedMessages: Bool
#endif

    init(fileStore: RuntimeLogFileStore = .shared) {
        self.fileStore = fileStore
#if FLOWTAB_TESTING
        usesUnredactedMessages = FlowTabTestLaunchOptions.isRunningUITests
            && !FlowTabTestLaunchOptions.requiresRedactedRuntimeLogs
#endif
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
#if FLOWTAB_TESTING
        if usesUnredactedMessages {
            let displayLine = "[\(Self.formattedTimestamp(timestamp))] "
                + "[\(level.rawValue)] [\(category)] \(message)"
            fileStore.append(displayLine)
            return
        }
        let persistedLine = privacyCodec.encodeLine(
            timestamp: Self.formattedTimestamp(timestamp),
            level: level,
            category: category,
            envelope: privacyFormatter.makeEnvelope(for: message)
        )
#else
        let persistedLine = privacyCodec.encodeLine(
            timestamp: Self.formattedTimestamp(timestamp),
            level: level,
            category: category,
            envelope: privacyFormatter.makeEnvelope(for: message)
        )
#endif
        fileStore.append(persistedLine)
    }

    func makeReadSnapshot() async -> RuntimeLogFileStore.ReadSnapshot {
        await fileStore.makeReadSnapshot()
    }

    func readRecentBatch(
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        since snapshot: RuntimeLogFileStore.ReadSnapshot? = nil
    ) async throws -> RuntimeLogReadBatch {
        try await fileStore.readRecentBatch(
            limit: limit,
            minimumLevel: minimumLevel,
            since: snapshot
        )
    }

    func readRecentLines(
        limit: Int,
        minimumLevel: RuntimeLogLevel,
        since snapshot: RuntimeLogFileStore.ReadSnapshot? = nil
    ) async -> [String] {
        await fileStore.readRecentLines(
            limit: limit,
            minimumLevel: minimumLevel,
            since: snapshot
        )
    }

    func clear() {
        fileStore.clear()
    }

    @discardableResult
    func clearAndWait() async throws -> RuntimeLogChange {
        try await fileStore.clearAndWait()
    }

    func observeChanges(
        kinds: Set<RuntimeLogChangeKind>,
        _ observer: @escaping (RuntimeLogChange) -> Void
    ) -> RuntimeLogChangeObservation {
        fileStore.observeChanges(kinds: kinds, observer)
    }

    func observeChanges(
        _ observer: @escaping (RuntimeLogChange) -> Void
    ) -> RuntimeLogChangeObservation {
        fileStore.observeChanges(observer)
    }
}

enum RuntimeLog {
    private static var minimumLevel: RuntimeLogLevel {
        RuntimeLogPreferencesStore.loadMinimumLevel()
    }

    private static func shouldRecord(level: RuntimeLogLevel) -> Bool {
        RuntimeLogRecordingPolicy.shouldRecord(
            level: level,
            minimumLevel: minimumLevel
        )
    }

    private static func emit(
        level: RuntimeLogLevel,
        category: String,
        message: @autoclosure () -> String
    ) {
        guard shouldRecord(level: level) else { return }
        RuntimeDiagnostics.shared.log(
            level: level,
            category: category,
            message: message()
        )
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

    static func debug(
        _ category: RuntimeLogCategory,
        _ message: @autoclosure () -> String
    ) {
        emit(level: .debug, category: category, message: message())
    }

    static func isDebugEnabled(for _: String) -> Bool {
        shouldRecord(level: .debug)
    }

    static func isDebugEnabled(for _: RuntimeLogCategory) -> Bool {
        shouldRecord(level: .debug)
    }

    static func info(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: .info, category: category, message: message())
    }

    static func info(
        _ category: RuntimeLogCategory,
        _ message: @autoclosure () -> String
    ) {
        emit(level: .info, category: category, message: message())
    }

    static func warning(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: .warning, category: category, message: message())
    }

    static func warning(
        _ category: RuntimeLogCategory,
        _ message: @autoclosure () -> String
    ) {
        emit(level: .warning, category: category, message: message())
    }

    static func error(_ category: String, _ message: @autoclosure () -> String) {
        emit(level: .error, category: category, message: message())
    }

    static func error(
        _ category: RuntimeLogCategory,
        _ message: @autoclosure () -> String
    ) {
        emit(level: .error, category: category, message: message())
    }
}
