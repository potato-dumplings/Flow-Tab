import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum HomeAppIconProvider {
    private static let provider = AppIconProvider()

    static func icon(for app: RuntimeHomeAppSummary) -> NSImage {
        icon(
            appID: app.appID,
            bundleIdentifier: app.bundleIdentifier,
            bundleURL: app.bundleURL
        )
    }

    static func icon(
        appID: String,
        bundleIdentifier: String?,
        bundleURL: URL?
    ) -> NSImage {
        provider.icon(
            appID: appID,
            bundleIdentifier: bundleIdentifier,
            bundleURL: bundleURL
        ) ?? NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

enum HomeWindowTotal: Equatable {
    case loading
    case ready(Int)
}

struct HomeAccessibleText: NSViewRepresentable {
    let text: String
    let font: NSFont
    let textColor: NSColor
    let accessibilityIdentifier: String?

    var lineBreakMode: NSLineBreakMode = .byTruncatingTail
    var alignment: NSTextAlignment = .left

    func makeNSView(context _: Context) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.setAccessibilityElement(true)
        label.setAccessibilityRole(.staticText)
        return label
    }

    func updateNSView(_ label: NSTextField, context _: Context) {
        label.stringValue = text
        label.font = font
        label.textColor = textColor
        label.lineBreakMode = lineBreakMode
        label.alignment = alignment
        label.setAccessibilityIdentifier(accessibilityIdentifier)
        label.setAccessibilityLabel(text)
    }
}

struct HomeOverviewStats: Equatable {
    let totalApps: Int
    let visibleApps: Int
    let hiddenApps: Int
    let totalWindows: HomeWindowTotal

    static func make(
        appRows: [HomeAppRowPresentation],
        loadingWindowCountAppIDs: Set<String>
    ) -> HomeOverviewStats {
        let hiddenCount = appRows.filter(\.isHidden).count
        let windowTotal: HomeWindowTotal = loadingWindowCountAppIDs.isEmpty
            ? .ready(appRows.reduce(0) { $0 + $1.windowCount })
            : .loading

        return HomeOverviewStats(
            totalApps: appRows.count,
            visibleApps: appRows.count - hiddenCount,
            hiddenApps: hiddenCount,
            totalWindows: windowTotal
        )
    }

    static func make(
        appSummaries: [RuntimeHomeAppSummary],
        hiddenAppIDs: Set<String>,
        loadingWindowCountAppIDs: Set<String>
    ) -> HomeOverviewStats {
        let rows = HomeAppVisibilityPresentation(hiddenAppIDs: hiddenAppIDs)
            .appRows(runtimeSummaries: appSummaries, installedApps: [])
        return make(
            appRows: rows,
            loadingWindowCountAppIDs: loadingWindowCountAppIDs
        )
    }
}

struct HomeOverviewStatsBar: NSViewRepresentable {
    let stats: HomeOverviewStats
    let language: AppLanguage

    func makeNSView(context _: Context) -> HomeOverviewStatsBarView {
        HomeOverviewStatsBarView()
    }

    func updateNSView(_ view: HomeOverviewStatsBarView, context _: Context) {
        view.update(stats: stats, language: language)
    }
}

final class HomeOverviewStatsBarView: NSView {
    private let stackView = NSStackView()
    private let totalAppsItem = HomeOverviewStatItemView(
        accessibilityIdentifier: "flowtab.home.stats.total-apps"
    )
    private let visibleAppsItem = HomeOverviewStatItemView(
        accessibilityIdentifier: "flowtab.home.stats.visible-apps"
    )
    private let hiddenAppsItem = HomeOverviewStatItemView(
        accessibilityIdentifier: "flowtab.home.stats.hidden-apps"
    )
    private let totalWindowsItem = HomeOverviewStatItemView(
        accessibilityIdentifier: "flowtab.home.stats.total-windows"
    )
    private var dividerViews: [NSView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: HomePageLayout.bottomStatusHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func update(stats: HomeOverviewStats, language: AppLanguage) {
        totalAppsItem.update(
            title: AppStrings.text(.homeStatsTotalApps, language: language),
            value: "\(stats.totalApps)"
        )
        visibleAppsItem.update(
            title: AppStrings.text(.homeStatsVisibleApps, language: language),
            value: "\(stats.visibleApps)"
        )
        hiddenAppsItem.update(
            title: AppStrings.text(.homeStatsHiddenApps, language: language),
            value: "\(stats.hiddenApps)"
        )

        switch stats.totalWindows {
        case .loading:
            totalWindowsItem.update(
                title: AppStrings.text(.homeStatsTotalWindows, language: language),
                value: nil
            )
        case let .ready(count):
            totalWindowsItem.update(
                title: AppStrings.text(.homeStatsTotalWindows, language: language),
                value: "\(count)"
            )
        }
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        setAccessibilityElement(false)
        setAccessibilityIdentifier("flowtab.home.stats")

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 18

        addSubview(stackView)
        addStatItem(totalAppsItem)
        addDivider()
        addStatItem(visibleAppsItem)
        addDivider()
        addStatItem(hiddenAppsItem)
        addDivider()
        addStatItem(totalWindowsItem)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            visibleAppsItem.widthAnchor.constraint(equalTo: totalAppsItem.widthAnchor),
            hiddenAppsItem.widthAnchor.constraint(equalTo: totalAppsItem.widthAnchor),
            totalWindowsItem.widthAnchor.constraint(equalTo: totalAppsItem.widthAnchor)
        ])

        updateAppearance()
    }

    private func addStatItem(_ item: HomeOverviewStatItemView) {
        item.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(item)
    }

    private func addDivider() {
        let divider = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        dividerViews.append(divider)
        stackView.addArrangedSubview(divider)
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func updateAppearance() {
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.025).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.09).cgColor
        dividerViews.forEach { divider in
            divider.wantsLayer = true
            divider.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.09).cgColor
        }
    }
}

private final class HomeOverviewStatItemView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let accessibilityIdentifierValue: String

    init(accessibilityIdentifier: String) {
        self.accessibilityIdentifierValue = accessibilityIdentifier
        super.init(frame: .zero)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        self.accessibilityIdentifierValue = ""
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 39)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func update(title: String, value: String?) {
        titleLabel.stringValue = title
        setAccessibilityLabel(title)
        setAccessibilityValue(value ?? "loading")
        valueLabel.stringValue = value ?? ""
        valueLabel.isHidden = value == nil

        if value == nil {
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
            progressIndicator.isHidden = true
        }
    }

    private func buildViewHierarchy() {
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityIdentifier(accessibilityIdentifierValue)

        configure(label: titleLabel)
        configure(label: valueLabel)
        titleLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.setAccessibilityElement(false)

        valueLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.setAccessibilityElement(false)

        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.isHidden = true
        progressIndicator.setAccessibilityLabel("loading")

        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(progressIndicator)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),

            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 7),

            progressIndicator.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressIndicator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 7)
        ])

        updateAppearance()
    }

    private func configure(label: NSTextField) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func updateAppearance() {
        titleLabel.textColor = .secondaryLabelColor
        valueLabel.textColor = .labelColor
    }
}

struct HomePermissionStatusCard: View {
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool
    let language: AppLanguage
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HomePermissionStatusRow(
                title: AppStrings.text(.homePermissionAccessibility, language: language),
                isGranted: accessibilityTrusted,
                language: language,
                colorScheme: colorScheme,
                accessibilityIdentifier: "flowtab.sidebar.permission.accessibility"
            )
            HomePermissionStatusRow(
                title: AppStrings.text(.homePermissionScreenCapture, language: language),
                isGranted: screenCaptureTrusted,
                language: language,
                colorScheme: colorScheme,
                accessibilityIdentifier: "flowtab.sidebar.permission.screen-capture"
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(
            maxWidth: .infinity,
            minHeight: HomePageLayout.bottomStatusHeight,
            alignment: .leading
        )
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .accessibilityIdentifier("flowtab.sidebar.permission-status")
    }
}

enum HomePermissionStatusColors {
    static func titleTextColor(colorScheme: ColorScheme) -> NSColor {
        (colorScheme == .dark ? NSColor.white : NSColor.black).withAlphaComponent(0.86)
    }

    static func iconColor(isGranted: Bool) -> Color {
        Color(nsColor: isGranted ? .systemGreen : .systemOrange)
    }

    static func statusTextColor(isGranted: Bool) -> NSColor {
        isGranted ? .secondaryLabelColor : .systemOrange
    }
}

private struct HomePermissionStatusRow: View {
    let title: String
    let isGranted: Bool
    let language: AppLanguage
    let colorScheme: ColorScheme
    let accessibilityIdentifier: String

    private var titleTextColor: NSColor {
        HomePermissionStatusColors.titleTextColor(colorScheme: colorScheme)
    }

    private var statusTextColor: NSColor {
        HomePermissionStatusColors.statusTextColor(isGranted: isGranted)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                statusIcon
                titleText
                Spacer(minLength: 4)
                statusText
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 9) {
                    statusIcon
                    titleText
                }
                statusText
                    .padding(.leading, 23)
            }
        }
    }

    private var statusIcon: some View {
        Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(HomePermissionStatusColors.iconColor(isGranted: isGranted))
            .frame(width: 14)
    }

    private var titleText: some View {
        HomeAccessibleText(
            text: title,
            font: .systemFont(ofSize: 12, weight: .medium),
            textColor: titleTextColor,
            accessibilityIdentifier: accessibilityIdentifier
        )
        .frame(height: 15)
    }

    private var statusText: some View {
        HomeAccessibleText(
            text: AppStrings.text(
                isGranted
                    ? .homePermissionGranted
                    : .homePermissionMissing,
                language: language
            ),
            font: .systemFont(ofSize: 11, weight: .medium),
            textColor: statusTextColor,
            accessibilityIdentifier:
                "\(accessibilityIdentifier).status"
        )
        .frame(height: 14)
    }
}
