import AppKit
import CoreGraphics
import Foundation

struct SpaceFixtureWindowMutationPressureRoute: Equatable {
    static let commandArgument =
        "--window-mutation-pressure-command-notification-name"
    static let commandAcknowledgementArgument =
        "--window-mutation-pressure-command-ack-notification-name"
    static let evidenceArgument =
        "--window-mutation-pressure-evidence-notification-name"
    static let evidenceAcknowledgementArgument =
        "--window-mutation-pressure-evidence-ack-notification-name"

    let command: Notification.Name
    let commandAcknowledgement: Notification.Name
    let evidence: Notification.Name
    let evidenceAcknowledgement: Notification.Name

    static func configured(arguments: [String]) -> Self? {
        guard
            let command = value(after: commandArgument, in: arguments),
            let commandAck = value(
                after: commandAcknowledgementArgument,
                in: arguments
            ),
            let evidence = value(after: evidenceArgument, in: arguments),
            let evidenceAck = value(
                after: evidenceAcknowledgementArgument,
                in: arguments
            )
        else {
            return nil
        }
        return Self(
            command: Notification.Name(command),
            commandAcknowledgement: Notification.Name(commandAck),
            evidence: Notification.Name(evidence),
            evidenceAcknowledgement: Notification.Name(evidenceAck)
        )
    }

    var launchArguments: [String] {
        [
            Self.commandArgument, command.rawValue,
            Self.commandAcknowledgementArgument,
            commandAcknowledgement.rawValue,
            Self.evidenceArgument, evidence.rawValue,
            Self.evidenceAcknowledgementArgument,
            evidenceAcknowledgement.rawValue
        ]
    }

    private static func value(
        after argument: String,
        in arguments: [String]
    ) -> String? {
        guard let index = arguments.firstIndex(of: argument) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex,
              !arguments[valueIndex].isEmpty
        else {
            return nil
        }
        return arguments[valueIndex]
    }
}

enum SpaceFixtureWindowMutationPressureAction: String {
    case open
    case close
}

struct SpaceFixtureWindowMutationPressureIdentity: Equatable {
    let bundleIdentifier: String
    let processIdentifier: Int32
}

struct SpaceFixtureWindowMutationPressureGenerationGate: Equatable {
    private(set) var latestSequence: UInt64 = 0
    private(set) var latestGeneration = 0

    mutating func accepts(sequence: UInt64, generation: Int) -> Bool {
        guard sequence > latestSequence,
              generation > latestGeneration
        else {
            return false
        }
        latestSequence = sequence
        latestGeneration = generation
        return true
    }
}

struct SpaceFixtureWindowMutationPressureCommand: Equatable {
    let sequence: UInt64
    let generation: Int
    let action: SpaceFixtureWindowMutationPressureAction
    let targetWindowPlanIndex: Int

    init?(notification: Notification) {
        guard let info = notification.userInfo,
              let sequence = (info["sequence"] as? NSNumber)?
                .uint64Value,
              sequence > 0,
              let generation = (info["generation"] as? NSNumber)?
                .intValue,
              generation > 0,
              let actionValue = info["action"] as? String,
              let action = SpaceFixtureWindowMutationPressureAction(
                rawValue: actionValue
              ),
              let target = (
                info["targetWindowPlanIndex"] as? NSNumber
              )?.intValue,
              target > 0
        else {
            return nil
        }
        self.sequence = sequence
        self.generation = generation
        self.action = action
        targetWindowPlanIndex = target
    }
}

struct SpaceFixtureWindowMutationPressureSnapshot: Equatable {
    let activeWindowPlanIndices: [Int]
    let activeWindowTitlesByPlanIndex: [Int: String]
    let activeCGWindowIDsByPlanIndex: [Int: CGWindowID]

    func satisfies(
        action: SpaceFixtureWindowMutationPressureAction,
        targetWindowPlanIndex: Int,
        retiredCGWindowID: CGWindowID
    ) -> Bool {
        switch action {
        case .open:
            guard activeWindowPlanIndices.contains(
                targetWindowPlanIndex
            ),
            let targetID = activeCGWindowIDsByPlanIndex[
                targetWindowPlanIndex
            ], targetID > 0
            else {
                return false
            }
            return Self.cgWindowIsOnScreen(targetID)
        case .close:
            return !activeWindowPlanIndices.contains(
                targetWindowPlanIndex
            )
                && (retiredCGWindowID == 0
                    || !Self.cgWindowExists(retiredCGWindowID))
        }
    }

    private static func cgWindowExists(_ windowID: CGWindowID) -> Bool {
        cgWindowInfo(windowID) != nil
    }

    private static func cgWindowIsOnScreen(
        _ windowID: CGWindowID
    ) -> Bool {
        (cgWindowInfo(windowID)?[kCGWindowIsOnscreen]
            as? NSNumber)?.boolValue == true
    }

    private static func cgWindowInfo(
        _ windowID: CGWindowID
    ) -> [CFString: Any]? {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            windowID
        ) as? [[CFString: Any]]
        else {
            return nil
        }
        return raw.first {
            ($0[kCGWindowNumber] as? NSNumber)?.uint32Value
                == windowID
        }
    }
}

struct SpaceFixtureWindowMutationPressureEvidence: Equatable {
    let sequence: UInt64
    let generation: Int
    let action: SpaceFixtureWindowMutationPressureAction
    let identity: SpaceFixtureWindowMutationPressureIdentity
    let targetWindowPlanIndex: Int
    let retiredCGWindowID: CGWindowID
    let readbackSatisfied: Bool
    let watchdogExpired: Bool
    let snapshot: SpaceFixtureWindowMutationPressureSnapshot

    init(
        sequence: UInt64,
        generation: Int,
        action: SpaceFixtureWindowMutationPressureAction,
        identity: SpaceFixtureWindowMutationPressureIdentity,
        targetWindowPlanIndex: Int,
        retiredCGWindowID: CGWindowID,
        readbackSatisfied: Bool,
        watchdogExpired: Bool,
        snapshot: SpaceFixtureWindowMutationPressureSnapshot
    ) {
        self.sequence = sequence
        self.generation = generation
        self.action = action
        self.identity = identity
        self.targetWindowPlanIndex = targetWindowPlanIndex
        self.retiredCGWindowID = retiredCGWindowID
        self.readbackSatisfied = readbackSatisfied
        self.watchdogExpired = watchdogExpired
        self.snapshot = snapshot
    }

    init?(notification: Notification) {
        guard let command =
                SpaceFixtureWindowMutationPressureCommand(
                    notification: notification
                ),
              let info = notification.userInfo,
              let bundleID = info["bundleIdentifier"] as? String,
              !bundleID.isEmpty,
              let pid = (info["processIdentifier"] as? NSNumber)?
                .int32Value,
              pid > 0,
              let indices = (info["activeWindowPlanIndices"]
                as? [NSNumber])?.map(\.intValue),
              indices == Array(Set(indices)).sorted()
        else {
            return nil
        }
        sequence = command.sequence
        generation = command.generation
        action = command.action
        targetWindowPlanIndex = command.targetWindowPlanIndex
        identity = SpaceFixtureWindowMutationPressureIdentity(
            bundleIdentifier: bundleID,
            processIdentifier: pid
        )
        retiredCGWindowID = (info["retiredCGWindowID"]
            as? NSNumber)?.uint32Value ?? 0
        readbackSatisfied = (info["readbackSatisfied"]
            as? NSNumber)?.boolValue == true
        watchdogExpired = (info["watchdogExpired"]
            as? NSNumber)?.boolValue == true
        snapshot = SpaceFixtureWindowMutationPressureSnapshot(
            activeWindowPlanIndices: indices,
            activeWindowTitlesByPlanIndex: Self.stringDictionary(
                info["activeWindowTitlesByPlanIndex"]
            ),
            activeCGWindowIDsByPlanIndex: Self.cgDictionary(
                info["activeCGWindowIDsByPlanIndex"]
            )
        )
    }

    var userInfo: [String: Any] {
        [
            "sequence": NSNumber(value: sequence),
            "generation": NSNumber(value: generation),
            "action": action.rawValue,
            "targetWindowPlanIndex": NSNumber(
                value: targetWindowPlanIndex
            ),
            "bundleIdentifier": identity.bundleIdentifier,
            "processIdentifier": NSNumber(
                value: identity.processIdentifier
            ),
            "retiredCGWindowID": NSNumber(value: retiredCGWindowID),
            "readbackSatisfied": NSNumber(value: readbackSatisfied),
            "watchdogExpired": NSNumber(value: watchdogExpired),
            "activeWindowPlanIndices": snapshot
                .activeWindowPlanIndices.map(NSNumber.init),
            "activeWindowTitlesByPlanIndex": Dictionary(
                uniqueKeysWithValues: snapshot
                    .activeWindowTitlesByPlanIndex.map {
                        (String($0.key), $0.value)
                    }
            ),
            "activeCGWindowIDsByPlanIndex": Dictionary(
                uniqueKeysWithValues: snapshot
                    .activeCGWindowIDsByPlanIndex.map {
                        (String($0.key), NSNumber(value: $0.value))
                    }
            )
        ]
    }

    private static func stringDictionary(_ value: Any?) -> [Int: String] {
        guard let values = value as? [String: String] else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: values.compactMap { key, value in
                guard let index = Int(key) else { return nil }
                return (index, value)
            }
        )
    }

    private static func cgDictionary(_ value: Any?) -> [Int: CGWindowID] {
        guard let values = value as? [String: NSNumber] else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: values.compactMap { key, value in
                guard let index = Int(key) else { return nil }
                return (index, value.uint32Value)
            }
        )
    }
}
