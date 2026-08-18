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
    private let afterReadback: () -> Void

    private var scheduledCancellation:
        FlowTabUITestObservationCancellation?
    private var isCancelled = false

    init(
        oneShotRegistration:
            @escaping FlowTabUITestOneShotReadbackRegistration,
        readback: @escaping (
            FlowTabUITestConditionObservationSource
        ) -> Void,
        afterReadback: @escaping () -> Void
    ) {
        self.oneShotRegistration = oneShotRegistration
        self.readback = readback
        self.afterReadback = afterReadback
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
        guard !isCancelled else { return }
        afterReadback()
        guard !isCancelled else { return }
        scheduleNext()
    }
}

enum FlowTabUITestConditionReadbackScheduler {
    static func serialRegistration(
        oneShotRegistration:
            @escaping FlowTabUITestOneShotReadbackRegistration,
        afterReadback: @escaping () -> Void = {}
    ) -> FlowTabUITestConditionObservationRegistration {
        { readback in
            let schedule =
                FlowTabUITestSerialConditionReadbackSchedule(
                    oneShotRegistration:
                        oneShotRegistration,
                    readback: readback,
                    afterReadback: afterReadback
                )
            schedule.start()
            return FlowTabUITestObservationCancellation {
                schedule.cancel()
            }
        }
    }

    static func mainRunLoopRegistration(
        cadence: TimeInterval,
        afterReadback: @escaping () -> Void = {}
    ) -> FlowTabUITestConditionObservationRegistration {
        serialRegistration(
            oneShotRegistration:
                mainRunLoopOneShotRegistration(
                    cadence: cadence
                ),
            afterReadback: afterReadback
        )
    }

    static func mainRunLoopOneShotRegistration(
        cadence: TimeInterval
    ) -> FlowTabUITestOneShotReadbackRegistration {
        { readback in
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
