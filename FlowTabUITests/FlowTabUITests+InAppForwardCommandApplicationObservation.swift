import Foundation
import XCTest

enum FlowTabUITestInAppForwardCommandApplicationObservationPolicy {
    static let watchdog: TimeInterval = 8
}

struct FlowTabUITestInAppHotkeyAdvanceApplicationRecord:
    Equatable
{
    let direction: String
    let key: String
    let sourceID: UUID
    let sequence: UInt64
    let inputGeneration: UInt64
    let sourceRegistrationGeneration: UInt64
    let sessionGeneration: Int
    let previousWindowID: String
    let selectedWindowID: String

    var logFields: String {
        "dir=\(direction) key=\(key) "
            + "source=\(sourceID.uuidString) "
            + "sequence=\(sequence) "
            + "inputGeneration=\(inputGeneration) "
            + "sourceRegistrationGeneration="
            + "\(sourceRegistrationGeneration) "
            + "sessionGeneration=\(sessionGeneration) "
            + "previousWindowID=\(previousWindowID) "
            + "selectedWindowID=\(selectedWindowID)"
    }

    static func records(
        in contents: String
    ) -> [Self] {
        contents
            .split(whereSeparator: \.isNewline)
            .compactMap(parse)
    }

    private static func parse(
        line: Substring
    ) -> Self? {
        let marker = "inAppHotkeyAdvance "
        guard let markerRange = line.range(of: marker) else {
            return nil
        }
        let tokens = line[markerRange.lowerBound...]
            .split(whereSeparator: \.isWhitespace)
        guard
            tokens.count == 12,
            tokens[0] == "inAppHotkeyAdvance",
            tokens[1] == "result=applied",
            let direction = value(
                in: tokens[2],
                key: "dir"
            ),
            let key = value(in: tokens[3], key: "key"),
            tokens[4] == "route=inAppWindowSwitcher",
            let sourceText = value(
                in: tokens[5],
                key: "source"
            ),
            let sourceID = UUID(uuidString: sourceText),
            let sequenceText = value(
                in: tokens[6],
                key: "sequence"
            ),
            let sequence = UInt64(sequenceText),
            sequence > 0,
            let inputGenerationText = value(
                in: tokens[7],
                key: "inputGeneration"
            ),
            let inputGeneration = UInt64(
                inputGenerationText
            ),
            inputGeneration > 0,
            let registrationGenerationText = value(
                in: tokens[8],
                key: "sourceRegistrationGeneration"
            ),
            let sourceRegistrationGeneration = UInt64(
                registrationGenerationText
            ),
            sourceRegistrationGeneration > 0,
            let sessionGenerationText = value(
                in: tokens[9],
                key: "sessionGeneration"
            ),
            let sessionGeneration = Int(
                sessionGenerationText
            ),
            sessionGeneration >= 0,
            let previousWindowID = value(
                in: tokens[10],
                key: "previousWindowID"
            ),
            let selectedWindowID = value(
                in: tokens[11],
                key: "selectedWindowID"
            ),
            previousWindowID != selectedWindowID
        else {
            return nil
        }

        return Self(
            direction: direction,
            key: key,
            sourceID: sourceID,
            sequence: sequence,
            inputGeneration: inputGeneration,
            sourceRegistrationGeneration:
                sourceRegistrationGeneration,
            sessionGeneration: sessionGeneration,
            previousWindowID: previousWindowID,
            selectedWindowID: selectedWindowID
        )
    }

    private static func value(
        in token: Substring,
        key: String
    ) -> String? {
        let prefix = "\(key)="
        guard token.hasPrefix(prefix) else { return nil }
        let value = token.dropFirst(prefix.count)
        return value.isEmpty ? nil : String(value)
    }
}

struct FlowTabUITestInAppForwardCommandApplicationSnapshot:
    Equatable
{
    let runtimeLogSnapshot: FlowTabUITestRuntimeLogSnapshot
    let records:
        [FlowTabUITestInAppHotkeyAdvanceApplicationRecord]

    init(
        runtimeLogSnapshot: FlowTabUITestRuntimeLogSnapshot
    ) {
        self.runtimeLogSnapshot = runtimeLogSnapshot
        records =
            FlowTabUITestInAppHotkeyAdvanceApplicationRecord
                .records(in: runtimeLogSnapshot.contents)
    }

    var diagnosticSummary: String {
        let recordSummary = records.isEmpty
            ? "none"
            : records.suffix(8)
                .map(\.logFields)
                .joined(separator: " | ")
        return "recordCount=\(records.count) "
            + "records=[\(recordSummary)] "
            + "runtime{\(runtimeLogSnapshot.diagnosticSummary)}"
    }
}

private final class
    FlowTabUITestInAppForwardCommandApplicationExpectation
{
    let expectedPreviousWindowID: String
    private(set) var initialRecordCount: Int?
    private(set) var isTriggerStarted = false

    init(expectedPreviousWindowID: String) {
        self.expectedPreviousWindowID =
            expectedPreviousWindowID
    }

    func reset() {
        initialRecordCount = nil
        isTriggerStarted = false
    }

    func establishInitialRecordCount(_ count: Int) {
        initialRecordCount = count
    }

    func markTriggerStarted() {
        isTriggerStarted = true
    }

    func matchingRecord(
        in snapshot:
            FlowTabUITestInAppForwardCommandApplicationSnapshot
    ) -> FlowTabUITestInAppHotkeyAdvanceApplicationRecord? {
        guard
            isTriggerStarted,
            let initialRecordCount,
            snapshot.records.count >= initialRecordCount
        else {
            return nil
        }
        return snapshot.records
            .dropFirst(initialRecordCount)
            .last {
                $0.direction == "forward"
                    && $0.key == "tabForward"
                    && $0.previousWindowID
                        == expectedPreviousWindowID
            }
    }

    var diagnosticSummary: String {
        "expectedDirection=forward expectedKey=tabForward "
            + "expectedPreviousWindowID="
            + "\(expectedPreviousWindowID) "
            + "initialRecordCount="
            + "\(initialRecordCount.map(String.init) ?? "unbound") "
            + "triggerStarted=\(isTriggerStarted)"
    }
}

final class
    FlowTabUITestInAppForwardCommandApplicationObservationOwner
{
    private let expectation:
        FlowTabUITestInAppForwardCommandApplicationExpectation
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestInAppForwardCommandApplicationSnapshot
        >

    convenience init(
        expectedPreviousWindowID: String,
        baseline: FlowTabUITestRuntimeLogObservationBaseline
    ) {
        self.init(
            expectedPreviousWindowID:
                expectedPreviousWindowID,
            observationRegistration:
                baseline.observationRegistration(),
            readback: baseline.makeReadback
        )
    }

    init(
        expectedPreviousWindowID: String,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestRuntimeLogSnapshot
    ) {
        let expectation =
            FlowTabUITestInAppForwardCommandApplicationExpectation(
                expectedPreviousWindowID:
                    expectedPreviousWindowID
            )
        self.expectation = expectation
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: {
                FlowTabUITestInAppForwardCommandApplicationSnapshot(
                    runtimeLogSnapshot: readback()
                )
            },
            isSatisfied: {
                expectation.matchingRecord(in: $0) != nil
            },
            describe: {
                expectation.diagnosticSummary
                    + " observed{\($0.diagnosticSummary)}"
            }
        )
    }

    func start() {
        expectation.reset()
        conditionOwner.start()
        if let initialEvidence = conditionOwner.latestEvidence {
            expectation.establishInitialRecordCount(
                initialEvidence.value.records.count
            )
        }
    }

    func markTriggerStarted() {
        expectation.markTriggerStarted()
        conditionOwner.requestReadback(
            source: .triggerReadback
        )
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestInAppHotkeyAdvanceApplicationRecord
    >? {
        guard
            let snapshotEvidence =
                conditionOwner.waitForResolution(
                    timeout: timeout
                ),
            let record = expectation.matchingRecord(
                in: snapshotEvidence.value
            )
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
        FlowTabUITestInAppHotkeyAdvanceApplicationRecord
    >? {
        guard
            let snapshotEvidence =
                conditionOwner.resolvedEvidence,
            let record = expectation.matchingRecord(
                in: snapshotEvidence.value
            )
        else {
            return nil
        }
        return FlowTabUITestConditionEvidence(
            generation: snapshotEvidence.generation,
            source: snapshotEvidence.source,
            value: record
        )
    }

    var diagnosticSummary: String {
        expectation.diagnosticSummary
            + " " + conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }

    deinit {
        cancel()
    }
}

extension FlowTabUITests {
    func performAndWaitForInAppForwardSelectionTransition(
        fromWindowID baselineWindowID: String,
        fromWindowNumber baselineWindowNumber: UInt32,
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        traceLabel: String
    ) throws
        -> FlowTabUITestSwitcherWindowSelectionTransitionResult
    {
        let logBaseline = makeRuntimeLogFileSnapshot()
        defer { logBaseline.cancel() }
        let applicationOwner =
            FlowTabUITestInAppForwardCommandApplicationObservationOwner(
                expectedPreviousWindowID: baselineWindowID,
                baseline: logBaseline
            )
        applicationOwner.start()
        defer { applicationOwner.cancel() }

        let transition =
            try performAndWaitForSwitcherWindowSelectionTransition(
                fromWindowNumber: baselineWindowNumber,
                in: app,
                diagnosticsSummary: diagnosticsSummary,
                traceLabel: traceLabel,
                trigger: {
                    applicationOwner.markTriggerStarted()
                    postFlowTabUITestSwitcherCommand(
                        .inAppForward,
                        traceLabel: traceLabel
                    )
                }
            )
        let applicationEvidence = try XCTUnwrap(
            applicationOwner.waitForResolution(
                timeout:
                    FlowTabUITestInAppForwardCommandApplicationObservationPolicy
                        .watchdog
            ),
            "In-App forward command application watchdog expired "
                + "for \(traceLabel). "
                + applicationOwner.diagnosticSummary
        )
        XCTAssertEqual(
            applicationEvidence.value.selectedWindowID,
            transition.windowID,
            "In-App forward command application and diagnostics "
                + "transition diverged for \(traceLabel). "
                + applicationOwner.diagnosticSummary
        )
        return transition
    }
}
