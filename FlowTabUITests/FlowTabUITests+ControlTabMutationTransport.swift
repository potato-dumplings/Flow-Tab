import Foundation
import XCTest

final class ControlTabMutationFixtureObserver {
    let route = SpaceFixtureWindowMutationPressureRoute(
        command: Notification.Name(
            "io.github.potato-dumplings.flowtab.mutation.command."
                + UUID().uuidString
        ),
        commandAcknowledgement: Notification.Name(
            "io.github.potato-dumplings.flowtab.mutation.command-ack."
                + UUID().uuidString
        ),
        evidence: Notification.Name(
            "io.github.potato-dumplings.flowtab.mutation.evidence."
                + UUID().uuidString
        ),
        evidenceAcknowledgement: Notification.Name(
            "io.github.potato-dumplings.flowtab.mutation.evidence-ack."
                + UUID().uuidString
        )
    )

    private let condition = NSCondition()
    private let queue = OperationQueue()
    private var commandToken: NSObjectProtocol?
    private var evidenceToken: NSObjectProtocol?
    private var commandAcknowledgements: Set<UInt64> = []
    private var evidenceByGeneration:
        [Int: SpaceFixtureWindowMutationPressureEvidence] = [:]
    private var sequence: UInt64 = 0
    private var generation = 0

    init() {
        queue.maxConcurrentOperationCount = 1
    }

    func start() {
        let center = DistributedNotificationCenter.default()
        commandToken = center.addObserver(
            forName: route.commandAcknowledgement,
            object: nil,
            queue: queue
        ) { [weak self] notification in
            guard let sequence = (notification.userInfo?["sequence"]
                as? NSNumber)?.uint64Value
            else { return }
            self?.condition.lock()
            self?.commandAcknowledgements.insert(sequence)
            self?.condition.broadcast()
            self?.condition.unlock()
        }
        evidenceToken = center.addObserver(
            forName: route.evidence,
            object: nil,
            queue: queue
        ) { [weak self] notification in
            guard let self,
                  let evidence =
                    SpaceFixtureWindowMutationPressureEvidence(
                        notification: notification
                    )
            else { return }
            center.postNotificationName(
                self.route.evidenceAcknowledgement,
                object: nil,
                userInfo: [
                    "generation": NSNumber(
                        value: evidence.generation
                    )
                ],
                deliverImmediately: true
            )
            self.condition.lock()
            self.evidenceByGeneration[evidence.generation] = evidence
            self.condition.broadcast()
            self.condition.unlock()
        }
    }

    func mutate(
        _ action: SpaceFixtureWindowMutationPressureAction,
        targetWindowPlanIndex: Int = 3,
        timeout: TimeInterval = 12,
        afterAcknowledgement: (() -> Void)? = nil
    ) -> SpaceFixtureWindowMutationPressureEvidence? {
        condition.lock()
        sequence &+= 1
        generation += 1
        let requestSequence = sequence
        let requestGeneration = generation
        condition.unlock()
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            DistributedNotificationCenter.default()
                .postNotificationName(
                    route.command,
                    object: nil,
                    userInfo: [
                        "sequence": NSNumber(value: requestSequence),
                        "generation": NSNumber(
                            value: requestGeneration
                        ),
                        "action": action.rawValue,
                        "targetWindowPlanIndex": NSNumber(
                            value: targetWindowPlanIndex
                        )
                    ],
                    deliverImmediately: true
                )
            if waitForCommandAcknowledgement(
                requestSequence,
                deadline: min(
                    deadline,
                    Date().addingTimeInterval(0.05)
                )
            ) {
                break
            }
        } while Date() < deadline
        guard commandAcknowledged(requestSequence) else {
            XCTFail(
                "Fixture mutation command acknowledgement expired "
                    + "generation=\(requestGeneration)"
            )
            return nil
        }
        afterAcknowledgement?()
        return waitForEvidence(
            requestGeneration,
            deadline: deadline
        )
    }

    func cancel() {
        let center = DistributedNotificationCenter.default()
        if let commandToken { center.removeObserver(commandToken) }
        if let evidenceToken { center.removeObserver(evidenceToken) }
        commandToken = nil
        evidenceToken = nil
        queue.cancelAllOperations()
    }

    private func waitForCommandAcknowledgement(
        _ sequence: UInt64,
        deadline: Date
    ) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        if commandAcknowledgements.contains(sequence) { return true }
        _ = condition.wait(until: deadline)
        return commandAcknowledgements.contains(sequence)
    }

    private func commandAcknowledged(_ sequence: UInt64) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return commandAcknowledgements.contains(sequence)
    }

    private func waitForEvidence(
        _ generation: Int,
        deadline: Date
    ) -> SpaceFixtureWindowMutationPressureEvidence? {
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let evidence = evidenceByGeneration[generation] {
                return evidence
            }
            guard condition.wait(until: deadline) else {
                XCTFail(
                    "Fixture mutation readback expired "
                        + "generation=\(generation)"
                )
                return nil
            }
        }
    }

    deinit {
        cancel()
    }
}
