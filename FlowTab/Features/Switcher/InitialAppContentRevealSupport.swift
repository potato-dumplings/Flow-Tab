import Foundation

struct InitialAppContentRevealPolicy: Equatable {
    let watchdogInterval: TimeInterval

    static let `default` = InitialAppContentRevealPolicy(
        watchdogInterval: 0.25
    )
}

struct InitialAppContentRevealTarget: Equatable {
    let observationGeneration: Int
    let presentationGeneration: Int
    let milestone: SwitcherRenderMilestone
    let renderGeneration: UInt64
}

struct InitialAppContentRevealEvidence: Equatable {
    let target: InitialAppContentRevealTarget
    let event: SwitcherRenderMilestoneEvent
}

struct InitialAppContentRenderPassEvidence: Equatable {
    let target: InitialAppContentRevealTarget
    let durationMilliseconds: Double
    let completedAtMilliseconds: Double
}

struct InitialAppContentRevealWatchdogFailure: Equatable {
    let target: InitialAppContentRevealTarget
    let lastEvent: SwitcherRenderMilestoneEvent?

    var logFields: String {
        let lastMilestone = lastEvent?.milestone.rawValue ?? "none"
        let lastGeneration = lastEvent.map {
            String($0.renderGeneration)
        } ?? "none"
        return "condition=currentAppContentDraw "
            + "expectedPresentationGeneration=\(target.presentationGeneration) "
            + "expectedMilestone=\(target.milestone.rawValue) "
            + "expectedRenderGeneration=\(target.renderGeneration) "
            + "lastMilestone=\(lastMilestone) "
            + "lastRenderGeneration=\(lastGeneration)"
    }
}

@MainActor
protocol InitialAppContentRevealCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol InitialAppContentRevealScheduling: AnyObject {
    func scheduleRenderPass(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any InitialAppContentRevealCancellable

    func scheduleWatchdog(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any InitialAppContentRevealCancellable
}

@MainActor
private final class InitialAppContentRevealToken:
    InitialAppContentRevealCancellable
{
    private let task: Task<Void, Never>

    init(
        interval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        task = Task { @MainActor in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(
                        (interval * 1_000_000_000).rounded()
                    )
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
private final class InitialAppContentRenderPassToken:
    InitialAppContentRevealCancellable
{
    private let task: Task<Void, Never>

    init(
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        task = Task { @MainActor in
            await Task.yield()
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
final class InitialAppContentRevealScheduler:
    InitialAppContentRevealScheduling
{
    func scheduleRenderPass(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any InitialAppContentRevealCancellable {
        InitialAppContentRenderPassToken(action: action)
    }

    func scheduleWatchdog(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any InitialAppContentRevealCancellable {
        InitialAppContentRevealToken(
            interval: interval,
            action: action
        )
    }
}
