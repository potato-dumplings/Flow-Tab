import CoreGraphics
import SwiftUI

struct SwitcherPointerSelectionActions {
    let selectApp: (String) -> Void
    let selectWindow: (String, String) -> Void
    let selectSearchResult: (String) -> Void
    let commitApp: (String) -> Void
    let commitWindow: (String, String) -> Void
    let commitSearchResult: (String) -> Void
}

struct SwitcherPointerSelectionGate: Equatable {
    static let defaultMovementThreshold: CGFloat = 1

    private let movementThreshold: CGFloat
    private var resetLocation: CGPoint?
    private(set) var isArmed = false

    init(movementThreshold: CGFloat = Self.defaultMovementThreshold) {
        self.movementThreshold = movementThreshold
    }

    mutating func reset(currentLocation: CGPoint?) {
        resetLocation = currentLocation
        isArmed = false
    }

    @discardableResult
    mutating func recordPointerMoved(to location: CGPoint) -> Bool {
        guard !isArmed else { return true }
        guard let resetLocation else {
            self.resetLocation = location
            return false
        }

        let deltaX = location.x - resetLocation.x
        let deltaY = location.y - resetLocation.y
        if deltaX * deltaX + deltaY * deltaY >= movementThreshold * movementThreshold {
            isArmed = true
        }
        return isArmed
    }
}

private struct SwitcherPointerSelectionModifier: ViewModifier {
    let isEnabled: Bool
    let onClick: (() -> Void)?
    let onActiveHover: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                guard isEnabled else { return }
                onClick?()
            }
            .onContinuousHover(coordinateSpace: .global) { phase in
                guard isEnabled else { return }
                guard case .active = phase else { return }
                onActiveHover()
            }
    }
}

private struct SwitcherPointerTrackingModifier: ViewModifier {
    let isEnabled: Bool
    let onActiveHover: (CGPoint) -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .global) { phase in
                guard isEnabled else { return }
                guard case .active(let location) = phase else { return }
                onActiveHover(location)
            }
    }
}

struct SwitcherPointerAppStripHitTest {
    static func appID(
        at globalLocation: CGPoint,
        in globalFrame: CGRect,
        appIDs: [String],
        tileSize: CGFloat,
        spacing: CGFloat
    ) -> String? {
        guard !appIDs.isEmpty else { return nil }
        guard globalFrame.contains(globalLocation) else { return nil }

        let tileCount = CGFloat(appIDs.count)
        let contentWidth = tileCount * tileSize + max(0, tileCount - 1) * spacing
        let startX = max(0, (globalFrame.width - contentWidth) / 2)
        let localX = globalLocation.x - globalFrame.minX - startX
        guard localX >= 0, localX <= contentWidth else { return nil }

        let slotWidth = tileSize + spacing
        let index = Int(localX / slotWidth)
        guard appIDs.indices.contains(index) else { return nil }

        let offsetInSlot = localX - CGFloat(index) * slotWidth
        guard offsetInSlot <= tileSize else { return nil }

        return appIDs[index]
    }
}

extension View {
    func switcherPointerSelection(
        isEnabled: Bool = true,
        onClick: (() -> Void)? = nil,
        onActiveHover: @escaping () -> Void
    ) -> some View {
        modifier(
            SwitcherPointerSelectionModifier(
                isEnabled: isEnabled,
                onClick: onClick,
                onActiveHover: onActiveHover
            )
        )
    }

    func switcherPointerTracking(
        isEnabled: Bool = true,
        onActiveHover: @escaping (CGPoint) -> Void
    ) -> some View {
        modifier(
            SwitcherPointerTrackingModifier(
                isEnabled: isEnabled,
                onActiveHover: onActiveHover
            )
        )
    }
}
