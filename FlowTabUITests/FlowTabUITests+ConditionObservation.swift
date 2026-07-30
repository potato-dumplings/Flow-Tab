import AppKit
import Foundation
import XCTest

enum FlowTabUITestConditionObservationSource: String {
    case initialReadback
    case notificationReadback
    case scheduledReadback
    case watchdogReadback
}

struct FlowTabUITestConditionEvidence<Value> {
    let generation: UInt64
    let source: FlowTabUITestConditionObservationSource
    let value: Value
}

final class FlowTabUITestObservationCancellation {
    private var cancellation: (() -> Void)?

    init(_ cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        guard let cancellation else { return }
        self.cancellation = nil
        cancellation()
    }

    deinit {
        cancel()
    }
}

typealias FlowTabUITestConditionObservationRegistration =
    (
        @escaping (FlowTabUITestConditionObservationSource) -> Void
    ) -> FlowTabUITestObservationCancellation?

final class FlowTabUITestConditionObservationOwner<Value> {
    private let readback: () -> Value
    private let isSatisfied: (Value) -> Bool
    private let describe: (Value) -> String
    private let observationRegistration:
        FlowTabUITestConditionObservationRegistration?

    private var nextGeneration: UInt64 = 1
    private var currentGeneration: UInt64?
    private var eventCancellation: FlowTabUITestObservationCancellation?
    private var resolvedExpectation: XCTestExpectation?
    private var lastWaitResult: XCTWaiter.Result?

    private(set) var latestEvidence:
        FlowTabUITestConditionEvidence<Value>?
    private(set) var resolvedEvidence:
        FlowTabUITestConditionEvidence<Value>?

    init(
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? = nil,
        readback: @escaping () -> Value,
        isSatisfied: @escaping (Value) -> Bool,
        describe: @escaping (Value) -> String
    ) {
        self.observationRegistration = observationRegistration
        self.readback = readback
        self.isSatisfied = isSatisfied
        self.describe = describe
    }

    func start() {
        cancel()
        latestEvidence = nil
        resolvedEvidence = nil
        lastWaitResult = nil

        let generation = nextGeneration
        nextGeneration &+= 1
        currentGeneration = generation
        let resolvedExpectation = XCTestExpectation(
            description: "UI condition observation generation \(generation)"
        )
        resolvedExpectation.assertForOverFulfill = true
        self.resolvedExpectation = resolvedExpectation

        let registrationCancellation = observationRegistration? {
            [weak self] source in
            self?.observe(
                source: source,
                generation: generation
            )
        }
        eventCancellation = registrationCancellation
        if resolvedEvidence != nil {
            stopObservationInputs()
            return
        }
        observe(source: .initialReadback, generation: generation)
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<Value>? {
        if let resolvedEvidence {
            return resolvedEvidence
        }
        guard let currentGeneration, let resolvedExpectation else {
            return nil
        }

        let result = XCTWaiter.wait(
            for: [resolvedExpectation],
            timeout: timeout
        )
        lastWaitResult = result
        if result != .completed {
            observe(
                source: .watchdogReadback,
                generation: currentGeneration,
                allowsResolution: false
            )
            stopObservationInputs()
            self.currentGeneration = nil
            self.resolvedExpectation = nil
        }
        return resolvedEvidence
    }

    var diagnosticSummary: String {
        guard let latestEvidence else {
            return "unobserved"
        }
        let waitResult = lastWaitResult.map {
            " waitResult=\(String(describing: $0))"
        } ?? ""
        return "generation=\(latestEvidence.generation) "
            + "source=\(latestEvidence.source.rawValue) "
            + "last{\(describe(latestEvidence.value))}"
            + waitResult
    }

    func cancel() {
        currentGeneration = nil
        stopObservationInputs()
        resolvedExpectation = nil
    }

    deinit {
        stopObservationInputs()
    }

    private func observe(
        source: FlowTabUITestConditionObservationSource,
        generation: UInt64,
        allowsResolution: Bool = true
    ) {
        guard currentGeneration == generation,
              resolvedEvidence == nil
        else {
            return
        }
        let evidence = FlowTabUITestConditionEvidence(
            generation: generation,
            source: source,
            value: readback()
        )
        latestEvidence = evidence
        guard allowsResolution,
              isSatisfied(evidence.value)
        else {
            return
        }
        resolvedEvidence = evidence
        stopObservationInputs()
        resolvedExpectation?.fulfill()
    }

    private func stopObservationInputs() {
        eventCancellation?.cancel()
        eventCancellation = nil
    }
}

enum FlowTabUITestConditionObservationPolicy {
    static let xcuiReadbackCadence: TimeInterval = 0.1
}

enum FlowTabUITestConditionReadbackScheduler {
    static func mainRunLoopRegistration(
        cadence: TimeInterval
    ) -> FlowTabUITestConditionObservationRegistration {
        { readback in
            let timer = Timer(
                timeInterval: cadence,
                repeats: true
            ) { _ in
                readback(.scheduledReadback)
            }
            RunLoop.main.add(timer, forMode: .common)
            return FlowTabUITestObservationCancellation {
                timer.invalidate()
            }
        }
    }
}

struct FlowTabUITestFrontmostApplicationSnapshot: Equatable {
    let bundleIdentifier: String?

    var diagnosticSummary: String {
        "frontmostBundleIdentifier=\(bundleIdentifier ?? "nil")"
    }
}

final class FlowTabUITestFrontmostApplicationObservationOwner {
    private let expectedBundleIdentifier: String
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestFrontmostApplicationSnapshot
        >

    init(
        expectedBundleIdentifier: String,
        notificationCenter: NotificationCenter =
            NSWorkspace.shared.notificationCenter,
        activationNotificationName: Notification.Name =
            NSWorkspace.didActivateApplicationNotification,
        readback: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?
                .bundleIdentifier
        }
    ) {
        self.expectedBundleIdentifier = expectedBundleIdentifier
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: { callback in
                let token = notificationCenter.addObserver(
                    forName: activationNotificationName,
                    object: nil,
                    queue: .main
                ) { _ in
                    callback(.notificationReadback)
                }
                return FlowTabUITestObservationCancellation {
                    notificationCenter.removeObserver(token)
                }
            },
            readback: {
                FlowTabUITestFrontmostApplicationSnapshot(
                    bundleIdentifier: readback()
                )
            },
            isSatisfied: {
                $0.bundleIdentifier == expectedBundleIdentifier
            },
            describe: \.diagnosticSummary
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestFrontmostApplicationSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestFrontmostApplicationSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        "expected=\(expectedBundleIdentifier) "
            + conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

func assertTriggerMakesApplicationFrontmost(
    _ bundleIdentifier: String,
    timeout: TimeInterval,
    message: String,
    trigger: () -> Void
) {
    let owner = FlowTabUITestFrontmostApplicationObservationOwner(
        expectedBundleIdentifier: bundleIdentifier
    )
    owner.start()
    defer { owner.cancel() }

    trigger()

    guard owner.waitForResolution(timeout: timeout) != nil else {
        XCTFail("\(message) \(owner.diagnosticSummary)")
        return
    }
}
