import SwiftUI
import AppKit

struct DiagnosticsRefreshPolicy: Equatable {
    var intervalNanoseconds: UInt64
    var lineLimit: Int

    static let runtimeLogs = DiagnosticsRefreshPolicy(
        intervalNanoseconds: 1_000_000_000,
        lineLimit: 300
    )
}

@MainActor
private final class RuntimeLogLinesViewModel: ObservableObject {
    @Published private(set) var lines: [String] = []
    @Published private(set) var isClearing = false

    private let refreshPolicy: DiagnosticsRefreshPolicy = .runtimeLogs
    private var lineLimit: Int {
        refreshPolicy.lineLimit
    }
    private var refreshIntervalNs: UInt64 {
        refreshPolicy.intervalNanoseconds
    }
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0

    func start(minimumLevel: RuntimeLogLevel) {
        stop()
        refreshGeneration &+= 1
        let generation = refreshGeneration
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.runRefreshLoop(minimumLevel: minimumLevel, generation: generation)
        }
    }

    func clearStoredLogs(minimumLevel: RuntimeLogLevel) async {
        guard !isClearing else { return }
        isClearing = true
        defer { isClearing = false }

        stop()
        do {
            try await RuntimeDiagnostics.shared.clearAndWait()
            lines = []
        } catch {
            await reload(minimumLevel: minimumLevel, generation: refreshGeneration)
        }
        start(minimumLevel: minimumLevel)
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshGeneration &+= 1
    }

    deinit {
        refreshTask?.cancel()
    }

    private func runRefreshLoop(minimumLevel: RuntimeLogLevel, generation: UInt64) async {
        await reload(minimumLevel: minimumLevel, generation: generation)
        while !Task.isCancelled, generation == refreshGeneration {
            try? await Task.sleep(nanoseconds: refreshIntervalNs)
            await reload(minimumLevel: minimumLevel, generation: generation)
        }
    }

    private func reload(minimumLevel: RuntimeLogLevel, generation: UInt64) async {
        let nextLines = await RuntimeDiagnostics.shared.readRecentLines(
            limit: lineLimit,
            minimumLevel: minimumLevel
        )
        guard !Task.isCancelled else { return }
        guard generation == refreshGeneration else { return }
        lines = nextLines
    }
}

struct RuntimeLogsSection: View {
    @Binding var enableVerboseDiagnostics: Bool
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
        if line.contains("seeded-debug-log-") {
            return "flowtab.logs.line.seeded.debug"
        }
        if line.contains("seeded-info-log-") {
            return "flowtab.logs.line.seeded.info"
        }
        if line.contains("seeded-warn-log-") {
            return "flowtab.logs.line.seeded.warn"
        }
        if line.contains("seeded-error-log-") {
            return "flowtab.logs.line.seeded.error"
        }
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
                Toggle(isOn: $enableVerboseDiagnostics) {
                    Text(AppStrings.text(.logsEnableVerbose, language: appLanguage))
                        .font(FlowTypography.swiftUI(.formLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
                    .toggleStyle(.switch)

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
