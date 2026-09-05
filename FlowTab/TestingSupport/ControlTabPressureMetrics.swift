#if FLOWTAB_TESTING
import Darwin
import Foundation
import CoreGraphics

enum ControlTabPressurePhase: String, CaseIterable, Sendable {
    case open
    case forward
    case reverse
    case commit
    case cancel
    case cooldown
}

enum ControlTabPressureCommandAction: String, Sendable {
    case open
    case forward
    case reverse
    case commit
    case cancel
    case physicalOpen
    case physicalForward
    case physicalReverse
    case physicalCommit
    case physicalCancel
    case cooldownBegin
    case cooldownEnd

    var phase: ControlTabPressurePhase? {
        switch self {
        case .open, .physicalOpen:
            .open
        case .forward, .physicalForward:
            .forward
        case .reverse, .physicalReverse:
            .reverse
        case .commit, .physicalCommit:
            .commit
        case .cancel, .physicalCancel:
            .cancel
        case .cooldownEnd:
            .cooldown
        case .cooldownBegin:
            nil
        }
    }

}

enum ControlTabPressureObservationStrategy: Equatable, Sendable {
    case firstVisibleFrame
    case commandReturn
    case externalStateReadback
    case cancelledPresentationReadback
}

extension ControlTabPressureCommandAction {
    var observationStrategy: ControlTabPressureObservationStrategy? {
        switch self {
        case .open:
            .firstVisibleFrame
        case .forward, .reverse, .commit, .cancel:
            .externalStateReadback
        case .physicalOpen,
             .physicalForward,
             .physicalReverse,
             .physicalCommit:
            .externalStateReadback
        case .physicalCancel:
            .cancelledPresentationReadback
        case .cooldownBegin, .cooldownEnd:
            nil
        }
    }
}

struct ControlTabProcessCPUSnapshot: Equatable, Sendable {
    let userNanoseconds: UInt64
    let systemNanoseconds: UInt64
    let isValid: Bool

    init(
        userNanoseconds: UInt64,
        systemNanoseconds: UInt64,
        isValid: Bool = true
    ) {
        self.userNanoseconds = userNanoseconds
        self.systemNanoseconds = systemNanoseconds
        self.isValid = isValid
    }

    init(runtimeSnapshot: RuntimeProcessCPUSnapshot) {
        self.init(
            userNanoseconds: runtimeSnapshot.userNanoseconds,
            systemNanoseconds: runtimeSnapshot.systemNanoseconds,
            isValid: runtimeSnapshot.isValid
        )
    }

    var totalNanoseconds: UInt64? {
        guard isValid else { return nil }
        let result = userNanoseconds.addingReportingOverflow(
            systemNanoseconds
        )
        return result.overflow ? nil : result.partialValue
    }
}

struct ControlTabPressureDuration: Equatable, Sendable {
    let wallMilliseconds: Double
    let cpuTimeMilliseconds: Double
    let isValid: Bool

    var cpuPercent: Double {
        guard wallMilliseconds > 0 else { return 0 }
        return cpuTimeMilliseconds / wallMilliseconds * 100
    }
}

enum ControlTabPressureMetricRules {
    static func duration(
        startedAtNanoseconds: UInt64,
        completedAtNanoseconds: UInt64,
        startedCPU: ControlTabProcessCPUSnapshot,
        completedCPU: ControlTabProcessCPUSnapshot
    ) -> ControlTabPressureDuration {
        let wallClockIsValid =
            completedAtNanoseconds >= startedAtNanoseconds
        let cpuNanoseconds: UInt64?
        if let startedTotal = startedCPU.totalNanoseconds,
           let completedTotal = completedCPU.totalNanoseconds,
           completedTotal >= startedTotal
        {
            cpuNanoseconds = completedTotal - startedTotal
        } else {
            cpuNanoseconds = nil
        }
        let wallNanoseconds = wallClockIsValid
            ? completedAtNanoseconds - startedAtNanoseconds
            : 0
        return ControlTabPressureDuration(
            wallMilliseconds:
                Double(wallNanoseconds) / 1_000_000,
            cpuTimeMilliseconds:
                Double(cpuNanoseconds ?? 0) / 1_000_000,
            isValid: wallClockIsValid && cpuNanoseconds != nil
        )
    }
}

protocol ControlTabProcessCPUClock: AnyObject {
    func snapshot() -> ControlTabProcessCPUSnapshot
}

final class ControlTabSystemProcessCPUClock:
    ControlTabProcessCPUClock
{
    func snapshot() -> ControlTabProcessCPUSnapshot {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else {
            return ControlTabProcessCPUSnapshot(
                userNanoseconds: 0,
                systemNanoseconds: 0,
                isValid: false
            )
        }
        return ControlTabProcessCPUSnapshot(
            userNanoseconds: Self.nanoseconds(usage.ru_utime),
            systemNanoseconds: Self.nanoseconds(usage.ru_stime)
        )
    }

    private static func nanoseconds(_ value: timeval) -> UInt64 {
        let seconds = max(0, value.tv_sec)
        let microseconds = max(0, value.tv_usec)
        return UInt64(seconds) * 1_000_000_000
            + UInt64(microseconds) * 1_000
    }
}

struct ControlTabPressureMeasurementToken: Sendable {
    let sequence: UInt64
    let phase: ControlTabPressurePhase
    let startedAtNanoseconds: UInt64
    let startedCPU: ControlTabProcessCPUSnapshot
    let panelWasPresented: Bool
    let selectedAppIDBefore: String?
    let selectedWindowIDBefore: String?
    let selectedWindowCountBefore: Int
    let activationRequestGenerationBefore: UInt64
    let activationVerificationGenerationBefore: UInt64
    let completeProjectionUpdateGenerationBefore: UInt64
    let focusedSessionDiagnosticGenerationBefore: Int
    let windowContentRenderGenerationBefore: UInt64
    let reusableShellPreparationGenerationBefore: UInt64
    let panelHiddenGenerationBefore: UInt64
    let cleanupCompleteGenerationBefore: UInt64
    let presentationCleanupRequiredBefore: Bool

    func reusableShellPreparationCompleted(
        at completedGeneration: UInt64
    ) -> Bool {
        if presentationCleanupRequiredBefore {
            return completedGeneration
                > reusableShellPreparationGenerationBefore
        }
        return completedGeneration
            >= reusableShellPreparationGenerationBefore
    }
}

struct ControlTabActivationRequestReceipt: Equatable, Sendable {
    let generation: UInt64
    let issuedAtUptimeNanoseconds: UInt64
}

struct ControlTabActivationVerificationReceipt: Equatable, Sendable {
    let generation: UInt64
    let processIdentifier: pid_t
    let windowID: String?
    let cgWindowID: CGWindowID?
    let satisfied: Bool
    let verificationRequired: Bool
    let verifiedAtUptimeNanoseconds: UInt64
}

struct ControlTabPressureEvidence: Sendable {
    let sequence: UInt64
    let phase: ControlTabPressurePhase
    let startedAtNanoseconds: UInt64
    let completedAtNanoseconds: UInt64
    let duration: ControlTabPressureDuration
    let timingValid: Bool
    let satisfied: Bool
    let panelPresented: Bool
    let userVisible: Bool
    let selectedAppID: String?
    let selectedWindowIDBefore: String?
    let selectedWindowIDAfter: String?
    let projectedAppCount: Int
    let selectedWindowCount: Int
    let activationRequestIssued: Bool
    let activationVerified: Bool
    let activationTargetPID: pid_t
    let activationTargetWindowID: String?
    let activationTargetCGWindowID: CGWindowID?
    let latePresentationObserved: Bool
    let projectionGeneration: UInt64
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool
    let partitions: [String: Double]
    let milestones: [String: Double]
    let partitionsReconciled: Bool
    let spans: [ControlTabPressureSpan]
    let requiredComponentsPresent: Bool
    let timelineReconciled: Bool
    let componentTimingValid: Bool
    let watchdogExpired: Bool
}
#endif
