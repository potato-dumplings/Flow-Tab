import AppKit

enum FlowSettingsActionButtonState: Hashable {
    case normal
    case hovered
    case focused
    case focusedHovered
    case pressed
    case disabled
}

enum FlowSettingsSelectState: Hashable {
    case normal
    case hovered
    case focused
    case expanded
    case disabled
}

enum FlowSettingsSegmentState: Hashable {
    case normal
    case hovered
    case pressed
    case selected
    case selectedHovered
    case selectedPressed
    case disabled
}

enum FlowSettingsActionButtonRole {
    case primaryAction
    case secondaryAction
    case compactSecondaryAction
}

enum FlowSettingsSelectRole {
    case formSelect
}

struct FlowSettingsStateStyle<State: Hashable> {
    let values: [State: FlowSettingsResolvedStyle]
    let fallback: State

    func value(for state: State) -> FlowSettingsResolvedStyle {
        values[state] ?? values[fallback] ?? FlowSettingsResolvedStyle.empty
    }
}

struct FlowSettingsResolvedStyle {
    let text: FlowSettingsTextToken?
    let surface: FlowSettingsSurfaceToken?
    let gradient: [FlowSettingsColorToken]?

    static let empty = FlowSettingsResolvedStyle(text: nil, surface: nil, gradient: nil)
}

struct FlowSettingsActionButtonStyle {
    let metrics: FlowSettingsControlMetrics
    let states: FlowSettingsStateStyle<FlowSettingsActionButtonState>

    static func preset(_ role: FlowSettingsActionButtonRole) -> FlowSettingsActionButtonStyle {
        switch role {
        case .primaryAction:
            return actionStyle(
                minimumWidth: 96,
                textColor: .absoluteWhite(alpha: 1),
                fill: [
                    .controlAccent(alpha: 0.94),
                    .controlAccent(alpha: 0.76),
                    .semantic(.label, alpha: 0.18)
                ],
                border: .controlAccent(alpha: 0.55),
                shadow: .controlAccent(alpha: 0.20)
            )
        case .secondaryAction:
            return actionStyle(
                minimumWidth: 96,
                textColor: .semantic(.label, alpha: 0.78),
                fill: [
                    .semantic(.label, alpha: 0.12),
                    .semantic(.label, alpha: 0.09),
                    .controlAccent(alpha: 0.26)
                ],
                border: .semantic(.label, alpha: 0.24),
                shadow: .semantic(.label, alpha: 0.08)
            )
        case .compactSecondaryAction:
            return compactActionStyle()
        }
    }

    private static func actionStyle(
        minimumWidth: CGFloat,
        textColor: FlowSettingsColorToken,
        fill: [FlowSettingsColorToken],
        border: FlowSettingsColorToken,
        shadow: FlowSettingsColorToken
    ) -> FlowSettingsActionButtonStyle {
        let metrics = FlowSettingsControlMetrics(
            height: 30,
            minimumWidth: minimumWidth,
            horizontalPadding: 16,
            iconSpacing: 0
        )
        let text = FlowSettingsTextToken(
            font: FlowTypography.appKit(.bodyStrong),
            color: textColor,
            alignment: .center,
            lineBreakMode: .byClipping
        )
        let normalSurface = FlowSettingsSurfaceToken(
            fill: .gradient(fill),
            borderColor: border,
            borderWidth: 1,
            cornerRadius: metrics.height / 2,
            shadow: FlowSettingsShadowToken(color: shadow, opacity: 1, radius: 6, offset: CGSize(width: 0, height: 2))
        )
        let disabledText = FlowSettingsTextToken(
            font: text.font,
            color: .semantic(.secondaryLabel, alpha: 0.55),
            alignment: .center,
            lineBreakMode: .byClipping
        )
        return FlowSettingsActionButtonStyle(
            metrics: metrics,
            states: FlowSettingsStateStyle(
                values: [
                    .normal: FlowSettingsResolvedStyle(text: text, surface: normalSurface, gradient: fill),
                    .hovered: FlowSettingsResolvedStyle(text: text, surface: normalSurface, gradient: fill),
                    .focused: FlowSettingsResolvedStyle(text: text, surface: normalSurface, gradient: fill),
                    .focusedHovered: FlowSettingsResolvedStyle(text: text, surface: normalSurface, gradient: fill),
                    .pressed: FlowSettingsResolvedStyle(text: text, surface: normalSurface, gradient: fill.map(pressedToken)),
                    .disabled: FlowSettingsResolvedStyle(text: disabledText, surface: normalSurface, gradient: fill)
                ],
                fallback: .normal
            )
        )
    }

    private static func compactActionStyle() -> FlowSettingsActionButtonStyle {
        let metrics = FlowSettingsControlMetrics(height: 32, minimumWidth: 68, horizontalPadding: 14, iconSpacing: 0)
        let text = FlowSettingsTextToken(
            font: FlowTypography.appKit(.controlTextEmphasized),
            color: .semantic(.label, alpha: 0.76),
            alignment: .center,
            lineBreakMode: .byClipping
        )
        let normal = FlowSettingsSurfaceToken(
            fill: .color(.rgb(
                light: FlowSettingsRGBColor(red: 1, green: 1, blue: 1, alpha: 0.96),
                dark: FlowSettingsRGBColor(red: 1, green: 1, blue: 1, alpha: 0.12)
            )),
            borderColor: .rgb(
                light: FlowSettingsRGBColor(red: 0, green: 0, blue: 0, alpha: 0.12),
                dark: FlowSettingsRGBColor(red: 1, green: 1, blue: 1, alpha: 0.18)
            ),
            borderWidth: 1,
            cornerRadius: 8,
            shadow: FlowSettingsShadowToken(color: .absoluteBlack(alpha: 0.05), opacity: 1, radius: 3, offset: CGSize(width: 0, height: 1))
        )
        let hovered = FlowSettingsSurfaceToken(
            fill: .color(.rgb(
                light: FlowSettingsRGBColor(red: 1, green: 1, blue: 1, alpha: 1),
                dark: FlowSettingsRGBColor(red: 1, green: 1, blue: 1, alpha: 0.18)
            )),
            borderColor: normal.borderColor,
            borderWidth: normal.borderWidth,
            cornerRadius: normal.cornerRadius,
            shadow: normal.shadow
        )
        return FlowSettingsActionButtonStyle(
            metrics: metrics,
            states: FlowSettingsStateStyle(
                values: [
                    .normal: FlowSettingsResolvedStyle(text: text, surface: normal, gradient: nil),
                    .hovered: FlowSettingsResolvedStyle(text: text, surface: hovered, gradient: nil),
                    .focused: FlowSettingsResolvedStyle(text: text, surface: hovered, gradient: nil),
                    .focusedHovered: FlowSettingsResolvedStyle(text: text, surface: hovered, gradient: nil),
                    .pressed: FlowSettingsResolvedStyle(text: text, surface: hovered, gradient: nil),
                    .disabled: FlowSettingsResolvedStyle(text: text, surface: normal, gradient: nil)
                ],
                fallback: .normal
            )
        )
    }

    private static func pressedToken(_ token: FlowSettingsColorToken) -> FlowSettingsColorToken {
        switch token {
        case let .controlAccent(alpha):
            return .controlAccent(alpha: min(1, alpha + 0.06))
        case let .semantic(color, alpha):
            return .semantic(color, alpha: min(1, alpha + 0.04))
        default:
            return token
        }
    }
}

struct FlowSettingsSelectStyle {
    let metrics: FlowSettingsControlMetrics
    let states: FlowSettingsStateStyle<FlowSettingsSelectState>

    static func preset(_ role: FlowSettingsSelectRole) -> FlowSettingsSelectStyle {
        let metrics = FlowSettingsControlMetrics(
            height: 32,
            minimumWidth: 132,
            horizontalPadding: 12,
            iconSpacing: 20
        )
        let text = FlowSettingsTextToken(
            font: FlowTypography.appKit(.controlText),
            color: .rgb(
                light: FlowSettingsRGBColor(red: 0, green: 0, blue: 0, alpha: 0.78),
                dark: FlowSettingsRGBColor(red: 1, green: 1, blue: 1, alpha: 0.92)
            ),
            alignment: .center,
            lineBreakMode: .byClipping
        )
        let surface = FlowSettingsSurfaceToken(
            fill: .color(.rgb(
                light: FlowSettingsRGBColor(red: 1, green: 1, blue: 1, alpha: 0.99),
                dark: FlowSettingsRGBColor(red: 1, green: 1, blue: 1, alpha: 0.08)
            )),
            borderColor: .rgb(
                light: FlowSettingsRGBColor(red: 0, green: 0, blue: 0, alpha: 0.14),
                dark: FlowSettingsRGBColor(red: 1, green: 1, blue: 1, alpha: 0.14)
            ),
            borderWidth: 1,
            cornerRadius: 10,
            shadow: FlowSettingsShadowToken(color: .absoluteBlack(alpha: 0.04), opacity: 1, radius: 4, offset: CGSize(width: 0, height: 1))
        )
        return FlowSettingsSelectStyle(
            metrics: metrics,
            states: FlowSettingsStateStyle(values: [
                .normal: FlowSettingsResolvedStyle(text: text, surface: surface, gradient: nil),
                .hovered: FlowSettingsResolvedStyle(text: text, surface: surface, gradient: nil),
                .focused: FlowSettingsResolvedStyle(text: text, surface: surface, gradient: nil),
                .expanded: FlowSettingsResolvedStyle(text: text, surface: surface, gradient: nil),
                .disabled: FlowSettingsResolvedStyle(text: text, surface: surface, gradient: nil)
            ], fallback: .normal)
        )
    }
}
