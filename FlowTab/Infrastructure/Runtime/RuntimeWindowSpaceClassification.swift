import CoreGraphics
import Foundation

enum RuntimeWindowSpaceClassification: Equatable {
    case unknown
    case desktopOnly
    case offDesktop
    case mixed
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
