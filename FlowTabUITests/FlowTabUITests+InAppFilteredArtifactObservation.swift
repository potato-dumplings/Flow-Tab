import Foundation
import XCTest

enum FlowTabUITestInAppFilteredArtifactObservationPolicy {
    static let watchdog: TimeInterval = 8
}

struct FlowTabUITestInAppFilteredArtifactRecord: Equatable {
    enum Kind: String, CaseIterable {
        case fullscreenHostArtifacts =
            "filtered-fullscreen-host-artifacts"
        case fullscreenSiblingArtifacts =
            "filtered-fullscreen-sibling-artifacts"
        case fullscreenDuplicateSurfaces =
            "filtered-fullscreen-duplicate-surfaces"
        case cgOnlyCoveredByActivation =
            "filtered-cg-only-covered-by-activation"

        func accepts(stage: String) -> Bool {
            switch self {
            case .fullscreenHostArtifacts,
                 .fullscreenSiblingArtifacts:
                [
                    "pre-dedupe",
                    "presentation",
                    "window-record-projection",
                    "read-model-app-switcher-normalization",
                    "read-model-current-app-normalization"
                ].contains(stage)
            case .fullscreenDuplicateSurfaces:
                [
                    "ordering",
                    "presentation-final",
                    "window-record-projection-final",
                    "read-model-app-switcher-normalization-final",
                    "read-model-current-app-normalization-final"
                ].contains(stage)
            case .cgOnlyCoveredByActivation:
                [
                    "presentation",
                    "window-record-projection",
                    "read-model-app-switcher-normalization",
                    "read-model-current-app-normalization"
                ].contains(stage)
            }
        }
    }

    let appName: String
    let processIdentifier: pid_t
    let kind: Kind
    let stage: String
    let droppedCount: Int

    var logFields: String {
        "app=\(appName) pid=\(processIdentifier) "
            + "kind=\(kind.rawValue) stage=\(stage) "
            + "dropped=\(droppedCount)"
    }

    static func records(in contents: String) -> [Self] {
        contents.split(whereSeparator: \.isNewline)
        .compactMap { record(in: String($0)) }
    }

    private static func record(in line: String) -> Self? {
        let categoryMarker = "] [DEBUG] [AXMatch] "
        guard line.hasPrefix("["),
              let categoryRange = line.range(
                  of: categoryMarker
              )
        else {
            return nil
        }
        let payload = String(line[categoryRange.upperBound...])
        guard
            let kind = Kind.allCases.first(where: {
                payload.contains(" \($0.rawValue) ")
            }),
            let kindRange = payload.range(
                of: " \(kind.rawValue) "
            )
        else {
            return nil
        }

        let appName = payload[..<kindRange.lowerBound]
            .trimmingCharacters(in: .whitespaces)
        let fields = payload[kindRange.upperBound...]
            .split(separator: " ")
        guard !appName.isEmpty,
              fields.count == 3,
              let stage = value(
                  in: fields[0],
                  key: "stage"
              ),
              kind.accepts(stage: stage),
              let droppedText = value(
                  in: fields[1],
                  key: "dropped"
              ),
              let droppedCount = Int(droppedText),
              droppedCount > 0,
              let processIdentifierText = value(
                  in: fields[2],
                  key: "pid"
              ),
              let processIdentifier = pid_t(
                  processIdentifierText
              ),
              processIdentifier > 0
        else {
            return nil
        }
        return Self(
            appName: appName,
            processIdentifier: processIdentifier,
            kind: kind,
            stage: stage,
            droppedCount: droppedCount
        )
    }

    private static func value(
        in field: Substring,
        key: String
    ) -> String? {
        let prefix = "\(key)="
        guard field.hasPrefix(prefix) else { return nil }
        let value = field.dropFirst(prefix.count)
        return value.isEmpty ? nil : String(value)
    }
}

struct FlowTabUITestInAppFilteredArtifactSnapshot:
    Equatable
{
    let runtimeLogSnapshot: FlowTabUITestRuntimeLogSnapshot
    let records: [FlowTabUITestInAppFilteredArtifactRecord]

    init(
        runtimeLogSnapshot: FlowTabUITestRuntimeLogSnapshot
    ) {
        self.runtimeLogSnapshot = runtimeLogSnapshot
        records =
            FlowTabUITestInAppFilteredArtifactRecord.records(
                in: runtimeLogSnapshot.contents
            )
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
    FlowTabUITestInAppFilteredArtifactExpectation
{
    let expectedAppName: String
    let expectedProcessIdentifier: pid_t

    init(
        expectedAppName: String,
        expectedProcessIdentifier: pid_t
    ) {
        self.expectedAppName = expectedAppName
        self.expectedProcessIdentifier =
            expectedProcessIdentifier
    }

    func matchingRecord(
        in snapshot:
            FlowTabUITestInAppFilteredArtifactSnapshot
    ) -> FlowTabUITestInAppFilteredArtifactRecord? {
        snapshot.records.last {
            $0.appName == expectedAppName
                && $0.processIdentifier
                    == expectedProcessIdentifier
        }
    }

    var diagnosticSummary: String {
        "expectedApp=\(expectedAppName) "
            + "expectedPID=\(expectedProcessIdentifier)"
    }
}

final class
    FlowTabUITestInAppFilteredArtifactObservationOwner
{
    private let expectation:
        FlowTabUITestInAppFilteredArtifactExpectation
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestInAppFilteredArtifactSnapshot
        >

    convenience init(
        expectedAppName: String,
        expectedProcessIdentifier: pid_t,
        baseline: FlowTabUITestRuntimeLogObservationBaseline
    ) {
        self.init(
            expectedAppName: expectedAppName,
            expectedProcessIdentifier:
                expectedProcessIdentifier,
            observationRegistration:
                baseline.observationRegistration(),
            readback: baseline.makeReadback
        )
    }

    init(
        expectedAppName: String,
        expectedProcessIdentifier: pid_t,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestRuntimeLogSnapshot
    ) {
        let expectation =
            FlowTabUITestInAppFilteredArtifactExpectation(
                expectedAppName: expectedAppName,
                expectedProcessIdentifier:
                    expectedProcessIdentifier
            )
        self.expectation = expectation
        conditionOwner =
            FlowTabUITestConditionObservationOwner(
                observationRegistration:
                    observationRegistration,
                readback: {
                    FlowTabUITestInAppFilteredArtifactSnapshot(
                        runtimeLogSnapshot: readback()
                    )
                },
                isSatisfied: {
                    expectation.matchingRecord(in: $0)
                        != nil
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
        FlowTabUITestInAppFilteredArtifactRecord
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
        FlowTabUITestInAppFilteredArtifactRecord
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
