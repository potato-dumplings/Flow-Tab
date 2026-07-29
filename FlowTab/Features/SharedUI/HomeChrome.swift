import AppKit
import SwiftUI

enum FlowPageLayout {
    static let horizontalInset: CGFloat = 24
    static let alignedTopInset: CGFloat = 18
    static let bottomInset: CGFloat = 17
}

enum HomePageLayout {
    static let bottomStatusHeight: CGFloat = 64
    static let layerListRowSpacing: CGFloat = 8
    static let appLayerRowHeight: CGFloat = 52
    static let windowLayerRowHeight: CGFloat = 44
}

struct FlowPageBackdropView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        (colorScheme == .dark ? Color.black : Color.white)
            .ignoresSafeArea()
    }
}

struct FlowPageSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let trailingText: String?
    let trailingAccessibilityIdentifier: String?
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

    init(
        title: String,
        subtitle: String,
        trailingText: String? = nil,
        trailingAccessibilityIdentifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailingText = trailingText
        self.trailingAccessibilityIdentifier = trailingAccessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if let trailingText {
                    HomeAccessibleText(
                        text: trailingText,
                        font: .systemFont(ofSize: 11, weight: .medium),
                        textColor: .secondaryLabelColor,
                        accessibilityIdentifier: trailingAccessibilityIdentifier
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(height: 14, alignment: .trailing)
                }
            }

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

enum FlowPageActionButtonTone: Equatable {
    case homeSecondaryGradient
    case homePrimaryGradient
    case solidAccent
}

struct FlowPageActionButton: View {
    let title: String
    let systemImage: String?
    let tone: FlowPageActionButtonTone
    let width: CGFloat?
    let height: CGFloat
    let horizontalPadding: CGFloat
    let accessibilityIdentifier: String?
    let pressAnimationPolicy: HomeControlPressAnimationPolicy
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        tone: FlowPageActionButtonTone = .homeSecondaryGradient,
        width: CGFloat? = nil,
        height: CGFloat = 30,
        horizontalPadding: CGFloat = 12,
        accessibilityIdentifier: String? = nil,
        pressAnimationPolicy: HomeControlPressAnimationPolicy = .default,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.width = width
        self.height = height
        self.horizontalPadding = horizontalPadding
        self.accessibilityIdentifier = accessibilityIdentifier
        self.pressAnimationPolicy = pressAnimationPolicy
        self.action = action
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
        }
        .buttonStyle(
            FlowPageActionButtonStyle(
                tone: tone,
                width: width,
                height: height,
                horizontalPadding: horizontalPadding,
                pressAnimationPolicy: pressAnimationPolicy
            )
        )

        if let accessibilityIdentifier {
            button.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            button
        }
    }
}

private struct FlowPageActionButtonStyle: ButtonStyle {
    private static let solidAccentColor = Color(
        .sRGB,
        red: 58 / 255,
        green: 128 / 255,
        blue: 247 / 255,
        opacity: 1
    )

    let tone: FlowPageActionButtonTone
    let width: CGFloat?
    let height: CGFloat
    let horizontalPadding: CGFloat
    let pressAnimationPolicy: HomeControlPressAnimationPolicy

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .frame(width: width)
            .foregroundStyle(foregroundColor)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundFill(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderFill, lineWidth: borderLineWidth)
            )
            .shadow(color: shadowColor, radius: 6, y: 2)
            .opacity(isEnabled ? 1 : 0.55)
            .animation(
                .easeOut(duration: pressAnimationPolicy.duration),
                value: configuration.isPressed
            )
    }

    private var cornerRadius: CGFloat {
        tone == .solidAccent ? 7 : height / 2
    }

    private var foregroundColor: Color {
        switch tone {
        case .homePrimaryGradient, .solidAccent:
            return .white
        case .homeSecondaryGradient:
            return .primary.opacity(0.78)
        }
    }

    private var borderFill: LinearGradient {
        switch tone {
        case .homeSecondaryGradient:
            return LinearGradient(
                stops: [
                    .init(color: Color.primary.opacity(0.24), location: 0.0),
                    .init(color: Color.primary.opacity(0.19), location: 0.75),
                    .init(color: Color.accentColor.opacity(0.36), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .homePrimaryGradient:
            return LinearGradient(
                stops: [
                    .init(color: Color.accentColor.opacity(0.55), location: 0.0),
                    .init(color: Color.accentColor.opacity(0.44), location: 0.75),
                    .init(color: Color.primary.opacity(0.28), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .solidAccent:
            return LinearGradient(
                stops: [
                    .init(color: Color.accentColor.opacity(0.94), location: 0.0),
                    .init(color: Color.accentColor.opacity(0.94), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var borderLineWidth: CGFloat {
        tone == .solidAccent ? 0 : 1
    }

    private var shadowColor: Color {
        switch tone {
        case .homePrimaryGradient:
            return Color.accentColor.opacity(0.20)
        case .homeSecondaryGradient:
            return Color.primary.opacity(0.08)
        case .solidAccent:
            return Color.clear
        }
    }

    private func backgroundFill(isPressed: Bool) -> LinearGradient {
        let pressedScale = isPressed ? 0.85 : 1
        switch tone {
        case .homeSecondaryGradient:
            return LinearGradient(
                stops: [
                    .init(color: Color.primary.opacity(0.12 * pressedScale), location: 0.0),
                    .init(color: Color.primary.opacity(0.09 * pressedScale), location: 0.75),
                    .init(color: Color.accentColor.opacity(0.26 * pressedScale), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .homePrimaryGradient:
            return LinearGradient(
                stops: [
                    .init(color: Color.accentColor.opacity(0.94 * pressedScale), location: 0.0),
                    .init(color: Color.accentColor.opacity(0.76 * pressedScale), location: 0.75),
                    .init(color: Color.primary.opacity(0.18 * pressedScale), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .solidAccent:
            return LinearGradient(
                stops: [
                    .init(color: Self.solidAccentColor.opacity(pressedScale), location: 0.0),
                    .init(color: Self.solidAccentColor.opacity(pressedScale), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}
