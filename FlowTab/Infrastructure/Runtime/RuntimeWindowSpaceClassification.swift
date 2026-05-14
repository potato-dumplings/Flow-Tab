import CoreGraphics
import Foundation

enum RuntimeWindowSpaceClassification: Equatable {
    case unknown
    case desktopOnly
    case offDesktop
    case mixed
}

enum RuntimeWindowDiagnostics {
    static func displayMode(
        frame: CGRect?,
        spaceIDs: [Int],
        confirmationSource: WindowBindingConfirmationSource?
    ) -> String {
        if isConfirmedFullscreenSource(confirmationSource) {
            return "full-screen"
        }
        if RuntimeWindowTopologyClassifier.isLikelyOffDesktopFullscreenContent(
            bounds: frame,
            spaceIDs: spaceIDs
        ) {
            return "full-screen"
        }
        return "normal"
    }

    static func activationIdentity(
        activationHandleID: String?,
        hasAXWindow: Bool,
        cgWindowID: CGWindowID?,
        hasStickyBinding: Bool
    ) -> String {
        if let activationHandleID {
            return "ax:\(activationHandleID)"
        }
        if hasAXWindow, let cgWindowID {
            return "ax-object+cg:\(cgWindowID)"
        }
        if hasAXWindow {
            return "ax-object"
        }
        if hasStickyBinding, let cgWindowID {
            return "sticky-cg:\(cgWindowID)"
        }
        if let cgWindowID {
            return "cg:\(cgWindowID)"
        }
        return "unknown"
    }

    private static func isConfirmedFullscreenSource(
        _ source: WindowBindingConfirmationSource?
    ) -> Bool {
        switch source {
        case .fullscreenContentRebinding,
             .fullscreenContentFallbackBinding,
             .desktopSiblingBinding:
            return true
        case .stickyBinding,
             .publicExactMatch,
             .privateExactBridge,
             nil:
            return false
        }
    }
}

enum RuntimeWindowTopologyClassifier {
    static let desktopSpaceID = 1

    private static let fullscreenMinimumWidth: CGFloat = 900
    private static let fullscreenMinimumHeight: CGFloat = 600
    private static let fullscreenOriginTolerance: CGFloat = 90
    private static let fullscreenTopInsetLimit: CGFloat = 180
    private static let frameMatchOriginTolerance: CGFloat = 24
    private static let frameMatchSizeTolerance: CGFloat = 40

    static func normalizedSpaceIDs(_ spaceIDs: [Int]) -> [Int] {
        Array(Set(spaceIDs.filter { $0 > 0 })).sorted()
    }

    static func classify(spaceIDs: [Int]) -> RuntimeWindowSpaceClassification {
        let normalized = normalizedSpaceIDs(spaceIDs)
        guard !normalized.isEmpty else { return .unknown }
        if normalized == [desktopSpaceID] {
            return .desktopOnly
        }
        if normalized.contains(desktopSpaceID) {
            return .mixed
        }
        return .offDesktop
    }

    static func isDesktopOnlySpaceWindow(spaceIDs: [Int]) -> Bool {
        classify(spaceIDs: spaceIDs) == .desktopOnly
    }

    static func hasOffDesktopSpace(spaceIDs: [Int]) -> Bool {
        switch classify(spaceIDs: spaceIDs) {
        case .offDesktop, .mixed:
            return true
        case .unknown, .desktopOnly:
            return false
        }
    }

    static func isLikelyFullscreenContent(bounds: CGRect?) -> Bool {
        guard let bounds = bounds?.standardized else { return false }
        guard bounds.width >= fullscreenMinimumWidth else { return false }
        guard bounds.height >= fullscreenMinimumHeight else { return false }
        guard abs(bounds.minX) <= fullscreenOriginTolerance else { return false }
        return bounds.minY >= 0 && bounds.minY <= fullscreenTopInsetLimit
    }

    static func isLikelyOffDesktopFullscreenContent(
        bounds: CGRect?,
        spaceIDs: [Int]
    ) -> Bool {
        hasOffDesktopSpace(spaceIDs: spaceIDs) && isLikelyFullscreenContent(bounds: bounds)
    }

    static func isLikelyDesktopWrapper(
        bounds: CGRect?,
        spaceIDs: [Int],
        fullscreenContentBounds: [CGRect]
    ) -> Bool {
        guard isDesktopOnlySpaceWindow(spaceIDs: spaceIDs) else { return false }
        guard let bounds = bounds?.standardized else { return false }
        guard isLikelyFullscreenContent(bounds: bounds) else { return false }
        return fullscreenContentBounds.contains { contentBounds in
            framesApproximatelyMatch(bounds, contentBounds.standardized)
        }
    }

    static func framesApproximatelyMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let left = lhs.standardized
        let right = rhs.standardized
        guard left.width > 0, left.height > 0, right.width > 0, right.height > 0 else {
            return false
        }
        return abs(left.minX - right.minX) <= frameMatchOriginTolerance
            && abs(left.minY - right.minY) <= frameMatchOriginTolerance
            && abs(left.width - right.width) <= frameMatchSizeTolerance
            && abs(left.height - right.height) <= frameMatchSizeTolerance
    }
}
