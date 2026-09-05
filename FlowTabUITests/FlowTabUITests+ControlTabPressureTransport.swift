import Foundation
import XCTest

struct ControlTabPressureUITestSpan {
    let phase: String
    let sequence: UInt64
    let name: String
    let parent: String
    let startedAtNanoseconds: UInt64
    let completedAtNanoseconds: UInt64
    let wallMilliseconds: Double
    let cpuTimeMilliseconds: Double
    let cpuPercent: Double
    let timingValid: Bool
    let scope: String
    let outcome: String
    let workUnits: Int
}

struct ControlTabPressureUITestEvidence {
    let sequence: UInt64
    let phase: String
    let startedAtNanoseconds: UInt64
    let completedAtNanoseconds: UInt64
    let wallMilliseconds: Double
    let cpuTimeMilliseconds: Double
    let cpuPercent: Double
    let timingValid: Bool
    let satisfied: Bool
    let panelPresented: Bool
    let userVisible: Bool
    let selectedAppID: String
    let selectedWindowIDBefore: String
    let selectedWindowIDAfter: String
    let projectedAppCount: Int
    let selectedWindowCount: Int
    let projectionGeneration: UInt64
    let activationRequestIssued: Bool
    let activationVerified: Bool
    let activationTargetPID: Int32
    let activationTargetWindowID: String
    let activationTargetCGWindowID: UInt32
    let latePresentationObserved: Bool
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool
    let partitionsReconciled: Bool
    let requiredComponentsPresent: Bool
    let timelineReconciled: Bool
    let componentTimingValid: Bool
    let watchdogExpired: Bool
    let partitions: [String: Double]
    let milestones: [String: Double]
    let spans: [ControlTabPressureUITestSpan]

    init?(notification: Notification) {
        guard let info = notification.userInfo,
              let sequence = Self.uint64("sequence", info),
              let phase = info["phase"] as? String,
              let startedAtNanoseconds = Self.uint64(
                "startedAtNanoseconds",
                info
              ),
              let completedAtNanoseconds = Self.uint64(
                "completedAtNanoseconds",
                info
              ),
              let wallMilliseconds = Self.double(
                "wallMilliseconds",
                info
              ),
              let cpuTimeMilliseconds = Self.double(
                "cpuTimeMilliseconds",
                info
              ),
              let cpuPercent = Self.double("cpuPercent", info),
              let selectedAppID = info["selectedAppID"] as? String,
              let selectedWindowIDBefore =
                info["selectedWindowIDBefore"] as? String,
              let selectedWindowIDAfter =
                info["selectedWindowIDAfter"] as? String,
              let projectedAppCount = Self.int(
                "projectedAppCount",
                info
              ),
              let selectedWindowCount = Self.int(
                "selectedWindowCount",
                info
              ),
              let projectionGeneration = Self.uint64(
                "projectionGeneration",
                info
              )
        else {
            return nil
        }
        self.sequence = sequence
        self.phase = phase
        self.startedAtNanoseconds = startedAtNanoseconds
        self.completedAtNanoseconds = completedAtNanoseconds
        self.wallMilliseconds = wallMilliseconds
        self.cpuTimeMilliseconds = cpuTimeMilliseconds
        self.cpuPercent = cpuPercent
        timingValid = Self.bool("timingValid", info)
        self.satisfied = Self.bool("satisfied", info)
        self.panelPresented = Self.bool("panelPresented", info)
        self.userVisible = Self.bool("userVisible", info)
        self.selectedAppID = selectedAppID
        self.selectedWindowIDBefore = selectedWindowIDBefore
        self.selectedWindowIDAfter = selectedWindowIDAfter
        self.projectedAppCount = projectedAppCount
        self.selectedWindowCount = selectedWindowCount
        self.projectionGeneration = projectionGeneration
        activationRequestIssued = Self.bool(
            "activationRequestIssued",
            info
        )
        activationVerified = Self.bool(
            "activationVerified",
            info
        )
        activationTargetPID = Int32(
            Self.int("activationTargetPID", info) ?? 0
        )
        activationTargetWindowID =
            info["activationTargetWindowID"] as? String ?? "none"
        activationTargetCGWindowID = UInt32(
            Self.int("activationTargetCGWindowID", info) ?? 0
        )
        latePresentationObserved = Self.bool(
            "latePresentationObserved",
            info
        )
        accessibilityTrusted = Self.bool(
            "accessibilityTrusted",
            info
        )
        screenCaptureTrusted = Self.bool(
            "screenCaptureTrusted",
            info
        )
        partitionsReconciled = Self.bool(
            "partitionsReconciled",
            info
        )
        requiredComponentsPresent = Self.bool(
            "requiredComponentsPresent",
            info
        )
        timelineReconciled = Self.bool(
            "timelineReconciled",
            info
        )
        componentTimingValid = Self.bool(
            "componentTimingValid",
            info
        )
        watchdogExpired = Self.bool("watchdogExpired", info)
        partitions = Self.metrics("partitions", info)
        milestones = Self.metrics("milestones", info)
        spans = Self.spans("spans", info)
    }

    private static func uint64(
        _ key: String,
        _ info: [AnyHashable: Any]
    ) -> UInt64? {
        (info[key] as? NSNumber)?.uint64Value
    }

    private static func int(
        _ key: String,
        _ info: [AnyHashable: Any]
    ) -> Int? {
        (info[key] as? NSNumber)?.intValue
    }

    private static func double(
        _ key: String,
        _ info: [AnyHashable: Any]
    ) -> Double? {
        (info[key] as? NSNumber)?.doubleValue
    }

    private static func bool(
        _ key: String,
        _ info: [AnyHashable: Any]
    ) -> Bool {
        (info[key] as? NSNumber)?.boolValue ?? false
    }

    private static func metrics(
        _ key: String,
        _ info: [AnyHashable: Any]
    ) -> [String: Double] {
        (info[key] as? [String: NSNumber])?
            .mapValues(\.doubleValue) ?? [:]
    }

    private static func spans(
        _ key: String,
        _ info: [AnyHashable: Any]
    ) -> [ControlTabPressureUITestSpan] {
        guard let values = info[key] as? [[String: Any]] else {
            return []
        }
        return values.compactMap { value in
            guard let phase = value["phase"] as? String,
                  let sequence = (value["sequence"] as? NSNumber)?
                    .uint64Value,
                  let name = value["name"] as? String,
                  let parent = value["parent"] as? String,
                  let started = (value["startedAtNanoseconds"]
                    as? NSNumber)?.uint64Value,
                  let completed = (value["completedAtNanoseconds"]
                    as? NSNumber)?.uint64Value,
                  let wall = (value["wallMilliseconds"]
                    as? NSNumber)?.doubleValue,
                  let cpu = (value["cpuTimeMilliseconds"]
                    as? NSNumber)?.doubleValue,
                  let cpuPercent = (value["cpuPercent"]
                    as? NSNumber)?.doubleValue,
                  let scope = value["scope"] as? String,
                  let outcome = value["outcome"] as? String
            else {
                return nil
            }
            return ControlTabPressureUITestSpan(
                phase: phase,
                sequence: sequence,
                name: name,
                parent: parent,
                startedAtNanoseconds: started,
                completedAtNanoseconds: completed,
                wallMilliseconds: wall,
                cpuTimeMilliseconds: cpu,
                cpuPercent: cpuPercent,
                timingValid: (value["timingValid"] as? NSNumber)?
                    .boolValue ?? false,
                scope: scope,
                outcome: outcome,
                workUnits: (value["workUnits"] as? NSNumber)?
                    .intValue ?? 0
            )
        }
    }
}

final class ControlTabPressureUITestObserver {
    let commandNotificationName = Notification.Name(
        "io.github.potato-dumplings.flowtab.control-tab.command."
            + UUID().uuidString
    )
    let commandAcknowledgementNotificationName = Notification.Name(
        "io.github.potato-dumplings.flowtab.control-tab.command-ack."
            + UUID().uuidString
    )
    let evidenceNotificationName = Notification.Name(
        "io.github.potato-dumplings.flowtab.control-tab.evidence."
            + UUID().uuidString
    )
    let evidenceAcknowledgementNotificationName = Notification.Name(
        "io.github.potato-dumplings.flowtab.control-tab.evidence-ack."
            + UUID().uuidString
    )

    private let condition = NSCondition()
    private let queue = OperationQueue()
    private var evidenceToken: NSObjectProtocol?
    private var commandToken: NSObjectProtocol?
    private var receivedEvidence:
        [UInt64: ControlTabPressureUITestEvidence] = [:]
    private var acknowledgedCommands: [UInt64: Bool] = [:]
    private var lastConsumedEvidenceSequence: UInt64 = 0
    private var lastAcknowledgedCommandSequence: UInt64 = 0
    private var nextSequence: UInt64 = 0

    init() {
        queue.maxConcurrentOperationCount = 1
    }

    var launchEnvironment: [String: String] {
        var environment = [
            "FLOWTAB_CONTROL_TAB_COMMAND_NOTIFICATION":
                commandNotificationName.rawValue,
            "FLOWTAB_CONTROL_TAB_COMMAND_ACK_NOTIFICATION":
                commandAcknowledgementNotificationName.rawValue,
            "FLOWTAB_CONTROL_TAB_EVIDENCE_NOTIFICATION":
                evidenceNotificationName.rawValue,
            "FLOWTAB_CONTROL_TAB_EVIDENCE_ACK_NOTIFICATION":
                evidenceAcknowledgementNotificationName.rawValue
        ]
        let processEnvironment = ProcessInfo.processInfo.environment
        if let recorderMode = processEnvironment[
            ControlTabPressureUITestEnvironment.recorderMode
        ] {
            environment[
                ControlTabPressureUITestEnvironment.recorderMode
            ] = recorderMode
        }
        return environment
    }

    func start() {
        let center = DistributedNotificationCenter.default()
        evidenceToken = center.addObserver(
            forName: evidenceNotificationName,
            object: nil,
            queue: queue
        ) { [weak self] notification in
            guard let self,
                  let evidence =
                    ControlTabPressureUITestEvidence(
                        notification: notification
                    )
            else {
                return
            }
            center.postNotificationName(
                self.evidenceAcknowledgementNotificationName,
                object: nil,
                userInfo: [
                    "sequence": NSNumber(value: evidence.sequence)
                ],
                deliverImmediately: true
            )
            self.condition.lock()
            if evidence.sequence
                > self.lastConsumedEvidenceSequence
            {
                self.receivedEvidence[evidence.sequence] = evidence
            }
            self.condition.broadcast()
            self.condition.unlock()
        }
        commandToken = center.addObserver(
            forName: commandAcknowledgementNotificationName,
            object: nil,
            queue: queue
        ) { [weak self] notification in
            guard let self,
                  let sequence = (
                    notification.userInfo?["sequence"]
                        as? NSNumber
                  )?.uint64Value,
                  let accepted = (
                    notification.userInfo?["accepted"]
                        as? NSNumber
                  )?.boolValue
            else {
                return
            }
            self.condition.lock()
            if sequence
                > self.lastAcknowledgedCommandSequence
            {
                self.acknowledgedCommands[sequence] =
                    accepted
                    || self.acknowledgedCommands[sequence] == true
            }
            self.condition.broadcast()
            self.condition.unlock()
        }
    }

    func post(_ action: String) -> UInt64? {
        condition.lock()
        nextSequence &+= 1
        let sequence = nextSequence
        condition.unlock()
        let deadline = Date().addingTimeInterval(
            ControlTabPressureUITestPolicy.eventWatchdogSeconds
        )
        repeat {
            DistributedNotificationCenter.default()
                .postNotificationName(
                    commandNotificationName,
                    object: nil,
                    userInfo: [
                        "sequence": NSNumber(value: sequence),
                        "action": action
                    ],
                    deliverImmediately: true
                )
            if waitForAcknowledgement(
                sequence,
                deadline: min(
                    deadline,
                    Date().addingTimeInterval(
                        ControlTabPressureUITestPolicy
                            .commandRetrySeconds
                    )
                )
            ) {
                return sequence
            }
        } while Date() < deadline
        XCTFail(
            "Control+Tab command acknowledgement expired "
                + "action=\(action) sequence=\(sequence)"
        )
        return nil
    }

    func wait(
        sequence: UInt64,
        phase: String
    ) -> ControlTabPressureUITestEvidence? {
        let deadline = Date().addingTimeInterval(
            ControlTabPressureUITestPolicy.eventWatchdogSeconds
        )
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let evidence = receivedEvidence[sequence],
               evidence.phase == phase {
                receivedEvidence[sequence] = nil
                lastConsumedEvidenceSequence = max(
                    lastConsumedEvidenceSequence,
                    sequence
                )
                return evidence
            }
            guard condition.wait(until: deadline) else {
                return nil
            }
        }
    }

    func cancel() {
        let center = DistributedNotificationCenter.default()
        if let evidenceToken {
            center.removeObserver(evidenceToken)
            self.evidenceToken = nil
        }
        if let commandToken {
            center.removeObserver(commandToken)
            self.commandToken = nil
        }
        queue.cancelAllOperations()
        condition.lock()
        receivedEvidence.removeAll()
        acknowledgedCommands.removeAll()
        condition.unlock()
    }

    private func waitForAcknowledgement(
        _ sequence: UInt64,
        deadline: Date
    ) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        if acknowledgedCommands[sequence] == true {
            acknowledgedCommands[sequence] = nil
            lastAcknowledgedCommandSequence = max(
                lastAcknowledgedCommandSequence,
                sequence
            )
            return true
        }
        _ = condition.wait(until: deadline)
        guard acknowledgedCommands[sequence] == true else {
            return false
        }
        acknowledgedCommands[sequence] = nil
        lastAcknowledgedCommandSequence = max(
            lastAcknowledgedCommandSequence,
            sequence
        )
        return true
    }

    deinit {
        cancel()
    }
}
