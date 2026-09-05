import CoreGraphics
import Foundation

@MainActor
final class SpaceFixtureWindowMutationPressureOwner {
    typealias SnapshotProvider =
        @MainActor () -> SpaceFixtureWindowMutationPressureSnapshot
    typealias Mutation =
        @MainActor (
            SpaceFixtureWindowMutationPressureAction,
            Int
        ) -> Void

    private let route: SpaceFixtureWindowMutationPressureRoute
    private let identity:
        SpaceFixtureWindowMutationPressureIdentity
    private let snapshotProvider: SnapshotProvider
    private let mutate: Mutation
    private var commandToken: NSObjectProtocol?
    private var evidenceAcknowledgementToken: NSObjectProtocol?
    private var readbackTask: Task<Void, Never>?
    private var deliveryTasks: [Int: Task<Void, Never>] = [:]
    private var generationGate =
        SpaceFixtureWindowMutationPressureGenerationGate()

    init(
        route: SpaceFixtureWindowMutationPressureRoute,
        identity: SpaceFixtureWindowMutationPressureIdentity,
        snapshotProvider: @escaping SnapshotProvider,
        mutate: @escaping Mutation
    ) {
        self.route = route
        self.identity = identity
        self.snapshotProvider = snapshotProvider
        self.mutate = mutate
    }

    func start() {
        let center = DistributedNotificationCenter.default()
        commandToken = center.addObserver(
            forName: route.command,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let command =
                    SpaceFixtureWindowMutationPressureCommand(
                        notification: notification
                    )
            else { return }
            Task { @MainActor [weak self] in
                self?.receive(command)
            }
        }
        evidenceAcknowledgementToken = center.addObserver(
            forName: route.evidenceAcknowledgement,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let generation = (notification.userInfo?["generation"]
                as? NSNumber)?.intValue
            Task { @MainActor [weak self] in
                guard let generation else { return }
                self?.deliveryTasks[generation]?.cancel()
                self?.deliveryTasks[generation] = nil
            }
        }
    }

    func cancel() {
        let center = DistributedNotificationCenter.default()
        if let commandToken { center.removeObserver(commandToken) }
        if let evidenceAcknowledgementToken {
            center.removeObserver(evidenceAcknowledgementToken)
        }
        commandToken = nil
        evidenceAcknowledgementToken = nil
        readbackTask?.cancel()
        deliveryTasks.values.forEach { $0.cancel() }
        deliveryTasks.removeAll()
    }

    private func receive(
        _ command: SpaceFixtureWindowMutationPressureCommand
    ) {
        DistributedNotificationCenter.default().postNotificationName(
            route.commandAcknowledgement,
            object: nil,
            userInfo: ["sequence": NSNumber(value: command.sequence)],
            deliverImmediately: true
        )
        guard generationGate.accepts(
            sequence: command.sequence,
            generation: command.generation
        ) else { return }
        readbackTask?.cancel()
        let before = snapshotProvider()
        let retiredID = before.activeCGWindowIDsByPlanIndex[
            command.targetWindowPlanIndex
        ] ?? 0
        mutate(
            command.action,
            command.targetWindowPlanIndex
        )
        readbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(10)
            while !Task.isCancelled {
                let snapshot = self.snapshotProvider()
                if snapshot.satisfies(
                    action: command.action,
                    targetWindowPlanIndex:
                        command.targetWindowPlanIndex,
                    retiredCGWindowID: retiredID
                ) {
                    self.publish(
                        command: command,
                        retiredID: retiredID,
                        snapshot: snapshot,
                        watchdogExpired: false
                    )
                    return
                }
                if Date() >= deadline {
                    self.publish(
                        command: command,
                        retiredID: retiredID,
                        snapshot: snapshot,
                        watchdogExpired: true
                    )
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func publish(
        command: SpaceFixtureWindowMutationPressureCommand,
        retiredID: CGWindowID,
        snapshot: SpaceFixtureWindowMutationPressureSnapshot,
        watchdogExpired: Bool
    ) {
        let evidence = SpaceFixtureWindowMutationPressureEvidence(
            sequence: command.sequence,
            generation: command.generation,
            action: command.action,
            identity: identity,
            targetWindowPlanIndex: command.targetWindowPlanIndex,
            retiredCGWindowID: retiredID,
            readbackSatisfied: !watchdogExpired,
            watchdogExpired: watchdogExpired,
            snapshot: snapshot
        )
        deliveryTasks[command.generation]?.cancel()
        deliveryTasks[command.generation] = Task { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(5)
            while !Task.isCancelled, Date() < deadline {
                DistributedNotificationCenter.default()
                    .postNotificationName(
                        self.route.evidence,
                        object: nil,
                        userInfo: evidence.userInfo,
                        deliverImmediately: true
                    )
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    deinit {
        readbackTask?.cancel()
        deliveryTasks.values.forEach { $0.cancel() }
    }
}
