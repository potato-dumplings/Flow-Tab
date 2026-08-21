import CoreGraphics
import Foundation
import XCTest

enum FlowTabUITestInAppWindowRequestObservationPolicy {
    static let watchdog: TimeInterval = 8
}

struct FlowTabUITestInAppWindowRequestRecord: Equatable {
    let appID: String
    let processIdentifier: pid_t
    let windowID: String
    let windowNumber: CGWindowID
    let title: String
    let reusableWindowEvidence: FlowTabUITestReusableWindowEvidence

    var diagnosticSummary: String {
        "appID=\(appID) pid=\(processIdentifier) "
            + "windowID=\(windowID) cg=\(windowNumber) "
            + "title=\(title) sticky=1 "
            + "source=\(reusableWindowEvidence.rawValue)"
    }

    static func records(in contents: String) -> [Self] {
        contents.split(whereSeparator: \.isNewline)
            .compactMap { record(in: String($0)) }
    }

    private static func record(in line: String) -> Self? {
        let marker =
            "] [INFO] [Activation] window-request appID="
        guard line.hasPrefix("["),
              let markerRange = line.range(of: marker),
              let pidRange = line.range(
                  of: " pid=",
                  range: markerRange.upperBound..<line.endIndex
              )
        else {
            return nil
        }
        let appID = String(
            line[markerRange.upperBound..<pidRange.lowerBound]
        )
        let pidStart = pidRange.upperBound
        let pidEnd = line[pidStart...].firstIndex(
            where: \.isWhitespace
        ) ?? line.endIndex
        guard !appID.isEmpty,
              let processIdentifier = pid_t(
                  line[pidStart..<pidEnd]
              ),
              processIdentifier > 0,
              let windowID = contents(
                  in: line,
                  after: " windowID=",
                  before: " title="
              ),
              let title = contents(
                  in: line,
                  after: " title=",
                  before: " mode="
              ),
              !title.isEmpty,
              let cgText = contents(
                  in: line,
                  after: " cg=",
                  before: " handle="
              ),
              let windowNumber = CGWindowID(cgText),
              windowNumber > 0,
              let stickyText = contents(
                  in: line,
                  after: " sticky=",
                  before: " source="
              ),
              let source = contents(
                  in: line,
                  after: " source=",
                  before: " publicAXRecovery="
              ),
              let reusableWindowEvidence =
                  FlowTabUITestReusableWindowEvidence
                  .parseCurrent(
                      hasStickyBinding: stickyText == "true",
                      source: source
                  ),
              windowID == "cg:\(processIdentifier):\(windowNumber)"
        else {
            return nil
        }
        return Self(
            appID: appID,
            processIdentifier: processIdentifier,
            windowID: windowID,
            windowNumber: windowNumber,
            title: title,
            reusableWindowEvidence:
                reusableWindowEvidence
        )
    }

    private static func contents(
        in value: String,
        after startMarker: String,
        before endMarker: String
    ) -> String? {
        guard let startRange = value.range(of: startMarker),
              let endRange = value.range(
                  of: endMarker,
                  range: startRange.upperBound..<value.endIndex
              )
        else {
            return nil
        }
        return String(
            value[startRange.upperBound..<endRange.lowerBound]
        )
    }
}

struct FlowTabUITestInAppWindowRequestSnapshot: Equatable {
    let runtimeLogSnapshot: FlowTabUITestRuntimeLogSnapshot
    let records: [FlowTabUITestInAppWindowRequestRecord]

    init(runtimeLogSnapshot: FlowTabUITestRuntimeLogSnapshot) {
        self.runtimeLogSnapshot = runtimeLogSnapshot
        records = FlowTabUITestInAppWindowRequestRecord.records(
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

private final class FlowTabUITestInAppWindowRequestExpectation {
    let expectedAppID: String
    let expectedProcessIdentifier: pid_t
    let expectedWindowID: String
    let expectedWindowNumber: CGWindowID
    let expectedTitle: String

    init(
        expectedAppID: String,
        expectedProcessIdentifier: pid_t,
        expectedWindowID: String,
        expectedWindowNumber: CGWindowID,
        expectedTitle: String
    ) {
        self.expectedAppID = expectedAppID
        self.expectedProcessIdentifier = expectedProcessIdentifier
        self.expectedWindowID = expectedWindowID
        self.expectedWindowNumber = expectedWindowNumber
        self.expectedTitle = expectedTitle
    }

    func matchingRecord(
        in snapshot: FlowTabUITestInAppWindowRequestSnapshot
    ) -> FlowTabUITestInAppWindowRequestRecord? {
        snapshot.records.last {
            $0.appID == expectedAppID
                && $0.processIdentifier
                    == expectedProcessIdentifier
                && $0.windowID == expectedWindowID
                && $0.windowNumber == expectedWindowNumber
                && $0.title == expectedTitle
        }
    }

    var diagnosticSummary: String {
        "expectedAppID=\(expectedAppID) "
            + "expectedPID=\(expectedProcessIdentifier) "
            + "expectedWindowID=\(expectedWindowID) "
            + "expectedCG=\(expectedWindowNumber) "
            + "expectedTitle=\(expectedTitle)"
    }
}

final class FlowTabUITestInAppWindowRequestObservationOwner {
    private let expectation:
        FlowTabUITestInAppWindowRequestExpectation
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestInAppWindowRequestSnapshot
        >

    convenience init(
        expectedAppID: String,
        expectedProcessIdentifier: pid_t,
        expectedWindowID: String,
        expectedWindowNumber: CGWindowID,
        expectedTitle: String,
        baseline: FlowTabUITestRuntimeLogObservationBaseline
    ) {
        self.init(
            expectedAppID: expectedAppID,
            expectedProcessIdentifier: expectedProcessIdentifier,
            expectedWindowID: expectedWindowID,
            expectedWindowNumber: expectedWindowNumber,
            expectedTitle: expectedTitle,
            observationRegistration:
                baseline.observationRegistration(),
            readback: baseline.makeReadback
        )
    }

    init(
        expectedAppID: String,
        expectedProcessIdentifier: pid_t,
        expectedWindowID: String,
        expectedWindowNumber: CGWindowID,
        expectedTitle: String,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestRuntimeLogSnapshot
    ) {
        let expectation = FlowTabUITestInAppWindowRequestExpectation(
            expectedAppID: expectedAppID,
            expectedProcessIdentifier: expectedProcessIdentifier,
            expectedWindowID: expectedWindowID,
            expectedWindowNumber: expectedWindowNumber,
            expectedTitle: expectedTitle
        )
        self.expectation = expectation
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: {
                FlowTabUITestInAppWindowRequestSnapshot(
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
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestInAppWindowRequestRecord
    >? {
        guard let snapshotEvidence =
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
        FlowTabUITestInAppWindowRequestRecord
    >? {
        guard let snapshotEvidence = conditionOwner.resolvedEvidence,
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
