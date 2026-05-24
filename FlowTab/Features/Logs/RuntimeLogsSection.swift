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

    private static var persistedClearSnapshot: RuntimeLogFileStore.ReadSnapshot?

    private let refreshPolicy: DiagnosticsRefreshPolicy = .runtimeLogs
    private var lineLimit: Int {
        refreshPolicy.lineLimit
    }
    private var refreshIntervalNs: UInt64 {
        refreshPolicy.intervalNanoseconds
    }
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0

    private var clearSnapshot: RuntimeLogFileStore.ReadSnapshot? {
        get { Self.persistedClearSnapshot }
        set { Self.persistedClearSnapshot = newValue }
    }

    func start(minimumLevel: RuntimeLogLevel) {
        stop()
        refreshGeneration &+= 1
        let generation = refreshGeneration
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.runRefreshLoop(minimumLevel: minimumLevel, generation: generation)
        }
    }

    func clearDisplayedOutput(minimumLevel: RuntimeLogLevel) {
        stop()
        lines = []
        refreshGeneration &+= 1
        let generation = refreshGeneration
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await RuntimeDiagnostics.shared.makeReadSnapshot()
            guard !Task.isCancelled else { return }
            guard generation == self.refreshGeneration else { return }
            self.clearSnapshot = snapshot
            await self.runRefreshLoop(minimumLevel: minimumLevel, generation: generation)
        }
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
            minimumLevel: minimumLevel,
            since: clearSnapshot
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

    private var logsActionButtonTint: Color {
        Color(.sRGB, red: 58 / 255, green: 128 / 255, blue: 247 / 255, opacity: 1)
    }

    private struct LogsActionButtonStyle: ButtonStyle {
        let tint: Color

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(configuration.isPressed ? 0.85 : 1))
                )
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    var body: some View {
        HomeSectionCard(
            title: AppStrings.text(.logsSectionTitle),
            subtitle: AppStrings.text(.logsSectionSubtitle)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $enableVerboseDiagnostics) {
                    Text(AppStrings.text(.logsEnableVerbose))
                        .fixedSize(horizontal: false, vertical: true)
                }
                    .toggleStyle(.switch)
                    .font(.system(size: 12))

                HStack(spacing: 10) {
                    Text(AppStrings.text(.logsLevel))
                        .font(.system(size: 12))
                    Picker(AppStrings.text(.logsLevel), selection: $runtimeLogLevelRaw) {
                        ForEach(RuntimeLogLevel.allCases) { level in
                            Text(level.displayName).tag(level.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                Text(
                    AppStrings.text(
                        .logsDirectory,
                        replacements: ["path": RuntimeDiagnostics.logsDirectoryPath]
                    )
                )
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Button(AppStrings.text(.logsOpenDirectory)) {
                        openLogsDirectory()
                    }
                    .buttonStyle(LogsActionButtonStyle(tint: logsActionButtonTint))
                    .accessibilityIdentifier("flowtab.logs.open-directory")

                    Button(AppStrings.text(.logsClear)) {
                        logsViewModel.clearDisplayedOutput(minimumLevel: selectedLogLevel)
                    }
                    .buttonStyle(LogsActionButtonStyle(tint: logsActionButtonTint))
                    .accessibilityIdentifier("flowtab.logs.clear")
                }

                ScrollView {
                    Group {
                        if logsViewModel.lines.isEmpty {
                            Text(
                                AppStrings.text(
                                    .logsEmptyHint,
                                    replacements: ["hotkey": hotkeyShortcutText]
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
