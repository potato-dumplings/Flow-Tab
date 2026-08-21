import CoreGraphics
import Foundation
import XCTest

enum FlowTabUITestInAppVerifiedFocusReadbackObservationPolicy {
    static let watchdog: TimeInterval = 8
}

enum FlowTabUITestInAppVerifiedFocusReadbackBaselineIssue:
    String,
    Equatable
{
    case matchingRecordBeforeTrigger
}

struct FlowTabUITestInAppVerifiedFocusReadbackRecord:
    Equatable
{
    let processIdentifier: pid_t
    let windowID: String
    let windowNumber: CGWindowID
    let axWindowID: String
    let reusableWindowEvidence: FlowTabUITestReusableWindowEvidence

    var diagnosticSummary: String {
        "pid=\(processIdentifier) windowID=\(windowID) "
            + "cg=\(windowNumber) ax=\(axWindowID) "
            + "confidence="
            + reusableWindowEvidence
                .verifiedFocusConfidenceTransition + " "
            + "source="
            + reusableWindowEvidence
                .verifiedFocusSourceTransition + " "
            + "verifiedFocusFallbackAX=0"
    }

    static func records(in contents: String) -> [Self] {
        contents.split(whereSeparator: \.isNewline)
            .compactMap(record(in:))
    }

    private static func record(in line: Substring) -> Self? {
        let marker =
            "] [DEBUG] [AXMatch] binding-confidence-change "
        guard line.hasPrefix("["),
              let markerRange = line.range(of: marker)
        else {
            return nil
        }
        let detail = line[markerRange.upperBound...]
        guard let windowID = value(
                  in: detail,
                  key: "windowID"
              ),
              let identity = windowIdentity(in: windowID),
              let cgText = value(in: detail, key: "cg"),
              let windowNumber = CGWindowID(cgText),
              windowNumber > 0,
              windowNumber == identity.windowNumber,
              let axWindowID = value(in: detail, key: "ax"),
              axProcessIdentifier(in: axWindowID)
                == identity.processIdentifier,
              let confidenceTransition = value(
                  in: detail,
                  key: "confidence"
              ),
              let sourceTransition = value(
                  in: detail,
                  key: "source"
              ),
              let reusableWindowEvidence =
                  FlowTabUITestReusableWindowEvidence
                  .parseVerifiedFocusReadback(
                      confidenceTransition:
                          confidenceTransition,
                      sourceTransition: sourceTransition
                  ),
              value(
                  in: detail,
                  key: "verifiedFocusFallbackAX"
              ) == "0"
        else {
            return nil
        }
        return Self(
            processIdentifier: identity.processIdentifier,
            windowID: windowID,
            windowNumber: windowNumber,
            axWindowID: axWindowID,
            reusableWindowEvidence:
                reusableWindowEvidence
        )
    }

    private static func windowIdentity(
        in windowID: String
    ) -> (
        processIdentifier: pid_t,
        windowNumber: CGWindowID
    )? {
        let components = windowID.split(
            separator: ":",
            omittingEmptySubsequences: false
        )
        guard components.count == 3,
              components[0] == "cg",
              let processIdentifier = pid_t(components[1]),
              processIdentifier > 0,
              let windowNumber = CGWindowID(components[2]),
              windowNumber > 0
        else {
            return nil
        }
        return (processIdentifier, windowNumber)
    }

    private static func axProcessIdentifier(
        in axWindowID: String
    ) -> pid_t? {
        let components = axWindowID.split(
            separator: ":",
            omittingEmptySubsequences: false
        )
        guard components.count == 3,
              components[0] == "ax",
              let processIdentifier = pid_t(components[1]),
              processIdentifier > 0,
              let windowIndex = Int(components[2]),
              windowIndex >= 0
        else {
            return nil
        }
        return processIdentifier
    }

    private static func value(
        in detail: Substring,
        key: String
    ) -> String? {
        let prefix = "\(key)="
        guard let token = detail
            .split(whereSeparator: \.isWhitespace)
            .first(where: { $0.hasPrefix(prefix) })
        else {
            return nil
        }
        let value = token.dropFirst(prefix.count)
        return value.isEmpty ? nil : String(value)
    }
}

struct FlowTabUITestInAppVerifiedFocusReadbackSnapshot:
    Equatable
{
    let runtimeLogSnapshot: FlowTabUITestRuntimeLogSnapshot
    let records: [FlowTabUITestInAppVerifiedFocusReadbackRecord]

    init(runtimeLogSnapshot: FlowTabUITestRuntimeLogSnapshot) {
        self.runtimeLogSnapshot = runtimeLogSnapshot
        records =
            FlowTabUITestInAppVerifiedFocusReadbackRecord.records(
                in: runtimeLogSnapshot.contents
            )
    }

    var diagnosticSummary: String {
        let recordSummary = records.isEmpty
            ? "none"
            : records.suffix(8)
                .map(\.diagnosticSummary)
                .joined(separator: " | ")
        return "recordCount=\(records.count) "
            + "records=[\(recordSummary)] "
            + "runtime{\(runtimeLogSnapshot.diagnosticSummary)}"
    }
}

private final class
    FlowTabUITestInAppVerifiedFocusReadbackExpectation
{
    let expectedProcessIdentifier: pid_t
    let expectedWindowID: String
    let expectedWindowNumber: CGWindowID

    init(
        expectedProcessIdentifier: pid_t,
        expectedWindowID: String,
        expectedWindowNumber: CGWindowID
    ) {
        self.expectedProcessIdentifier = expectedProcessIdentifier
        self.expectedWindowID = expectedWindowID
        self.expectedWindowNumber = expectedWindowNumber
    }

    func matchingRecord(
        in snapshot:
            FlowTabUITestInAppVerifiedFocusReadbackSnapshot
    ) -> FlowTabUITestInAppVerifiedFocusReadbackRecord? {
        snapshot.records.last {
            $0.processIdentifier == expectedProcessIdentifier
                && $0.windowID == expectedWindowID
                && $0.windowNumber == expectedWindowNumber
        }
    }

    var diagnosticSummary: String {
        "expectedPID=\(expectedProcessIdentifier) "
            + "expectedWindowID=\(expectedWindowID) "
            + "expectedCG=\(expectedWindowNumber) "
            + "expectedReusableEvidence="
            + FlowTabUITestReusableWindowEvidence
                .allCases
                .map {
                    $0.verifiedFocusConfidenceTransition
                        + "/"
                        + $0.verifiedFocusSourceTransition
                }
                .joined(separator: ",")
    }
}

private final class FlowTabUITestInAppVerifiedFocusReadbackState {
    let expectation:
        FlowTabUITestInAppVerifiedFocusReadbackExpectation

    private(set) var baselineIssue:
        FlowTabUITestInAppVerifiedFocusReadbackBaselineIssue?
    private(set) var matchingRecordAfterTrigger:
        FlowTabUITestInAppVerifiedFocusReadbackRecord?
    private(set) var isTriggerStarted = false
    private(set) var isTriggerCompleted = false

    init(
        expectation:
            FlowTabUITestInAppVerifiedFocusReadbackExpectation
    ) {
        self.expectation = expectation
    }

    func reset() {
        baselineIssue = nil
        matchingRecordAfterTrigger = nil
        isTriggerStarted = false
        isTriggerCompleted = false
    }

    func observe(
        _ snapshot:
            FlowTabUITestInAppVerifiedFocusReadbackSnapshot
    ) -> Bool {
        let record = expectation.matchingRecord(in: snapshot)
        guard isTriggerStarted else {
            if record != nil {
                baselineIssue = .matchingRecordBeforeTrigger
            }
            return false
        }
        if baselineIssue == nil, let record {
            matchingRecordAfterTrigger = record
        }
        return baselineIssue == nil
            && isTriggerCompleted
            && matchingRecordAfterTrigger != nil
    }

    func markTriggerStarted() {
        isTriggerStarted = true
    }

    func markTriggerCompleted() {
        isTriggerCompleted = true
    }

    var diagnosticSummary: String {
        "triggerStarted=\(isTriggerStarted ? 1 : 0) "
            + "triggerCompleted=\(isTriggerCompleted ? 1 : 0) "
            + "baselineIssue=\(baselineIssue?.rawValue ?? "none")"
    }
}

final class FlowTabUITestInAppVerifiedFocusReadbackObservationOwner:
    FlowTabUITestInAppConfirmationTriggerLifecycle
{
    private let state:
        FlowTabUITestInAppVerifiedFocusReadbackState
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestInAppVerifiedFocusReadbackSnapshot
        >

    convenience init(
        expectedProcessIdentifier: pid_t,
        expectedWindowID: String,
        expectedWindowNumber: CGWindowID,
        baseline: FlowTabUITestRuntimeLogObservationBaseline
    ) {
        self.init(
            expectedProcessIdentifier: expectedProcessIdentifier,
            expectedWindowID: expectedWindowID,
            expectedWindowNumber: expectedWindowNumber,
            observationRegistration:
                baseline.observationRegistration(),
            readback: baseline.makeReadback
        )
    }

    init(
        expectedProcessIdentifier: pid_t,
        expectedWindowID: String,
        expectedWindowNumber: CGWindowID,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestRuntimeLogSnapshot
    ) {
        let expectation =
            FlowTabUITestInAppVerifiedFocusReadbackExpectation(
                expectedProcessIdentifier:
                    expectedProcessIdentifier,
                expectedWindowID: expectedWindowID,
                expectedWindowNumber: expectedWindowNumber
            )
        let state = FlowTabUITestInAppVerifiedFocusReadbackState(
            expectation: expectation
        )
        self.state = state
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: {
                FlowTabUITestInAppVerifiedFocusReadbackSnapshot(
                    runtimeLogSnapshot: readback()
                )
            },
            isSatisfied: state.observe,
            describe: {
                expectation.diagnosticSummary
                    + " observed{\($0.diagnosticSummary)}"
            }
        )
    }

    func start() {
        state.reset()
        conditionOwner.start()
    }

    func markTriggerStarted() {
        guard !state.isTriggerStarted else { return }
        conditionOwner.requestReadback(source: .triggerReadback)
        state.markTriggerStarted()
    }

    func markTriggerCompleted() {
        guard state.isTriggerStarted,
              !state.isTriggerCompleted
        else {
            return
        }
        state.markTriggerCompleted()
        conditionOwner.requestReadback(source: .triggerReadback)
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestInAppVerifiedFocusReadbackRecord
    >? {
        guard let snapshotEvidence =
                conditionOwner.waitForResolution(timeout: timeout),
              let record = state.matchingRecordAfterTrigger
        else {
            return nil
        }
        return FlowTabUITestConditionEvidence(
            generation: snapshotEvidence.generation,
            source: snapshotEvidence.source,
            value: record
        )
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestInAppVerifiedFocusReadbackRecord
    >? {
        guard let snapshotEvidence = conditionOwner.resolvedEvidence,
              let record = state.matchingRecordAfterTrigger
        else {
            return nil
        }
        return FlowTabUITestConditionEvidence(
            generation: snapshotEvidence.generation,
            source: snapshotEvidence.source,
            value: record
        )
    }

    var baselineIssue:
        FlowTabUITestInAppVerifiedFocusReadbackBaselineIssue?
    {
        state.baselineIssue
    }

    var diagnosticSummary: String {
        state.expectation.diagnosticSummary
            + " " + state.diagnosticSummary
            + " " + conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }

    deinit {
        cancel()
    }
}
