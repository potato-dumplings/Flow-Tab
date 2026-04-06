import AppKit
import SwiftUI
import FlowTabCore

struct WindowPreviewCard: View {
    let image: NSImage?
    let title: String
    let appIcon: NSImage?
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private let titleAreaHeight: CGFloat = 26
    private var previewAreaHeight: CGFloat {
        max(84, height - titleAreaHeight)
    }
    private var previewBorderColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.accentColor.opacity(0.95) : Color.accentColor.opacity(0.72)
        }
        return colorScheme == .dark ? Color.white.opacity(0.20) : Color.primary.opacity(0.12)
    }
    private var previewBorderWidth: CGFloat {
        if isSelected {
            return colorScheme == .dark ? 2.6 : 2.1
        }
        return 1
    }
    private var previewGlowColor: Color {
        guard isSelected else { return .clear }
        return colorScheme == .dark ? Color.accentColor.opacity(0.42) : Color.accentColor.opacity(0.18)
    }
    private var titleForegroundColor: Color {
        if colorScheme == .dark {
            return isSelected ? Color.white.opacity(0.98) : Color.white.opacity(0.80)
        }
        return isSelected ? Color.primary : Color.primary.opacity(0.86)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    (colorScheme == .dark ? Color.black : Color.white)

                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 84, height: 84)
                            .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                    }
                }
            }
            .frame(width: width, height: previewAreaHeight)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(previewBorderColor, lineWidth: previewBorderWidth)
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .inset(by: 1)
                            .stroke(
                                colorScheme == .dark ? Color.white.opacity(0.24) : Color.white.opacity(0.16),
                                lineWidth: 0.8
                            )
                    }
                }
            )
            .shadow(color: previewGlowColor, radius: isSelected ? 14 : 0, y: 0)
            .shadow(color: .black.opacity(isSelected ? 0.16 : 0.12), radius: isSelected ? 12 : 10, y: 5)

            Text(title)
                .lineLimit(1)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(titleForegroundColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 4)
        }
        .frame(width: width, height: height, alignment: .top)
    }
}

struct WindowOnlyPreviewCard: View {
    let image: NSImage?
    let title: String
    let appIcon: NSImage?
    let titleBarStyle: WindowTitleBarStyleGuess?
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private let titleAreaHeight: CGFloat = 30
    private var previewAreaHeight: CGFloat {
        max(1, height - titleAreaHeight)
    }
    private var fallbackAppIconSize: CGFloat {
        max(42, min(96, min(width, previewAreaHeight) * 0.24))
    }
    private var usesDarkTitleBar: Bool {
        if let titleBarStyle {
            return titleBarStyle == .dark
        }
        return colorScheme == .dark
    }
    private var titleForegroundColor: Color {
        if usesDarkTitleBar {
            return Color.white.opacity(isSelected ? 0.98 : 0.92)
        }
        return Color.black.opacity(isSelected ? 0.84 : 0.74)
    }
    private var titleBarBackgroundColor: Color {
        if usesDarkTitleBar {
            return Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 1.0))
        }
        return Color(nsColor: NSColor(calibratedWhite: 0.97, alpha: 1.0))
    }
    private var titleBarDividerColor: Color {
        if usesDarkTitleBar {
            return Color.white.opacity(0.14)
        }
        return Color.black.opacity(0.12)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .lineLimit(1)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(titleForegroundColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 10)
                .frame(height: titleAreaHeight)
                .background(titleBarBackgroundColor)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(titleBarDividerColor)
                        .frame(height: 1)
                }
                .zIndex(1)

            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    if colorScheme == .dark {
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        Color.white
                    }
                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: fallbackAppIconSize, height: fallbackAppIconSize)
                            .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
                    } else {
                        Image(systemName: "macwindow")
                            .font(.system(size: 52, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: width, height: previewAreaHeight)
            .clipped()
        }
        .frame(width: width, height: height, alignment: .top)
        .background(Color.black.opacity(usesDarkTitleBar ? 0.20 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.28),
                    lineWidth: isSelected ? 2.1 : 1.0
                )
        )
        .shadow(
            color: Color.black.opacity(isSelected ? 0.22 : 0.12),
            radius: isSelected ? 14 : 9,
            y: isSelected ? 8 : 5
        )
    }
}

extension AnyTransition {
    static var appQuitRemoval: AnyTransition {
        let removal = AnyTransition.opacity
            .combined(with: .scale(scale: 0.72, anchor: .center))
        let insertion = AnyTransition.opacity
        return .asymmetric(insertion: insertion, removal: removal)
    }
}

struct AppTileView: View {
    let app: AppSwitchCandidate
    let isSelected: Bool
    let isTerminating: Bool
    let size: CGFloat
    let icon: NSImage?

    var body: some View {
        let cornerRadius = max(1, min(16, size * 0.18))
        let iconSize = max(1, min(56, size * 0.58))
        let fallbackFontSize = max(1, min(28, size * 0.32))
        let fallbackDotSize = max(1, size * 0.38)

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.1),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
            } else {
                if size >= 11 {
                    Text(app.displayName.prefix(1).uppercased())
                        .font(.system(size: fallbackFontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                } else {
                    Circle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: fallbackDotSize, height: fallbackDotSize)
                }
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isTerminating ? 0.96 : 1.0)
        .opacity(isTerminating ? 0.9 : 1.0)
        .saturation(isTerminating ? 0.88 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isTerminating)
    }
}
