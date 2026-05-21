import AppKit
import SwiftUI
import FlowTabCore

struct SwitcherSearchLayoutMeasurements: Equatable {
    let presentationHeaderHeight: CGFloat
    let resultRowHeight: CGFloat
}

enum SwitcherPanelLayoutMetrics {
    static let rootPadding: CGFloat = 16
    static let bodyHorizontalPadding: CGFloat = 16
    static let bodyVerticalPadding: CGFloat = 14
    static let bodySpacing: CGFloat = 12

    static var horizontalInset: CGFloat {
        rootPadding * 2 + bodyHorizontalPadding * 2
    }

    enum Search {
        static let fallbackPresentationHeaderHeight: CGFloat = 46
        static let fallbackResultRowHeight: CGFloat = 40
        static let resultRowSpacing: CGFloat = 8
        static let resultListPadding: CGFloat = 2
        static let visibleRowLimit = 8

        static func visibleRowCount(for resultCount: Int) -> Int {
            max(1, min(resultCount, visibleRowLimit))
        }

        static func resultListHeight(
            visibleRowCount: Int,
            resultRowHeight: CGFloat = fallbackResultRowHeight
        ) -> CGFloat {
            let rowCount = max(1, visibleRowCount)
            return CGFloat(rowCount) * resultRowHeight
                + CGFloat(max(rowCount - 1, 0)) * resultRowSpacing
                + resultListPadding * 2
        }

        static func panelHeight(
            visibleRowCount: Int,
            measurements: SwitcherSearchLayoutMeasurements = .fallback
        ) -> CGFloat {
            SwitcherPanelLayoutMetrics.rootPadding * 2
                + SwitcherPanelLayoutMetrics.bodyVerticalPadding * 2
                + measurements.presentationHeaderHeight
                + SwitcherPanelLayoutMetrics.bodySpacing
                + resultListHeight(
                    visibleRowCount: visibleRowCount,
                    resultRowHeight: measurements.resultRowHeight
                )
        }
    }
}

extension SwitcherSearchLayoutMeasurements {
    static let fallback = SwitcherSearchLayoutMeasurements(
        presentationHeaderHeight: SwitcherPanelLayoutMetrics.Search.fallbackPresentationHeaderHeight,
        resultRowHeight: SwitcherPanelLayoutMetrics.Search.fallbackResultRowHeight
    )

    var normalized: SwitcherSearchLayoutMeasurements {
        SwitcherSearchLayoutMeasurements(
            presentationHeaderHeight: max(1, presentationHeaderHeight),
            resultRowHeight: max(1, resultRowHeight)
        )
    }
}

struct SearchInputHeader: View {
    let query: String
    let scope: SwitcherSearchScope
    let isInputFocused: Bool
    let hintText: String
    @Environment(\.colorScheme) private var colorScheme

    init(
        query: String,
        scope: SwitcherSearchScope,
        isInputFocused: Bool,
        hintText: String
    ) {
        self.query = query
        self.scope = scope
        self.isInputFocused = isInputFocused
        self.hintText = hintText
    }

    private var queryText: String {
        if query.isEmpty && !isInputFocused {
            return AppStrings.text(.panelInputPlaceholder)
        }
        return query
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(queryText)
                    .foregroundStyle(query.isEmpty && !isInputFocused ? .secondary : .primary)
                    .lineLimit(1)
                    .font(.system(size: 13, weight: .medium))

                Spacer(minLength: 8)

                Text(scope.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.08))
                    )
            }

            Text(hintText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(isInputFocused ? 0.95 : 0.78))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isInputFocused
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.78 : 0.58)
                        : Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.10),
                    lineWidth: isInputFocused ? 1.6 : 1
                )
        )
    }
}

struct SearchPresentationHeader: View {
    let query: String
    let cursorPosition: Int
    let scope: SwitcherSearchScope
    let isInputFocused: Bool
    let highlightedItem: SearchHeaderHighlightItem?
    let isSearchActive: Bool
    let onSearchInputChanged: (String, Int) -> Void
    let onSearchMarkedTextChanged: (Bool) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let inputLineHeight: CGFloat = 24

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                if query.isEmpty && !isInputFocused {
                    Text(AppStrings.text(.panelSearchLabel))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                SearchSystemTextInputBridge(
                    query: query,
                    cursorPosition: cursorPosition,
                    isSearchActive: isSearchActive,
                    showsInsertionPoint: isInputFocused,
                    onInputChanged: onSearchInputChanged,
                    onMarkedTextChanged: onSearchMarkedTextChanged
                )
                .opacity(query.isEmpty && !isInputFocused ? 0.01 : 1)
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, minHeight: inputLineHeight, maxHeight: inputLineHeight, alignment: .leading)
            .clipped()

            if let highlightedItem {
                HStack(spacing: 8) {
                    Text("—")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text(highlightedItem.title)
                        .lineLimit(1)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.30 : 0.20))
                )
            }

            Group {
                if let icon = highlightedItem?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.13))
                        .overlay(
                            Image(systemName: scope == .app ? "app.badge.fill" : "macwindow")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 3, y: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isInputFocused
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.76 : 0.54)
                        : Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.10),
                    lineWidth: isInputFocused ? 1.6 : 1
                )
        )
    }
}

struct SearchEmptyState: View {
    let scope: SwitcherSearchScope

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: scope == .app ? "app.badge" : "macwindow.on.rectangle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
            Text(AppStrings.text(.panelNoResult))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct SearchAppRow: View {
    let item: SearchAppResultItem
    let icon: NSImage?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.14))
                        .overlay(
                            Text(item.app.displayName.prefix(1).uppercased())
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(item.app.displayName)
                .lineLimit(1)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(
                    item.isSelected
                        ? Color.primary
                        : Color.primary.opacity(0.92)
                )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    item.isSelected
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.16)
                        : Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.04)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    item.isSelected
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.64 : 0.45)
                        : Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08),
                    lineWidth: item.isSelected ? 1.4 : 1
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.app.displayName))
        .accessibilityIdentifier("flowtab.switcher.search.app.\(item.app.id.flowTabAccessibilityIdentifierComponent)")
    }
}

struct SearchWindowRow: View {
    let item: SearchWindowResultItem
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.14))
                        .overlay(
                            Image(systemName: "app")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(1)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(
                        item.isSelected
                            ? Color.primary
                            : Color.primary.opacity(0.92)
                    )
                Text(item.appName)
                    .lineLimit(1)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    item.isSelected
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.16)
                        : Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.04)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    item.isSelected
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.64 : 0.45)
                        : Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08),
                    lineWidth: item.isSelected ? 1.4 : 1
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(item.title), \(item.appName)"))
        .accessibilityIdentifier("flowtab.switcher.search.window.\(item.id.flowTabAccessibilityIdentifierComponent)")
    }
}
