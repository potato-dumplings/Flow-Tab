#if FLOWTAB_TESTING
import Foundation

enum TabSwitchStressTarget:
    String,
    CaseIterable,
    Equatable,
    Sendable
{
    case home
    case logs
    case settings
}

struct TabSwitchStressPolicy:
    Equatable,
    Sendable
{
    static let defaultDurationSeconds = 30.0
    static let defaultCadenceMilliseconds = 20.0
    static let minimumDurationSeconds = 1.0
    static let minimumCadenceMilliseconds = 1.0

    private static let maximumRepresentableNanoseconds =
        UInt64.max / 4

    let durationNanoseconds: UInt64
    let cadenceNanoseconds: UInt64

    init(
        durationSeconds: Double,
        cadenceMilliseconds: Double
    ) {
        durationNanoseconds = Self.normalizedNanoseconds(
            rawValue: durationSeconds,
            minimumValue: Self.minimumDurationSeconds,
            fallbackValue: Self.defaultDurationSeconds,
            scale: 1_000_000_000
        )
        cadenceNanoseconds = Self.normalizedNanoseconds(
            rawValue: cadenceMilliseconds,
            minimumValue:
                Self.minimumCadenceMilliseconds,
            fallbackValue:
                Self.defaultCadenceMilliseconds,
            scale: 1_000_000
        )
    }

    static var launchPolicy: TabSwitchStressPolicy {
        TabSwitchStressPolicy(
            durationSeconds:
                FlowTabTestLaunchOptions
                    .tabSwitchStressDurationSeconds,
            cadenceMilliseconds:
                FlowTabTestLaunchOptions
                    .tabSwitchStressIntervalMilliseconds
        )
    }

    var durationSeconds: TimeInterval {
        TimeInterval(durationNanoseconds)
            / 1_000_000_000
    }

    var cadenceMilliseconds: Double {
        Double(cadenceNanoseconds) / 1_000_000
    }

    var requiredSwitchCount: UInt64 {
        let quotient =
            durationNanoseconds / cadenceNanoseconds
        let remainder =
            durationNanoseconds % cadenceNanoseconds
        return quotient
            + (remainder == 0 ? 0 : 1)
    }

    func deadline(
        after startNanoseconds: UInt64
    ) -> UInt64 {
        let available =
            UInt64.max - startNanoseconds
        return startNanoseconds
            + min(durationNanoseconds, available)
    }

    private static func normalizedNanoseconds(
        rawValue: Double,
        minimumValue: Double,
        fallbackValue: Double,
        scale: Double
    ) -> UInt64 {
        let finiteValue =
            rawValue.isFinite ? rawValue : fallbackValue
        let scaled =
            max(minimumValue, finiteValue) * scale
        guard scaled
                < Double(
                    maximumRepresentableNanoseconds
                )
        else {
            return maximumRepresentableNanoseconds
        }
        return UInt64(
            scaled.rounded(
                .toNearestOrAwayFromZero
            )
        )
    }
}

enum TabSwitchStressPhase:
    String,
    Equatable,
    Sendable
{
    case started
    case selectionObserved
    case completed
    case cancelled
}

struct TabSwitchStressEvidence:
    Equatable,
    Sendable
{
    let ownerGeneration: UInt64
    let transitionGeneration: UInt64
    let phase: TabSwitchStressPhase
    let policy: TabSwitchStressPolicy
    let attemptCount: UInt64
    let switchCount: UInt64
    let homeSwitchCount: UInt64
    let logsSwitchCount: UInt64
    let settingsSwitchCount: UInt64
    let requestedTarget: TabSwitchStressTarget?
    let observedTarget: TabSwitchStressTarget?
    let elapsedNanoseconds: UInt64
    let durationSatisfied: Bool
    let workloadSatisfied: Bool

    var logFields: String {
        "phase=\(phase.rawValue) "
            + "ownerGeneration=\(ownerGeneration) "
            + "transitionGeneration=\(transitionGeneration) "
            + "durationNanoseconds="
            + "\(policy.durationNanoseconds) "
            + "cadenceNanoseconds="
            + "\(policy.cadenceNanoseconds) "
            + "requiredSwitches="
            + "\(policy.requiredSwitchCount) "
            + "attempts=\(attemptCount) "
            + "switches=\(switchCount) "
            + "homeSwitches=\(homeSwitchCount) "
            + "logsSwitches=\(logsSwitchCount) "
            + "settingsSwitches=\(settingsSwitchCount) "
            + "requested="
            + "\(requestedTarget?.rawValue ?? "none") "
            + "observed="
            + "\(observedTarget?.rawValue ?? "none") "
            + "elapsedNanoseconds="
            + "\(elapsedNanoseconds) "
            + "durationSatisfied="
            + "\(durationSatisfied) "
            + "workloadSatisfied="
            + "\(workloadSatisfied)"
    }
}

@MainActor
protocol TabSwitchStressMonotonicClock:
    AnyObject
{
    var nowNanoseconds: UInt64 { get }
}

@MainActor
final class TabSwitchStressSystemMonotonicClock:
    TabSwitchStressMonotonicClock
{
    var nowNanoseconds: UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

protocol TabSwitchStressCancellable:
    AnyObject
{
    func cancel()
}

@MainActor
protocol TabSwitchStressScheduling:
    AnyObject
{
    func schedule(
        afterNanoseconds nanoseconds: UInt64,
        _ action:
            @escaping @MainActor @Sendable () -> Void
    ) -> any TabSwitchStressCancellable
}

private final class TabSwitchStressTaskToken:
    TabSwitchStressCancellable
{
    private let task: Task<Void, Never>

    @MainActor
    init(
        nanoseconds: UInt64,
        action:
            @escaping @MainActor @Sendable () -> Void
    ) {
        task = Task { @MainActor in
            do {
                try await Task.sleep(
                    nanoseconds: nanoseconds
                )
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task.cancel()
    }

    deinit {
        task.cancel()
    }
}

@MainActor
final class TabSwitchStressTaskScheduler:
    TabSwitchStressScheduling
{
    func schedule(
        afterNanoseconds nanoseconds: UInt64,
        _ action:
            @escaping @MainActor @Sendable () -> Void
    ) -> any TabSwitchStressCancellable {
        TabSwitchStressTaskToken(
            nanoseconds: nanoseconds,
            action: action
        )
    }
}
#endif
