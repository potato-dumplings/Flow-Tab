import Foundation

enum SpaceFixturePostTerminationRefreshObservationPolicy {
    static let evidenceWatchdog: TimeInterval = 10
}

struct SpaceFixturePostTerminationRefreshEvidence: Equatable {
    let reason: String
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let matchedPending: Bool
    let pendingGeneration: Int?
    let refreshed: Bool

    var logFields: String {
        "reason=\(reason) appID=\(bundleIdentifier) "
            + "pid=\(processIdentifier) "
            + "matchedPending=\(matchedPending ? 1 : 0) "
            + "pendingGeneration="
            + "\(pendingGeneration.map(String.init) ?? "nil") "
            + "refreshed=\(refreshed)"
    }

    static func records(
        in contents: String
    ) -> [SpaceFixturePostTerminationRefreshEvidence] {
        contents
            .split(whereSeparator: \.isNewline)
            .compactMap(parse)
    }

    private static func parse(
        line: Substring
    ) -> SpaceFixturePostTerminationRefreshEvidence? {
        let marker = "terminate post-refresh "
        guard let markerRange = line.range(of: marker) else {
            return nil
        }
        let tokens = line[markerRange.lowerBound...]
            .split(whereSeparator: \.isWhitespace)
        guard tokens.count == 8,
              tokens[0] == "terminate",
              tokens[1] == "post-refresh",
              let reason = value(in: tokens[2], key: "reason"),
              let bundleIdentifier = value(
                  in: tokens[3],
                  key: "appID"
              ),
              let processIdentifierText = value(
                  in: tokens[4],
                  key: "pid"
              ),
              let processIdentifier = pid_t(
                  processIdentifierText
              ),
              processIdentifier > 0,
              let matchedPendingText = value(
                  in: tokens[5],
                  key: "matchedPending"
              ),
              let pendingGenerationText = value(
                  in: tokens[6],
                  key: "pendingGeneration"
              ),
              let refreshedText = value(
                  in: tokens[7],
                  key: "refreshed"
              )
        else {
            return nil
        }

        let matchedPending: Bool
        switch matchedPendingText {
        case "1":
            matchedPending = true
        case "0":
            matchedPending = false
        default:
            return nil
        }

        let pendingGeneration: Int?
        if pendingGenerationText == "nil" {
            pendingGeneration = nil
        } else {
            guard let generation = Int(pendingGenerationText),
                  generation > 0
            else {
                return nil
            }
            pendingGeneration = generation
        }

        let refreshed: Bool
        switch refreshedText {
        case "true":
            refreshed = true
        case "false":
            refreshed = false
        default:
            return nil
        }

        return SpaceFixturePostTerminationRefreshEvidence(
            reason: reason,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            matchedPending: matchedPending,
            pendingGeneration: pendingGeneration,
            refreshed: refreshed
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

struct SpaceFixturePostTerminationRefreshSnapshot: Equatable {
    let runtimeLogSnapshot: FlowTabUITestRuntimeLogSnapshot
    let records: [SpaceFixturePostTerminationRefreshEvidence]

    init(
        runtimeLogSnapshot: FlowTabUITestRuntimeLogSnapshot
    ) {
        self.runtimeLogSnapshot = runtimeLogSnapshot
        records = SpaceFixturePostTerminationRefreshEvidence
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

private final class SpaceFixturePostTerminationRefreshExpectation {
    private static let expectedReason =
        "workspace_notification"

    let bundleIdentifier: String
    private(set) var processIdentifier: pid_t?
    private(set) var requestGeneration: Int?

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    func reset() {
        processIdentifier = nil
        requestGeneration = nil
    }

    func bind(
        processIdentifier: pid_t,
        requestGeneration: Int
    ) {
        self.processIdentifier = processIdentifier
        self.requestGeneration = requestGeneration
    }

    func matchingRecord(
        in snapshot: SpaceFixturePostTerminationRefreshSnapshot
    ) -> SpaceFixturePostTerminationRefreshEvidence? {
        guard let processIdentifier,
              let requestGeneration
        else {
            return nil
        }
        return snapshot.records.last {
            $0.reason == Self.expectedReason
                && $0.bundleIdentifier == bundleIdentifier
                && $0.processIdentifier == processIdentifier
                && $0.matchedPending
                && $0.pendingGeneration == requestGeneration
                && $0.refreshed
        }
    }

    var diagnosticSummary: String {
        "expectedReason=\(Self.expectedReason) "
            + "expectedAppID=\(bundleIdentifier) "
            + "expectedPID="
            + "\(processIdentifier.map(String.init) ?? "unbound") "
            + "expectedPendingGeneration="
            + "\(requestGeneration.map(String.init) ?? "unbound") "
            + "expectedMatchedPending=1 expectedRefreshed=true"
    }
}

final class SpaceFixturePostTerminationRefreshObservationOwner {
    private let expectation:
        SpaceFixturePostTerminationRefreshExpectation
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            SpaceFixturePostTerminationRefreshSnapshot
        >

    convenience init(
        bundleIdentifier: String,
        baseline: FlowTabUITestRuntimeLogObservationBaseline
    ) {
        self.init(
            bundleIdentifier: bundleIdentifier,
            observationRegistration:
                baseline.observationRegistration(),
            readback: baseline.makeReadback
        )
    }

    init(
        bundleIdentifier: String,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestRuntimeLogSnapshot
    ) {
        let expectation =
            SpaceFixturePostTerminationRefreshExpectation(
                bundleIdentifier: bundleIdentifier
            )
        self.expectation = expectation
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: {
                SpaceFixturePostTerminationRefreshSnapshot(
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
    }

    func bindTarget(
        processIdentifier: pid_t,
        requestGeneration: Int
    ) {
        expectation.bind(
            processIdentifier: processIdentifier,
            requestGeneration: requestGeneration
        )
        conditionOwner.requestReadback(
            source: .triggerReadback
        )
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        SpaceFixturePostTerminationRefreshEvidence
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
        SpaceFixturePostTerminationRefreshEvidence
    >? {
        guard let snapshotEvidence =
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
