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
    let holdSetPressedEvidence: Bool?

    init(
        identity: HotkeyInputEventIdentity,
        phase: Phase,
        isBackward: Bool,
        holdSetPressedEvidence: Bool? = nil
    ) {
        self.identity = identity
        self.phase = phase
        self.isBackward = isBackward
        self.holdSetPressedEvidence = holdSetPressedEvidence
    }
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

struct InAppHotkeyAdvanceApplicationEvidence:
    Equatable,
    Sendable
{
    let direction: String
    let key: String
    let sourceID: HotkeyInputSourceID
    let sequence: UInt64
    let inputGeneration: UInt64
    let sourceRegistrationGeneration: UInt64
    let presentationSessionGeneration: Int
    let previousWindowID: String
    let selectedWindowID: String

    init?(
        receipt: SwitcherHotkeyInputReceipt,
        previousWindowID: String?,
        selectedWindowID: String?
    ) {
        guard
            receipt.route == .inAppWindowSwitcher,
            receipt.event.phase == .pressed,
            let previousWindowID,
            let selectedWindowID,
            previousWindowID != selectedWindowID
        else {
            return nil
        }

        direction = receipt.event.isBackward
            ? "backward"
            : "forward"
        key = receipt.event.isBackward
            ? "tabBackward"
            : "tabForward"
        sourceID = receipt.event.identity.sourceID
        sequence = receipt.event.identity.sequence
        inputGeneration = receipt.inputGeneration
        sourceRegistrationGeneration =
            receipt.sourceRegistrationGeneration
        presentationSessionGeneration =
            receipt.presentationSessionGeneration
        self.previousWindowID = previousWindowID
        self.selectedWindowID = selectedWindowID
    }

    var logMessage: String {
        "inAppHotkeyAdvance result=applied "
            + "dir=\(direction) key=\(key) "
            + "route=inAppWindowSwitcher "
            + "source=\(sourceID.rawValue.uuidString) "
            + "sequence=\(sequence) "
            + "inputGeneration=\(inputGeneration) "
            + "sourceRegistrationGeneration="
            + "\(sourceRegistrationGeneration) "
            + "sessionGeneration="
            + "\(presentationSessionGeneration) "
            + "previousWindowID=\(previousWindowID) "
            + "selectedWindowID=\(selectedWindowID)"
    }
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
        var latestHoldSetPressedEvidence: Bool?
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
            latestPhase: nil,
            latestHoldSetPressedEvidence: nil
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
        if let holdSetPressedEvidence =
            event.holdSetPressedEvidence
        {
            state.latestHoldSetPressedEvidence =
                holdSetPressedEvidence
        }
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

    func latestHoldSetPressedEvidence(
        for route: SwitcherHotkeyInputRoute
    ) -> Bool? {
        routeStates[route]?.latestHoldSetPressedEvidence
    }

    func updateHoldSetPressedEvidence(
        _ evidence: Bool,
        for route: SwitcherHotkeyInputRoute
    ) {
        guard var state = routeStates[route] else { return }
        state.latestHoldSetPressedEvidence = evidence
        routeStates[route] = state
    }

}
