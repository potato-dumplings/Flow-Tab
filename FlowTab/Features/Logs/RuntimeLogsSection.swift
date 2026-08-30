import SwiftUI
import AppKit

struct DiagnosticsRefreshPolicy: Equatable {
    var lineLimit: Int
    var cachedReadDelayNanoseconds: UInt64

    static let runtimeLogs = DiagnosticsRefreshPolicy(
        lineLimit: 300,
        cachedReadDelayNanoseconds: 100_000_000
    )
}

@MainActor
final class RuntimeLogLinesViewModel: ObservableObject {
    @Published private(set) var lines: [String] = []
    @Published private(set) var isClearing = false

    private let diagnostics: any RuntimeLogLinesProviding
    private let refreshPolicy: DiagnosticsRefreshPolicy
    private var lineLimit: Int {
        refreshPolicy.lineLimit
    }
    private var changeObservation: RuntimeLogChangeObservation?
    private var reloadTask: Task<Void, Never>?
    private var reloadOwnerID: UUID?
    private var reloadOwnerGeneration: UInt64?
    private var restartsReloadAfterCancellation = false
    private var refreshGeneration: UInt64 = 0
    private var latestRequestedChangeGeneration: UInt64?
    private var requiresReload = false
    private var readSnapshot: RuntimeLogFileStore.ReadSnapshot?
    private var coveredChangeGeneration: UInt64 = 0
    private var cachedMinimumLevel: RuntimeLogLevel?
    private var isActive = false
    private var activeMinimumLevel: RuntimeLogLevel?

    init(
        diagnostics: any RuntimeLogLinesProviding = RuntimeDiagnostics.shared,
        refreshPolicy: DiagnosticsRefreshPolicy = .runtimeLogs
    ) {
        self.diagnostics = diagnostics
        self.refreshPolicy = refreshPolicy
    }

    func updateActivity(
        isActive: Bool,
        minimumLevel: RuntimeLogLevel
    ) {
        guard isActive else {
            guard self.isActive
                    || changeObservation != nil
                    || reloadTask != nil
            else { return }
            deactivate()
            return
        }

        guard !self.isActive || activeMinimumLevel != minimumLevel else {
            return
        }
        activate(minimumLevel: minimumLevel)
    }

    private func activate(minimumLevel: RuntimeLogLevel) {
        invalidateCurrentRefresh()
        if cachedMinimumLevel != minimumLevel {
            cachedMinimumLevel = minimumLevel
            lines = []
            readSnapshot = nil
            coveredChangeGeneration = 0
        }
        isActive = true
        activeMinimumLevel = minimumLevel
        let generation = refreshGeneration
        let observation = diagnostics.observeChanges(
            kinds: [.flushed, .cleared]
        ) { [weak self] change in
            Task { @MainActor [weak self] in
                self?.handleObservedChange(
                    change,
                    minimumLevel: minimumLevel,
                    refreshGeneration: generation
                )
            }
        }
        changeObservation = observation
        let requiresInitialRead = readSnapshot == nil
        requestReload(
            changeGeneration: observation.baselineGeneration,
            minimumLevel: minimumLevel,
            refreshGeneration: generation,
            force: requiresInitialRead
        )
    }

    func clearStoredLogs(minimumLevel: RuntimeLogLevel) async {
        guard isActive, !isClearing else { return }
        isClearing = true
        defer { isClearing = false }

        let generation = refreshGeneration
        do {
            let change = try await diagnostics.clearAndWait()
            guard isActive, generation == refreshGeneration else { return }
            lines = []
            readSnapshot = nil
            coveredChangeGeneration = change.generation
            requestReload(
                changeGeneration: change.generation,
                minimumLevel: minimumLevel,
                refreshGeneration: generation,
                force: true
            )
        } catch {
            guard isActive, generation == refreshGeneration else { return }
            requestReload(
                changeGeneration: coveredChangeGeneration,
                minimumLevel: minimumLevel,
                refreshGeneration: generation,
                force: true
            )
        }
    }

    private func deactivate() {
        isActive = false
        activeMinimumLevel = nil
        invalidateCurrentRefresh()
    }

    private func invalidateCurrentRefresh() {
        changeObservation?.cancel()
        changeObservation = nil
        reloadTask?.cancel()
        latestRequestedChangeGeneration = nil
        requiresReload = false
        refreshGeneration &+= 1
    }

    deinit {
        changeObservation?.cancel()
        reloadTask?.cancel()
    }

    private func requestReload(
        changeGeneration: UInt64,
        minimumLevel: RuntimeLogLevel,
        refreshGeneration: UInt64,
        force: Bool = false
    ) {
        guard isActive,
              activeMinimumLevel == minimumLevel,
              refreshGeneration == self.refreshGeneration
        else { return }
        if let latestRequestedChangeGeneration {
            self.latestRequestedChangeGeneration = max(
                latestRequestedChangeGeneration,
                changeGeneration
            )
        } else {
            latestRequestedChangeGeneration = changeGeneration
        }
        requiresReload = requiresReload || force
        guard reloadTask == nil else {
            if reloadOwnerGeneration != refreshGeneration {
                restartsReloadAfterCancellation = true
            }
            return
        }
        startReload(
            minimumLevel: minimumLevel,
            refreshGeneration: refreshGeneration,
            delaysCachedRead: readSnapshot != nil && !force
        )
    }

    private func startReload(
        minimumLevel: RuntimeLogLevel,
        refreshGeneration: UInt64,
        delaysCachedRead: Bool
    ) {
        let ownerID = UUID()
        reloadOwnerID = ownerID
        reloadOwnerGeneration = refreshGeneration
        reloadTask = Task { [weak self] in
            guard let self else { return }
            if delaysCachedRead {
                do {
                    try await Task.sleep(
                        nanoseconds:
                            refreshPolicy.cachedReadDelayNanoseconds
                    )
                } catch {
                    finishReload(ownerID: ownerID)
                    return
                }
            }
            await self.runReloadLoop(
                minimumLevel: minimumLevel,
                refreshGeneration: refreshGeneration
            )
            self.finishReload(ownerID: ownerID)
        }
    }

    private func runReloadLoop(
        minimumLevel: RuntimeLogLevel,
        refreshGeneration: UInt64
    ) async {
        var candidateLines = lines
        var candidateSnapshot = readSnapshot
        var candidateCoveredGeneration = coveredChangeGeneration
        var forceNextRead = requiresReload

        while !Task.isCancelled,
              isActive,
              activeMinimumLevel == minimumLevel,
              refreshGeneration == self.refreshGeneration,
              let requestedChangeGeneration =
                  latestRequestedChangeGeneration {
            let needsRead = forceNextRead
                || candidateSnapshot == nil
                || requestedChangeGeneration > candidateCoveredGeneration
            guard needsRead else {
                commitReload(
                    lines: candidateLines,
                    snapshot: candidateSnapshot,
                    coveredChangeGeneration: candidateCoveredGeneration
                )
                return
            }
            forceNextRead = false
            requiresReload = false

            let batch: RuntimeLogReadBatch
            do {
                batch = try await diagnostics.readRecentBatch(
                    limit: lineLimit,
                    minimumLevel: minimumLevel,
                    since: candidateSnapshot
                )
            } catch {
                guard !Task.isCancelled else { return }
                return
            }

            guard !Task.isCancelled else { return }
            guard isActive,
                  activeMinimumLevel == minimumLevel,
                  refreshGeneration == self.refreshGeneration
            else { return }

            switch batch.mode {
            case .full:
                candidateLines = batch.lines
            case .incremental:
                candidateLines.append(contentsOf: batch.lines)
                if candidateLines.count > lineLimit {
                    candidateLines.removeFirst(
                        candidateLines.count - lineLimit
                    )
                }
            }
            candidateSnapshot = batch.snapshot
            candidateCoveredGeneration = max(
                candidateCoveredGeneration,
                batch.coveredChangeGeneration
            )

            if let latestRequestedChangeGeneration,
               latestRequestedChangeGeneration > candidateCoveredGeneration {
                continue
            }
            commitReload(
                lines: candidateLines,
                snapshot: candidateSnapshot,
                coveredChangeGeneration: candidateCoveredGeneration
            )
            return
        }
    }

    private func handleObservedChange(
        _ change: RuntimeLogChange,
        minimumLevel: RuntimeLogLevel,
        refreshGeneration: UInt64
    ) {
        guard isActive,
              activeMinimumLevel == minimumLevel,
              refreshGeneration == self.refreshGeneration
        else { return }
        if change.kind == .cleared {
            lines = []
            readSnapshot = nil
        }
        requestReload(
            changeGeneration: change.generation,
            minimumLevel: minimumLevel,
            refreshGeneration: refreshGeneration,
            force: change.kind == .cleared
        )
    }

    private func commitReload(
        lines: [String],
        snapshot: RuntimeLogFileStore.ReadSnapshot?,
        coveredChangeGeneration: UInt64
    ) {
        self.lines = Array(lines.suffix(lineLimit))
        readSnapshot = snapshot
        self.coveredChangeGeneration = coveredChangeGeneration
        latestRequestedChangeGeneration = nil
        requiresReload = false
    }

    private func finishReload(ownerID: UUID) {
        guard reloadOwnerID == ownerID else { return }
        reloadTask = nil
        reloadOwnerID = nil
        reloadOwnerGeneration = nil

        let shouldRestart = restartsReloadAfterCancellation
            && isActive
            && latestRequestedChangeGeneration != nil
        restartsReloadAfterCancellation = false
        if shouldRestart, let activeMinimumLevel {
            startReload(
                minimumLevel: activeMinimumLevel,
                refreshGeneration: refreshGeneration,
                delaysCachedRead: readSnapshot != nil
            )
        }
    }
}

struct RuntimeLogsSection: View {
    @Binding var runtimeLogLevelRaw: String
    let lifecycle: HomeRetainedTabLifecycle
    let hotkeyShortcutText: String
    let appLanguage: AppLanguage
    let targetAppearance: NSAppearance

    @StateObject private var logsViewModel = RuntimeLogLinesViewModel()

    private var selectedLogLevel: RuntimeLogLevel {
        RuntimeLogPreferencesStore.resolve(rawValue: runtimeLogLevelRaw)
    }

    private func synchronizeLogLevelIfNeeded() {
        let resolved = RuntimeLogPreferencesStore.resolve(rawValue: runtimeLogLevelRaw)
        if resolved.rawValue != runtimeLogLevelRaw {
            runtimeLogLevelRaw = resolved.rawValue
        }
    }

    private func openLogsDirectory() {
        let logsURL = URL(fileURLWithPath: RuntimeDiagnostics.logsDirectoryPath, isDirectory: true)
        _ = NSWorkspace.shared.open(logsURL)
    }

    private func accessibilityIdentifier(forLogLine line: String, index: Int) -> String {
#if FLOWTAB_TESTING
        let seededCategoryToken = "[\(FlowTabUITestBootstrapper.seededLogCategory)]"
        if FlowTabTestLaunchOptions.isRunningUITests,
           line.contains(seededCategoryToken) {
            if line.contains("[DEBUG]") {
                return "flowtab.logs.line.seeded.debug"
            }
            if line.contains("[INFO]") {
                return "flowtab.logs.line.seeded.info"
            }
            if line.contains("[WARN]") {
                return "flowtab.logs.line.seeded.warn"
            }
            if line.contains("[ERROR]") {
                return "flowtab.logs.line.seeded.error"
            }
        }
#endif
        return "flowtab.logs.line.row.\(index)"
    }

    private var logLevelOptions: [FlowDropdownOption] {
        RuntimeLogLevel.allCases.map {
            FlowDropdownOption(id: $0.rawValue, title: $0.displayName)
        }
    }

    private var logActionButtonPresentation: FlowCompactActionButtonPresentation {
        let blue = NSColor(srgbRed: 58 / 255, green: 128 / 255, blue: 247 / 255, alpha: 1)
        return .compact(
            targetAppearance: targetAppearance,
            textColor: .white,
            backgroundColor: blue,
            hoverBackgroundColor: blue.withAlphaComponent(0.88),
            borderColor: blue
        )
    }

    var body: some View {
        FlowPageSectionCard(
            title: AppStrings.text(.logsSectionTitle, language: appLanguage),
            subtitle: AppStrings.text(.logsSectionSubtitle, language: appLanguage)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(AppStrings.text(.logsLevel, language: appLanguage))
                        .font(FlowTypography.swiftUI(.formLabel))
                    FlowDropdownRepresentable(
                        selectedID: $runtimeLogLevelRaw,
                        options: logLevelOptions,
                        presentation: .form(targetAppearance: targetAppearance),
                        accessibilityIdentifier: "flowtab.logs.level"
                    )
                    .frame(width: 120)
                }

                Text(AppStrings.text(.logsPrivacyNotice, language: appLanguage))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("flowtab.logs.privacy-notice")

                Text(
                    AppStrings.text(
                        .logsDirectory,
                        replacements: ["path": RuntimeDiagnostics.logsDirectoryPath],
                        language: appLanguage
                    )
                )
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    FlowCompactActionButton(
                        title: AppStrings.text(.logsOpenDirectory, language: appLanguage),
                        targetAppearance: targetAppearance,
                        presentation: logActionButtonPresentation,
                        accessibilityIdentifier: "flowtab.logs.open-directory"
                    ) {
                        openLogsDirectory()
                    }

                    FlowCompactActionButton(
                        title: AppStrings.text(.logsClear, language: appLanguage),
                        targetAppearance: targetAppearance,
                        presentation: logActionButtonPresentation,
                        accessibilityIdentifier: "flowtab.logs.clear"
                    ) {
                        Task {
                            await logsViewModel.clearStoredLogs(minimumLevel: selectedLogLevel)
                        }
                    }
                    .disabled(logsViewModel.isClearing)
                }

                ScrollView {
                    Group {
                        if logsViewModel.lines.isEmpty {
                            Text(
                                AppStrings.text(
                                    .logsEmptyHint,
                                    replacements: ["hotkey": hotkeyShortcutText],
                                    language: appLanguage
                                )
                            )
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("flowtab.logs.empty-hint")
                        } else {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(logsViewModel.lines.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .accessibilityIdentifier(accessibilityIdentifier(forLogLine: line, index: index))
                                        .accessibilityLabel(line)
                                        .accessibilityValue(line)
                                }
                            }
                            .accessibilityIdentifier("flowtab.logs.lines")
                            .accessibilityValue(logsViewModel.lines.joined(separator: "\n"))
                        }
                    }
                    .padding(8)
                }
                .frame(minHeight: 320, maxHeight: 440)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }
        }
        .onAppear {
            synchronizeLogLevelIfNeeded()
            logsViewModel.updateActivity(
                isActive: lifecycle.state == .active,
                minimumLevel: selectedLogLevel
            )
        }
        .onReceive(lifecycle.transitions) { state in
            logsViewModel.updateActivity(
                isActive: state == .active,
                minimumLevel: selectedLogLevel
            )
        }
        .onChange(of: runtimeLogLevelRaw) { newValue in
            let resolved = RuntimeLogPreferencesStore.resolve(rawValue: newValue)
            if newValue != resolved.rawValue {
                runtimeLogLevelRaw = resolved.rawValue
                return
            }
            logsViewModel.updateActivity(
                isActive: lifecycle.state == .active,
                minimumLevel: resolved
            )
        }
        .onDisappear {
            logsViewModel.updateActivity(
                isActive: false,
                minimumLevel: selectedLogLevel
            )
        }
    }
}
