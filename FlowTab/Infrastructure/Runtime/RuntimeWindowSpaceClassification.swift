import CoreGraphics
import Foundation

enum RuntimeWindowSpaceClassification: Equatable {
    case unknown
    case desktopOnly
    case offDesktop
    case mixed
}

enum RuntimeSpaceEvidenceConfidence: String, Equatable {
    case observed
    case inferredFromTopology
    case inferredFromFullscreenGeometry
    case stale
}

struct RuntimeSpaceEvidence: Equatable {
    let cgWindowID: CGWindowID
    let spaceIDs: Set<Int>
    let confidence: RuntimeSpaceEvidenceConfidence
    let displayID: CGDirectDisplayID?
    let source: String

    var canConfirmExactBinding: Bool {
        false
    }

    var allowsPublicAXRecovery: Bool {
        confidence != .stale
    }
}

struct RuntimeWindowTopologyPolicy: Equatable {
    let desktopSpaceID: Int
    let fullscreenMinimumWidth: CGFloat
    let fullscreenMinimumHeight: CGFloat
    let fullscreenOriginTolerance: CGFloat
    let fullscreenTopInsetLimit: CGFloat
    let frameMatchOriginTolerance: CGFloat
    let frameMatchSizeTolerance: CGFloat

    static let `default` = RuntimeWindowTopologyPolicy(
        desktopSpaceID: 1,
        fullscreenMinimumWidth: 900,
        fullscreenMinimumHeight: 600,
        fullscreenOriginTolerance: 90,
        fullscreenTopInsetLimit: 180,
        frameMatchOriginTolerance: 24,
        frameMatchSizeTolerance: 40
    )
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
    static let policy: RuntimeWindowTopologyPolicy = .default
    static var desktopSpaceID: Int {
        policy.desktopSpaceID
    }

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
        guard bounds.width >= policy.fullscreenMinimumWidth else { return false }
        guard bounds.height >= policy.fullscreenMinimumHeight else { return false }
        guard abs(bounds.minX) <= policy.fullscreenOriginTolerance else { return false }
        return bounds.minY >= 0 && bounds.minY <= policy.fullscreenTopInsetLimit
    }

    static func isLikelyOffDesktopFullscreenContent(
        bounds: CGRect?,
        spaceIDs: [Int]
    ) -> Bool {
        hasOffDesktopSpace(spaceIDs: spaceIDs) && isLikelyFullscreenContent(bounds: bounds)
    }

    static func spaceEvidence(
        cgWindowID: CGWindowID,
        spaceIDs: [Int],
        bounds: CGRect?,
        displayID: CGDirectDisplayID? = nil,
        source: String
    ) -> RuntimeSpaceEvidence {
        let normalizedSpaceIDs = normalizedSpaceIDs(spaceIDs)
        let confidence: RuntimeSpaceEvidenceConfidence
        if normalizedSpaceIDs.isEmpty {
            confidence = .stale
        } else if isLikelyOffDesktopFullscreenContent(
            bounds: bounds,
            spaceIDs: normalizedSpaceIDs
        ) {
            confidence = .inferredFromFullscreenGeometry
        } else if hasOffDesktopSpace(spaceIDs: normalizedSpaceIDs) {
            confidence = .inferredFromTopology
        } else {
            confidence = .observed
        }
        return RuntimeSpaceEvidence(
            cgWindowID: cgWindowID,
            spaceIDs: Set(normalizedSpaceIDs),
            confidence: confidence,
            displayID: displayID,
            source: source
        )
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
        return abs(left.minX - right.minX) <= policy.frameMatchOriginTolerance
            && abs(left.minY - right.minY) <= policy.frameMatchOriginTolerance
            && abs(left.width - right.width) <= policy.frameMatchSizeTolerance
            && abs(left.height - right.height) <= policy.frameMatchSizeTolerance
    }
}
