import SwiftUI
import AppKit

struct DiagnosticsRefreshPolicy: Equatable {
    var lineLimit: Int

    static let runtimeLogs = DiagnosticsRefreshPolicy(
        lineLimit: 300
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
    private var refreshGeneration: UInt64 = 0
    private var latestRequestedChangeGeneration: UInt64?

    init(
        diagnostics: any RuntimeLogLinesProviding = RuntimeDiagnostics.shared,
        refreshPolicy: DiagnosticsRefreshPolicy = .runtimeLogs
    ) {
        self.diagnostics = diagnostics
        self.refreshPolicy = refreshPolicy
    }

    func start(minimumLevel: RuntimeLogLevel) {
        stop()
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let observation = diagnostics.observeChanges { [weak self] change in
            Task { @MainActor [weak self] in
                self?.requestReload(
                    changeGeneration: change.generation,
                    minimumLevel: minimumLevel,
                    refreshGeneration: generation
                )
            }
        }
        changeObservation = observation
        requestReload(
            changeGeneration: observation.baselineGeneration,
            minimumLevel: minimumLevel,
            refreshGeneration: generation
        )
    }

    func clearStoredLogs(minimumLevel: RuntimeLogLevel) async {
        guard !isClearing else { return }
        isClearing = true
        defer { isClearing = false }

        let generation = refreshGeneration
        do {
            let change = try await diagnostics.clearAndWait()
            guard generation == refreshGeneration else { return }
            lines = []
            requestReload(
                changeGeneration: change.generation,
                minimumLevel: minimumLevel,
                refreshGeneration: generation
            )
        } catch {
            guard generation == refreshGeneration else { return }
            start(minimumLevel: minimumLevel)
        }
    }

    func stop() {
        changeObservation?.cancel()
        changeObservation = nil
        reloadTask?.cancel()
        reloadTask = nil
        latestRequestedChangeGeneration = nil
        refreshGeneration &+= 1
    }

    deinit {
        changeObservation?.cancel()
        reloadTask?.cancel()
    }

    private func requestReload(
        changeGeneration: UInt64,
        minimumLevel: RuntimeLogLevel,
        refreshGeneration: UInt64
    ) {
        guard refreshGeneration == self.refreshGeneration else { return }
        if let latestRequestedChangeGeneration,
           changeGeneration <= latestRequestedChangeGeneration {
            return
        }
        latestRequestedChangeGeneration = changeGeneration
        guard reloadTask == nil else { return }
        reloadTask = Task { [weak self] in
            await self?.runReloadLoop(
                minimumLevel: minimumLevel,
                refreshGeneration: refreshGeneration
            )
        }
    }

    private func runReloadLoop(
        minimumLevel: RuntimeLogLevel,
        refreshGeneration: UInt64
    ) async {
        while !Task.isCancelled,
              refreshGeneration == self.refreshGeneration,
              let requestedChangeGeneration =
                  latestRequestedChangeGeneration {
            let nextLines = await diagnostics.readRecentLines(
                limit: lineLimit,
                minimumLevel: minimumLevel,
                since: nil
            )
            guard !Task.isCancelled else { return }
            guard refreshGeneration == self.refreshGeneration else { return }
            guard requestedChangeGeneration
                    == latestRequestedChangeGeneration
            else {
                continue
            }
            lines = nextLines
            reloadTask = nil
            return
        }
    }
}

struct RuntimeLogsSection: View {
    @Binding var runtimeLogLevelRaw: String
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
            logsViewModel.start(minimumLevel: selectedLogLevel)
        }
        .onChange(of: runtimeLogLevelRaw) { newValue in
            let resolved = RuntimeLogPreferencesStore.resolve(rawValue: newValue)
            if newValue != resolved.rawValue {
                runtimeLogLevelRaw = resolved.rawValue
                return
            }
            logsViewModel.start(minimumLevel: resolved)
        }
        .onDisappear {
            logsViewModel.stop()
        }
    }
}
