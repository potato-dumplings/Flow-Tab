import AppKit
import SwiftUI

enum FlowTypography {
    enum Token {
        case pageTitle
        case pageSubtitle
        case cardTitle
        case cardSubtitle
        case formLabel
        case formLabelEmphasized
        case controlText
        case controlTextEmphasized
        case body
        case bodyEmphasized
        case bodyStrong
        case micro
        case microEmphasized
        case display
        case metadataMonospaced
        case metadataMonospacedEmphasized
        case bodyMonospaced
    }

    enum Weight {
        case regular
        case medium
        case semibold
    }

    enum Design {
        case standard
        case rounded
        case monospaced
    }

    private struct Spec {
        let size: CGFloat
        let weight: Weight
        let design: Design

        private init(size: CGFloat, weight: Weight, design: Design) {
            self.size = size
            self.weight = weight
            self.design = design
        }

        static let pageTitle = Spec(size: 22, weight: .semibold, design: .standard)
        static let pageSubtitle = Spec(size: 12, weight: .regular, design: .standard)
        static let cardTitle = Spec(size: 15, weight: .semibold, design: .standard)
        static let cardSubtitle = Spec(size: 11, weight: .regular, design: .standard)
        static let formLabel = Spec(size: 13, weight: .regular, design: .standard)
        static let formLabelEmphasized = Spec(size: 13, weight: .medium, design: .standard)
        static let controlText = Spec(size: 13, weight: .regular, design: .standard)
        static let controlTextEmphasized = Spec(size: 13, weight: .medium, design: .standard)
        static let body = Spec(size: 12, weight: .regular, design: .standard)
        static let bodyEmphasized = Spec(size: 12, weight: .medium, design: .standard)
        static let bodyStrong = Spec(size: 12, weight: .semibold, design: .standard)
        static let micro = Spec(size: 10, weight: .medium, design: .standard)
        static let microEmphasized = Spec(size: 10, weight: .semibold, design: .standard)
        static let display = Spec(size: 28, weight: .semibold, design: .rounded)
        static let metadataMonospaced = Spec(size: 11, weight: .regular, design: .monospaced)
        static let metadataMonospacedEmphasized = Spec(size: 11, weight: .medium, design: .monospaced)
        static let bodyMonospaced = Spec(size: 12, weight: .regular, design: .monospaced)
    }

    static func swiftUI(_ token: Token) -> Font {
        let spec = spec(for: token)
        return .system(size: spec.size, weight: spec.weight.swiftUIWeight, design: spec.design.swiftUIDesign)
    }

    static func appKit(_ token: Token) -> NSFont {
        let spec = spec(for: token)
        switch spec.design {
        case .standard:
            return .systemFont(ofSize: spec.size, weight: spec.weight.appKitWeight)
        case .rounded:
            return roundedSystemFont(size: spec.size, weight: spec.weight.appKitWeight)
        case .monospaced:
            return .monospacedSystemFont(ofSize: spec.size, weight: spec.weight.appKitWeight)
        }
    }

    private static func spec(for token: Token) -> Spec {
        switch token {
        case .pageTitle:
            return .pageTitle
        case .pageSubtitle:
            return .pageSubtitle
        case .cardTitle:
            return .cardTitle
        case .cardSubtitle:
            return .cardSubtitle
        case .formLabel:
            return .formLabel
        case .formLabelEmphasized:
            return .formLabelEmphasized
        case .controlText:
            return .controlText
        case .controlTextEmphasized:
            return .controlTextEmphasized
        case .body:
            return .body
        case .bodyEmphasized:
            return .bodyEmphasized
        case .bodyStrong:
            return .bodyStrong
        case .micro:
            return .micro
        case .microEmphasized:
            return .microEmphasized
        case .display:
            return .display
        case .metadataMonospaced:
            return .metadataMonospaced
        case .metadataMonospacedEmphasized:
            return .metadataMonospacedEmphasized
        case .bodyMonospaced:
            return .bodyMonospaced
        }
    }

    private static func roundedSystemFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let standard = NSFont.systemFont(ofSize: size, weight: weight)
        guard
            let roundedDescriptor = standard.fontDescriptor.withDesign(.rounded),
            let roundedFont = NSFont(descriptor: roundedDescriptor, size: size)
        else {
            return standard
        }
        return roundedFont
    }
}

private extension FlowTypography.Weight {
    var swiftUIWeight: Font.Weight {
        switch self {
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        }
    }

    var appKitWeight: NSFont.Weight {
        switch self {
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        }
    }
}

private extension FlowTypography.Design {
    var swiftUIDesign: Font.Design {
        switch self {
        case .standard:
            return .default
        case .rounded:
            return .rounded
        case .monospaced:
            return .monospaced
        }
    }
}
