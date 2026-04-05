import SwiftUI

enum HomePageLayout {
    static let alignedTopInset: CGFloat = 18
}

struct HomeBackdropView: View {
    @ObservedObject private var systemTheme = SystemThemeState.shared
    @AppStorage(AppPreferenceKeys.themeMode)
    private var themeModeRaw = ThemePreferencesStore.defaultMode.rawValue

    private var colorScheme: ColorScheme {
        ThemePreferencesStore.resolve(rawValue: themeModeRaw)
            .resolvedColorScheme(systemColorScheme: systemTheme.colorScheme)
    }

    var body: some View {
        (colorScheme == .dark ? Color.black : Color.white)
            .ignoresSafeArea()
    }
}

struct HomeSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    private var cardBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.13, green: 0.13, blue: 0.15).opacity(0.96)
        }
        return Color(red: 0.965, green: 0.97, blue: 0.978)
    }

    private var cardBorderColor: Color {
        if colorScheme == .dark {
            return Color.primary.opacity(0.1)
        }
        return Color.black.opacity(0.14)
    }

    private var cardShadowColor: Color {
        if colorScheme == .dark {
            return .clear
        }
        return Color.black.opacity(0.05)
    }

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackgroundColor)
                .shadow(color: cardShadowColor, radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        )
    }
}

enum FlowActionButtonTone: Equatable {
    case grayDominant
    case blueDominant
}

struct FlowActionButton: View {
    let title: String
    let systemImage: String?
    let tone: FlowActionButtonTone
    let width: CGFloat?
    let accessibilityIdentifier: String?
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        tone: FlowActionButtonTone = .grayDominant,
        width: CGFloat? = nil,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.width = width
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    private var foregroundColor: Color {
        tone == .blueDominant ? .white : .primary.opacity(0.78)
    }

    private var backgroundFill: LinearGradient {
        switch tone {
        case .grayDominant:
            return LinearGradient(
                stops: [
                    .init(color: Color.primary.opacity(0.12), location: 0.0),
                    .init(color: Color.primary.opacity(0.09), location: 0.75),
                    .init(color: Color.accentColor.opacity(0.26), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .blueDominant:
            return LinearGradient(
                stops: [
                    .init(color: Color.accentColor.opacity(0.94), location: 0.0),
                    .init(color: Color.accentColor.opacity(0.76), location: 0.75),
                    .init(color: Color.primary.opacity(0.18), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var borderFill: LinearGradient {
        switch tone {
        case .grayDominant:
            return LinearGradient(
                stops: [
                    .init(color: Color.primary.opacity(0.24), location: 0.0),
                    .init(color: Color.primary.opacity(0.19), location: 0.75),
                    .init(color: Color.accentColor.opacity(0.36), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .blueDominant:
            return LinearGradient(
                stops: [
                    .init(color: Color.accentColor.opacity(0.55), location: 0.0),
                    .init(color: Color.accentColor.opacity(0.44), location: 0.75),
                    .init(color: Color.primary.opacity(0.28), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var shadowColor: Color {
        tone == .blueDominant ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.08)
    }

    var body: some View {
        let button = Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .frame(width: width)
            .foregroundStyle(foregroundColor)
            .background(
                Capsule()
                    .fill(backgroundFill)
            )
            .overlay(
                Capsule()
                    .stroke(borderFill, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: 6, y: 2)
        }
        .buttonStyle(.plain)

        if let accessibilityIdentifier {
            button.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            button
        }
    }
}
