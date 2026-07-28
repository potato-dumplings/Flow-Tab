import Foundation

struct HotkeyInputSourceID: Equatable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct HotkeyInputEventIdentity: Equatable, Hashable, Sendable {
    let sourceID: HotkeyInputSourceID
    let sequence: UInt64
}

struct HotkeyInputEvent: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case pressed
        case released
    }

    let identity: HotkeyInputEventIdentity
    let phase: Phase
    let isBackward: Bool
}

enum SwitcherHotkeyInputRoute: String, Equatable, Hashable, Sendable {
    case globalAppSwitcher
    case inAppWindowSwitcher
}

struct SwitcherHotkeyInputReceipt: Equatable, Sendable {
    let route: SwitcherHotkeyInputRoute
    let event: HotkeyInputEvent
    let inputGeneration: UInt64
    let sourceRegistrationGeneration: UInt64
    let presentationSessionGeneration: Int
}

enum SwitcherHotkeyInputRejection: Equatable, Sendable {
    case sourceNotRegistered
    case unexpectedSource(
        expected: HotkeyInputSourceID,
        observed: HotkeyInputSourceID
    )
    case duplicate(sequence: UInt64)
    case outOfOrder(sequence: UInt64, latestSequence: UInt64)
}

enum SwitcherHotkeyInputObservation: Equatable, Sendable {
    case accepted(SwitcherHotkeyInputReceipt)
    case rejected(SwitcherHotkeyInputRejection)
}

@MainActor
final class SwitcherHotkeyInputOwner {
    private struct RouteState {
        let sourceID: HotkeyInputSourceID
        let sourceRegistrationGeneration: UInt64
        var latestSequence: UInt64?
        var latestPhase: HotkeyInputEvent.Phase?
    }

    private var routeStates: [SwitcherHotkeyInputRoute: RouteState] = [:]

    private(set) var inputGeneration: UInt64 = 0
    private(set) var sourceRegistrationGeneration: UInt64 = 0

    @discardableResult
    func register(
        sourceID: HotkeyInputSourceID,
        for route: SwitcherHotkeyInputRoute
    ) -> UInt64 {
        if routeStates[route]?.sourceID == sourceID {
            return routeStates[route]?.sourceRegistrationGeneration
                ?? sourceRegistrationGeneration
        }
        sourceRegistrationGeneration &+= 1
        routeStates[route] = RouteState(
            sourceID: sourceID,
            sourceRegistrationGeneration: sourceRegistrationGeneration,
            latestSequence: nil,
            latestPhase: nil
        )
        return sourceRegistrationGeneration
    }

    func unregister(route: SwitcherHotkeyInputRoute) {
        guard routeStates.removeValue(forKey: route) != nil else { return }
        sourceRegistrationGeneration &+= 1
    }

    func observe(
        _ event: HotkeyInputEvent,
        route: SwitcherHotkeyInputRoute,
        presentationSessionGeneration: Int
    ) -> SwitcherHotkeyInputObservation {
        guard var state = routeStates[route] else {
            return .rejected(.sourceNotRegistered)
        }
        guard state.sourceID == event.identity.sourceID else {
            return .rejected(
                .unexpectedSource(
                    expected: state.sourceID,
                    observed: event.identity.sourceID
                )
            )
        }
        if let latestSequence = state.latestSequence {
            if event.identity.sequence == latestSequence {
                return .rejected(.duplicate(sequence: latestSequence))
            }
            guard event.identity.sequence > latestSequence else {
                return .rejected(
                    .outOfOrder(
                        sequence: event.identity.sequence,
                        latestSequence: latestSequence
                    )
                )
            }
        }

        inputGeneration &+= 1
        state.latestSequence = event.identity.sequence
        state.latestPhase = event.phase
        routeStates[route] = state
        return .accepted(
            SwitcherHotkeyInputReceipt(
                route: route,
                event: event,
                inputGeneration: inputGeneration,
                sourceRegistrationGeneration:
                    state.sourceRegistrationGeneration,
                presentationSessionGeneration:
                    presentationSessionGeneration
            )
        )
    }

    func latestPhase(
        for route: SwitcherHotkeyInputRoute
    ) -> HotkeyInputEvent.Phase? {
        routeStates[route]?.latestPhase
    }
}
