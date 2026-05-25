import AppKit

struct FlowSettingsRGBColor: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat
}

enum FlowSettingsSemanticColor {
    case label
    case secondaryLabel
}

enum FlowSettingsColorToken {
    case semantic(FlowSettingsSemanticColor, alpha: CGFloat)
    case controlAccent(alpha: CGFloat)
    case absoluteWhite(alpha: CGFloat)
    case absoluteBlack(alpha: CGFloat)
    case rgb(light: FlowSettingsRGBColor, dark: FlowSettingsRGBColor)
    case clear
}

enum FlowSettingsFillToken {
    case color(FlowSettingsColorToken)
    case gradient([FlowSettingsColorToken])
}

struct FlowSettingsTextToken {
    let font: NSFont
    let color: FlowSettingsColorToken
    let alignment: NSTextAlignment
    let lineBreakMode: NSLineBreakMode
}

struct FlowSettingsShadowToken {
    let color: FlowSettingsColorToken
    let opacity: Float
    let radius: CGFloat
    let offset: CGSize
}

struct FlowSettingsSurfaceToken {
    let fill: FlowSettingsFillToken
    let borderColor: FlowSettingsColorToken
    let borderWidth: CGFloat
    let cornerRadius: CGFloat
    let shadow: FlowSettingsShadowToken?
}

struct FlowSettingsControlMetrics {
    let height: CGFloat
    let minimumWidth: CGFloat
    let horizontalPadding: CGFloat
    let iconSpacing: CGFloat

    func preferredWidth(for titles: [String], font: NSFont, segmentCount: Int? = nil) -> CGFloat {
        let widestTitle = titles
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        if let segmentCount {
            let segmentWidth = ceil(widestTitle) + horizontalPadding * 2
            return max(minimumWidth, segmentWidth * CGFloat(max(segmentCount, 1)) + 4)
        }
        return max(minimumWidth, ceil(widestTitle) + horizontalPadding * 2 + iconSpacing)
    }
}

protocol FlowSettingsAppearanceRefreshable: AnyObject {
    func applySettingsAppearance(_ appearance: NSAppearance)
    func refreshStyle()
}

enum FlowSettingsStyleResolver {
    static var defaultAppearance: NSAppearance {
        NSAppearance.current ?? NSAppearance(named: .aqua) ?? NSApp.effectiveAppearance
    }

    static func targetAppearance(for themeModeRaw: String, fallback: NSAppearance) -> NSAppearance {
        switch ThemePreferencesStore.resolve(rawValue: themeModeRaw) {
        case .light:
            return NSAppearance(named: .aqua) ?? fallback
        case .dark:
            return NSAppearance(named: .darkAqua) ?? fallback
        case .followSystem:
            return fallback
        }
    }

    static func color(_ token: FlowSettingsColorToken, appearance: NSAppearance) -> NSColor {
        switch token {
        case let .semantic(semantic, alpha):
            return resolve(appearance: appearance) {
                semanticColor(semantic).withAlphaComponent(alpha)
            }
        case let .controlAccent(alpha):
            return resolve(appearance: appearance) {
                NSColor.controlAccentColor.withAlphaComponent(alpha)
            }
        case let .absoluteWhite(alpha):
            return NSColor.white.withAlphaComponent(alpha)
        case let .absoluteBlack(alpha):
            return NSColor.black.withAlphaComponent(alpha)
        case let .rgb(light, dark):
            let rgb = appearance.isFlowTabDarkInterface ? dark : light
            return NSColor(
                srgbRed: rgb.red,
                green: rgb.green,
                blue: rgb.blue,
                alpha: rgb.alpha
            )
        case .clear:
            return .clear
        }
    }

    static func cgColor(_ token: FlowSettingsColorToken, appearance: NSAppearance) -> CGColor {
        color(token, appearance: appearance).cgColor
    }

    static func attributedString(
        _ text: String,
        token: FlowSettingsTextToken,
        appearance: NSAppearance
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = token.alignment
        paragraphStyle.lineBreakMode = token.lineBreakMode
        return NSAttributedString(
            string: text,
            attributes: [
                .paragraphStyle: paragraphStyle,
                .font: token.font,
                .foregroundColor: color(token.color, appearance: appearance)
            ]
        )
    }

    static func apply(surface: FlowSettingsSurfaceToken, to layer: CALayer, appearance: NSAppearance) {
        switch surface.fill {
        case let .color(colorToken):
            layer.backgroundColor = cgColor(colorToken, appearance: appearance)
        case .gradient:
            layer.backgroundColor = nil
        }
        layer.borderColor = cgColor(surface.borderColor, appearance: appearance)
        layer.borderWidth = surface.borderWidth
        layer.cornerRadius = surface.cornerRadius

        if let shadow = surface.shadow {
            layer.shadowColor = cgColor(shadow.color, appearance: appearance)
            layer.shadowOpacity = shadow.opacity
            layer.shadowRadius = shadow.radius
            layer.shadowOffset = shadow.offset
            layer.shadowPath = CGPath(
                roundedRect: layer.bounds,
                cornerWidth: surface.cornerRadius,
                cornerHeight: surface.cornerRadius,
                transform: nil
            )
        } else {
            layer.shadowOpacity = 0
            layer.shadowPath = nil
        }
    }

    private static func semanticColor(_ semantic: FlowSettingsSemanticColor) -> NSColor {
        switch semantic {
        case .label:
            return .labelColor
        case .secondaryLabel:
            return .secondaryLabelColor
        }
    }

    private static func resolve(appearance: NSAppearance, _ provider: () -> NSColor) -> NSColor {
        var resolvedColor: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = provider()
        }
        return resolvedColor ?? provider()
    }
}
