import CoreGraphics
import Foundation
import SwiftUI

struct SwitcherPointerSelectionActions {
    let selectApp: (String) -> Void
    let selectWindow: (String, String) -> Void
    let selectSearchResult: (String) -> Void
    let commitApp: (String) -> Void
    let commitWindow: (String, String) -> Void
    let commitSearchResult: (String) -> Void
}

enum SwitcherPointerSelectionTarget: Hashable {
    case application(appID: String)
    case window(appID: String, windowID: String)
    case searchResult(resultID: String)

    var diagnosticSummary: String {
        switch self {
        case .application(let appID):
            return "targetKind=application targetID=\(Self.escaped(appID))"
        case .window(let appID, let windowID):
            return "targetKind=window targetID=\(Self.escaped(windowID))"
                + " targetAppID=\(Self.escaped(appID))"
        case .searchResult(let resultID):
            return "targetKind=searchResult targetID=\(Self.escaped(resultID))"
        }
    }

    static func escaped(_ value: String) -> String {
        value.addingPercentEncoding(
            withAllowedCharacters: diagnosticAllowedCharacters
        ) ?? ""
    }

    private static let diagnosticAllowedCharacters =
        CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~")
        )
}

struct SwitcherPointerSelectionGateBlockedEvidence: Equatable {
    let generation: UInt64
    let target: SwitcherPointerSelectionTarget

    var diagnosticSummary: String {
        "\(target.diagnosticSummary) generation=\(generation)"
    }
}

enum SwitcherPointerSelectionGateDecision: Equatable {
    case allowed
    case blocked(SwitcherPointerSelectionGateBlockedEvidence)
    case duplicateBlocked

    var allowsSelection: Bool {
        self == .allowed
    }

    var newBlockedEvidence:
        SwitcherPointerSelectionGateBlockedEvidence?
    {
        guard case .blocked(let evidence) = self else {
            return nil
        }
        return evidence
    }
}

struct SwitcherPointerSelectionGate: Equatable {
    static let defaultMovementThreshold: CGFloat = 1

    private let movementThreshold: CGFloat
    private var resetLocation: CGPoint?
    private var blockedTargets: Set<SwitcherPointerSelectionTarget> = []
    private(set) var isArmed = false
    private(set) var generation: UInt64 = 0

    init(movementThreshold: CGFloat = Self.defaultMovementThreshold) {
        self.movementThreshold = movementThreshold
    }

    mutating func reset(currentLocation: CGPoint?) {
        generation &+= 1
        resetLocation = currentLocation
        blockedTargets.removeAll(keepingCapacity: false)
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

    mutating func evaluateSelection(
        of target: SwitcherPointerSelectionTarget,
        at location: CGPoint
    ) -> SwitcherPointerSelectionGateDecision {
        guard !recordPointerMoved(to: location) else {
            return .allowed
        }
        guard blockedTargets.insert(target).inserted else {
            return .duplicateBlocked
        }
        return .blocked(
            SwitcherPointerSelectionGateBlockedEvidence(
                generation: generation,
                target: target
            )
        )
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
