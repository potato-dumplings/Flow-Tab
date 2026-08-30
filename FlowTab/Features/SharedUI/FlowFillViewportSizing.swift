import CoreGraphics
import SwiftUI

enum FlowFillViewportSizing {
    static func resolve(
        proposal: ProposedViewSize,
        currentSize: CGSize
    ) -> CGSize? {
        guard let width = resolvedDimension(
            proposed: proposal.width,
            current: currentSize.width
        ), let height = resolvedDimension(
            proposed: proposal.height,
            current: currentSize.height
        ) else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private static func resolvedDimension(
        proposed: CGFloat?,
        current: CGFloat
    ) -> CGFloat? {
        if let proposed, proposed.isFinite, proposed >= 0 {
            return proposed
        }
        guard current.isFinite, current > 0 else { return nil }
        return current
    }
}
