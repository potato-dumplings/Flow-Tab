import Foundation

typealias FlowTabUITestOneShotReadbackRegistration =
    (
        @escaping () -> Void
    ) -> FlowTabUITestObservationCancellation

private final class FlowTabUITestSerialConditionReadbackSchedule {
    private let oneShotRegistration:
        FlowTabUITestOneShotReadbackRegistration
    private let readback:
        (FlowTabUITestConditionObservationSource) -> Void

    private var scheduledCancellation:
        FlowTabUITestObservationCancellation?
    private var isCancelled = false

    init(
        oneShotRegistration:
            @escaping FlowTabUITestOneShotReadbackRegistration,
        readback: @escaping (
            FlowTabUITestConditionObservationSource
        ) -> Void
    ) {
        self.oneShotRegistration = oneShotRegistration
        self.readback = readback
    }

    func start() {
        scheduleNext()
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        scheduledCancellation?.cancel()
        scheduledCancellation = nil
    }

    deinit {
        cancel()
    }

    private func scheduleNext() {
        guard !isCancelled,
              scheduledCancellation == nil
        else {
            return
        }
        scheduledCancellation = oneShotRegistration {
            [weak self] in
            self?.fire()
        }
    }

    private func fire() {
        guard !isCancelled else { return }
        scheduledCancellation = nil
        readback(.scheduledReadback)
        scheduleNext()
    }
}

enum FlowTabUITestConditionReadbackScheduler {
    static func serialRegistration(
        oneShotRegistration:
            @escaping FlowTabUITestOneShotReadbackRegistration
    ) -> FlowTabUITestConditionObservationRegistration {
        { readback in
            let schedule =
                FlowTabUITestSerialConditionReadbackSchedule(
                    oneShotRegistration:
                        oneShotRegistration,
                    readback: readback
                )
            schedule.start()
            return FlowTabUITestObservationCancellation {
                schedule.cancel()
            }
        }
    }

    static func mainRunLoopRegistration(
        cadence: TimeInterval
    ) -> FlowTabUITestConditionObservationRegistration {
        serialRegistration { readback in
            let timer = Timer(
                timeInterval: cadence,
                repeats: false
            ) { _ in
                readback()
            }
            RunLoop.main.add(timer, forMode: .common)
            return FlowTabUITestObservationCancellation {
                timer.invalidate()
            }
        }
    }
}
