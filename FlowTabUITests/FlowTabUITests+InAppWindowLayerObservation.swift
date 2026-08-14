import CoreGraphics
import Foundation
import XCTest

enum FlowTabUITestInAppWindowLayerObservationPolicy {
    static let watchdog: TimeInterval = 8
}

struct FlowTabUITestInAppWindowLayerRecord: Equatable {
    enum SpaceEvidence: String {
        case observed
        case inferredFromTopology
    }

    let appName: String
    let processIdentifier: pid_t
    let windowID: String
    let windowNumber: CGWindowID
    let title: String
    let spaceEvidence: SpaceEvidence

    var diagnosticSummary: String {
        "app=\(appName) pid=\(processIdentifier) "
            + "windowID=\(windowID) cg=\(windowNumber) "
            + "title=\(title) source=stickyBinding "
            + "spaceEvidence=\(spaceEvidence.rawValue)"
    }

    static func records(in contents: String) -> [Self] {
        contents.split(whereSeparator: \.isNewline)
            .flatMap { records(inLine: String($0)) }
    }

    private struct LogIdentity {
        let appName: String
        let processIdentifier: pid_t
    }

    private static func records(inLine line: String) -> [Self] {
        guard line.hasPrefix("["),
              let identity = logIdentity(in: line),
              let detail = trailingContents(
                  in: line,
                  after: " detail=[",
                  before: "]"
              )
        else {
            return []
        }
        return entrySegments(in: detail).compactMap {
            record(in: $0, identity: identity)
        }
    }

    private static func record(
        in entry: String,
        identity: LogIdentity
    ) -> Self? {
        guard let windowID = contents(
                  in: entry,
                  after: ":id=",
                  before: ":title="
              ),
              let title = contents(
                  in: entry,
                  after: ":title=",
                  before: ":mode="
              ),
              !title.isEmpty,
              let cgText = contents(
                  in: entry,
                  after: ":cg=",
                  before: ":sticky="
              ),
              let windowNumber = CGWindowID(cgText),
              windowNumber > 0,
              contents(
                  in: entry,
                  after: ":sticky=",
                  before: ":source="
              ) == "1",
              contents(
                  in: entry,
                  after: ":source=",
                  before: ":spaceEvidence="
              ) == "stickyBinding",
              let spaceEvidenceText = contents(
                  in: entry,
                  after: ":spaceEvidence=",
                  before: ":publicAXRecovery="
              ),
              let spaceEvidence = SpaceEvidence(
                  rawValue: spaceEvidenceText
              ),
              windowID == "cg:\(identity.processIdentifier):\(windowNumber)"
        else {
            return nil
        }
        return Self(
            appName: identity.appName,
            processIdentifier: identity.processIdentifier,
            windowID: windowID,
            windowNumber: windowNumber,
            title: title,
            spaceEvidence: spaceEvidence
        )
    }

    private static func logIdentity(
        in line: String
    ) -> LogIdentity? {
        let marker =
            "] [DEBUG] [RuntimeFacts] window-entries app="
        guard let markerRange = line.range(of: marker),
              let pidRange = line.range(
                  of: " pid=",
                  range: markerRange.upperBound..<line.endIndex
              )
        else {
            return nil
        }
        let appName = String(
            line[markerRange.upperBound..<pidRange.lowerBound]
        )
        let pidStart = pidRange.upperBound
        let pidEnd = line[pidStart...].firstIndex(
            where: \.isWhitespace
        ) ?? line.endIndex
        guard !appName.isEmpty,
              let processIdentifier = pid_t(
                  line[pidStart..<pidEnd]
              ),
              processIdentifier > 0
        else {
            return nil
        }
        return LogIdentity(
            appName: appName,
            processIdentifier: processIdentifier
        )
    }

    private static func entrySegments(
        in detail: String
    ) -> [String] {
        let expression = try? NSRegularExpression(
            pattern: #"(?:^|,)[0-9]+:id="#
        )
        let nsDetail = detail as NSString
        let matches = expression?.matches(
            in: detail,
            range: NSRange(
                location: 0,
                length: nsDetail.length
            )
        ) ?? []
        return matches.enumerated().map { index, match in
            let startsWithComma = nsDetail.substring(
                with: NSRange(
                    location: match.range.location,
                    length: 1
                )
            ) == ","
            let start = match.range.location
                + (startsWithComma ? 1 : 0)
            let end = index + 1 < matches.count
                ? matches[index + 1].range.location
                : nsDetail.length
            return nsDetail.substring(
                with: NSRange(
                    location: start,
                    length: end - start
                )
            )
        }
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

    private static func trailingContents(
        in value: String,
        after startMarker: String,
        before endMarker: String
    ) -> String? {
        guard let startRange = value.range(of: startMarker),
              let endRange = value.range(
                  of: endMarker,
                  options: .backwards,
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

struct FlowTabUITestInAppWindowLayerSnapshot: Equatable {
    let runtimeLogSnapshot: FlowTabUITestRuntimeLogSnapshot
    let records: [FlowTabUITestInAppWindowLayerRecord]

    init(runtimeLogSnapshot: FlowTabUITestRuntimeLogSnapshot) {
        self.runtimeLogSnapshot = runtimeLogSnapshot
        records = FlowTabUITestInAppWindowLayerRecord.records(
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

private final class FlowTabUITestInAppWindowLayerExpectation {
    let expectedAppName: String
    let expectedProcessIdentifier: pid_t
    let expectedTitle: String

    init(
        expectedAppName: String,
        expectedProcessIdentifier: pid_t,
        expectedTitle: String
    ) {
        self.expectedAppName = expectedAppName
        self.expectedProcessIdentifier = expectedProcessIdentifier
        self.expectedTitle = expectedTitle
    }

    func matchingRecord(
        in snapshot: FlowTabUITestInAppWindowLayerSnapshot
    ) -> FlowTabUITestInAppWindowLayerRecord? {
        snapshot.records.last {
            $0.appName == expectedAppName
                && $0.processIdentifier
                    == expectedProcessIdentifier
                && $0.title == expectedTitle
        }
    }

    var diagnosticSummary: String {
        "expectedApp=\(expectedAppName) "
            + "expectedPID=\(expectedProcessIdentifier) "
            + "expectedTitle=\(expectedTitle)"
    }
}

final class FlowTabUITestInAppWindowLayerObservationOwner {
    private let expectation:
        FlowTabUITestInAppWindowLayerExpectation
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestInAppWindowLayerSnapshot
        >

    convenience init(
        expectedAppName: String,
        expectedProcessIdentifier: pid_t,
        expectedTitle: String,
        baseline: FlowTabUITestRuntimeLogObservationBaseline
    ) {
        self.init(
            expectedAppName: expectedAppName,
            expectedProcessIdentifier: expectedProcessIdentifier,
            expectedTitle: expectedTitle,
            observationRegistration:
                baseline.observationRegistration(),
            readback: baseline.makeReadback
        )
    }

    init(
        expectedAppName: String,
        expectedProcessIdentifier: pid_t,
        expectedTitle: String,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestRuntimeLogSnapshot
    ) {
        let expectation = FlowTabUITestInAppWindowLayerExpectation(
            expectedAppName: expectedAppName,
            expectedProcessIdentifier: expectedProcessIdentifier,
            expectedTitle: expectedTitle
        )
        self.expectation = expectation
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: {
                FlowTabUITestInAppWindowLayerSnapshot(
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
        FlowTabUITestInAppWindowLayerRecord
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
        FlowTabUITestInAppWindowLayerRecord
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
