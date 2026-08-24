import AppKit
import SwiftUI

struct HomeLayerRowView: View {
    let title: String
    let subtitle: String
    let trailing: String
    let icon: NSImage?
    let isTrailingLoading: Bool
    let badge: String?
    let badgeAccessibilityIdentifier: String?
    let isSelected: Bool

    init(
        title: String,
        subtitle: String,
        trailing: String,
        icon: NSImage? = nil,
        isTrailingLoading: Bool = false,
        badge: String? = nil,
        badgeAccessibilityIdentifier: String? = nil,
        isSelected: Bool
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.icon = icon
        self.isTrailingLoading = isTrailingLoading
        self.badge = badge
        self.badgeAccessibilityIdentifier = badgeAccessibilityIdentifier
        self.isSelected = isSelected
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .accessibilityIdentifier(badgeAccessibilityIdentifier ?? "")
                            .accessibilityLabel(badge)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.orange.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.orange.opacity(0.28), lineWidth: 1)
                            )
                    }
                }

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            trailingContent
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
        )
    }

    @ViewBuilder
    private var trailingContent: some View {
        if isTrailingLoading {
            ProgressView()
                .controlSize(.small)
                .frame(width: 22, height: 14, alignment: .center)
        } else {
            Text(trailing)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 22, alignment: .trailing)
        }
    }
}
