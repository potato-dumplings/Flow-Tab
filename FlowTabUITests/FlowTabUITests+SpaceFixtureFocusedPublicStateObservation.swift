import Foundation

enum SpaceFixtureFocusedPublicStateObservationPolicy {
    static let evidenceWatchdog: TimeInterval = 8
}

enum SpaceFixtureFocusedPublicStateEvidenceSource: String {
    case focusedTieBreak
    case publicExactBinding
}

struct SpaceFixtureFocusedPublicStateEvidence:
    Equatable,
    Hashable
{
    let processIdentifier: pid_t
    let axWindowID: String
    let cgWindowID: UInt32
    let source: SpaceFixtureFocusedPublicStateEvidenceSource

    var diagnosticSummary: String {
        "source=\(source.rawValue) "
            + "pid=\(processIdentifier) "
            + "ax=\(axWindowID) cg=\(cgWindowID)"
    }

    static func records(
        in contents: String
    ) -> [SpaceFixtureFocusedPublicStateEvidence] {
        let lines = contents.split(whereSeparator: \.isNewline)
        let focusedAssociations = Set(
            lines.flatMap(focusedAssociations(in:))
        )
        var records = lines.compactMap(focusedTieBreak(in:))
        records.append(
            contentsOf: lines.compactMap { line in
                guard let association =
                        publicExactBindingAssociation(in: line),
                      focusedAssociations.contains(association)
                else {
                    return nil
                }
                return SpaceFixtureFocusedPublicStateEvidence(
                    processIdentifier:
                        association.processIdentifier,
                    axWindowID: association.axWindowID,
                    cgWindowID: association.cgWindowID,
                    source: .publicExactBinding
                )
            }
        )

        var seen: Set<SpaceFixtureFocusedPublicStateEvidence> = []
        return records.filter { seen.insert($0).inserted }
    }

    private struct Association: Hashable {
        let processIdentifier: pid_t
        let axWindowID: String
        let cgWindowID: UInt32
    }

    private static func focusedTieBreak(
        in line: Substring
    ) -> SpaceFixtureFocusedPublicStateEvidence? {
        guard line.contains(
            "binding-assignment public-state-tiebreak"
        ),
        value(in: line, key: "state") == "focused",
        let axWindowID = value(in: line, key: "ax"),
        let processIdentifier = processIdentifier(
            in: axWindowID
        ),
        let cgWindowIDText = value(in: line, key: "cg"),
        let cgWindowID = UInt32(cgWindowIDText),
        cgWindowID > 0,
        let axCandidateCountText = value(
            in: line,
            key: "axCandidates"
        ),
        let axCandidateCount = Int(axCandidateCountText),
        axCandidateCount >= 2,
        let cgCandidateCountText = value(
            in: line,
            key: "cgCandidates"
        ),
        let cgCandidateCount = Int(cgCandidateCountText),
        cgCandidateCount >= 2
        else {
            return nil
        }
        return SpaceFixtureFocusedPublicStateEvidence(
            processIdentifier: processIdentifier,
            axWindowID: axWindowID,
            cgWindowID: cgWindowID,
            source: .focusedTieBreak
        )
    }

    private static func focusedAssociations(
        in line: Substring
    ) -> [Association] {
        guard line.contains("chrome-topology"),
              let processIdentifierText = value(
                  in: line,
                  key: "pid"
              ),
              let processIdentifier = pid_t(
                  processIdentifierText
              ),
              processIdentifier > 0,
              let axStart = line.range(of: " ax=["),
              let cgStart = line.range(
                  of: "] cg=[",
                  range: axStart.upperBound..<line.endIndex
              )
        else {
            return []
        }
        let axList = String(
            line[axStart.upperBound..<cgStart.lowerBound]
        )
        return axList
            .components(separatedBy: ",ax:")
            .enumerated()
            .compactMap { index, rawSegment in
                let segment = index == 0
                    ? rawSegment
                    : "ax:" + rawSegment
                return focusedAssociation(
                    in: segment,
                    processIdentifier: processIdentifier
                )
            }
    }

    private static func focusedAssociation(
        in segment: String,
        processIdentifier: pid_t
    ) -> Association? {
        guard segment.contains(":focused=1"),
              let axWindowID = axWindowID(
                  inTopologySegment: segment
              ),
              self.processIdentifier(in: axWindowID)
                == processIdentifier,
              let bridgeRange = segment.range(
                  of: ":bridgeCG="
              ),
              let bridgeEnd = segment[
                  bridgeRange.upperBound...
              ].firstIndex(of: ":"),
              let cgWindowID = UInt32(
                  segment[
                      bridgeRange.upperBound..<bridgeEnd
                  ]
              ),
              cgWindowID > 0
        else {
            return nil
        }
        return Association(
            processIdentifier: processIdentifier,
            axWindowID: axWindowID,
            cgWindowID: cgWindowID
        )
    }

    private static func publicExactBindingAssociation(
        in line: Substring
    ) -> Association? {
        guard line.contains("binding-confidence-change"),
              let axWindowID = value(in: line, key: "ax"),
              let processIdentifier = processIdentifier(
                  in: axWindowID
              ),
              let cgWindowIDText = value(in: line, key: "cg"),
              let cgWindowID = UInt32(cgWindowIDText),
              cgWindowID > 0,
              value(in: line, key: "windowID")
                == "cg:\(processIdentifier):\(cgWindowID)",
              let sourceTransition = value(
                  in: line,
                  key: "source"
              ),
              let confidenceTransition = value(
                  in: line,
                  key: "confidence"
              ),
              isPublicExactTransition(
                  sourceTransition,
                  confidenceTransition: confidenceTransition
              ),
              value(
                  in: line,
                  key: "verifiedFocusFallbackAX"
              ) == "0"
        else {
            return nil
        }
        return Association(
            processIdentifier: processIdentifier,
            axWindowID: axWindowID,
            cgWindowID: cgWindowID
        )
    }

    private static func isPublicExactTransition(
        _ sourceTransition: String,
        confidenceTransition: String
    ) -> Bool {
        let sources = sourceTransition.components(
            separatedBy: "->"
        )
        let confidences = confidenceTransition.components(
            separatedBy: "->"
        )
        guard sources.count == 2,
              confidences.count == 2
        else {
            return false
        }
        let previous = sources[0]
        let current = sources[1]
        return (
            current == "publicExactMatch"
                && confidences[1] == "exact"
        )
            || (
                previous == "publicExactMatch"
                    && current == "stickyBinding"
                    && confidences == ["exact", "sticky"]
            )
    }

    private static func axWindowID(
        inTopologySegment segment: String
    ) -> String? {
        let components = segment.split(
            separator: ":",
            maxSplits: 3,
            omittingEmptySubsequences: false
        )
        guard components.count == 4,
              components[0] == "ax",
              !components[1].isEmpty,
              !components[2].isEmpty
        else {
            return nil
        }
        return components.prefix(3).joined(separator: ":")
    }

    private static func processIdentifier(
        in axWindowID: String
    ) -> pid_t? {
        let components = axWindowID.split(
            separator: ":",
            omittingEmptySubsequences: false
        )
        guard components.count >= 3,
              components[0] == "ax",
              let processIdentifier = pid_t(components[1]),
              processIdentifier > 0
        else {
            return nil
        }
        return processIdentifier
    }

    private static func value(
        in line: Substring,
        key: String
    ) -> String? {
        let prefix = "\(key)="
        guard let token = line
            .split(whereSeparator: \.isWhitespace)
            .first(where: { $0.hasPrefix(prefix) })
        else {
            return nil
        }
        let value = token.dropFirst(prefix.count)
        return value.isEmpty ? nil : String(value)
    }
}

struct SpaceFixtureFocusedPublicStateSnapshot: Equatable {
    let runtimeLogSnapshot: FlowTabUITestRuntimeLogSnapshot
    let records: [SpaceFixtureFocusedPublicStateEvidence]

    init(runtimeLogSnapshot: FlowTabUITestRuntimeLogSnapshot) {
        self.runtimeLogSnapshot = runtimeLogSnapshot
        records = SpaceFixtureFocusedPublicStateEvidence.records(
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

private final class SpaceFixtureFocusedPublicStateExpectation {
    let bundleIdentifier: String
    private(set) var processIdentifier: pid_t?

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    func reset() {
        processIdentifier = nil
    }

    func bind(processIdentifier: pid_t) {
        self.processIdentifier = processIdentifier
    }

    func matchingRecord(
        in snapshot: SpaceFixtureFocusedPublicStateSnapshot
    ) -> SpaceFixtureFocusedPublicStateEvidence? {
        guard let processIdentifier else { return nil }
        return snapshot.records.last {
            $0.processIdentifier == processIdentifier
        }
    }

    var diagnosticSummary: String {
        "expectedAppID=\(bundleIdentifier) expectedPID="
            + "\(processIdentifier.map(String.init) ?? "unbound") "
            + "expectedSource=focusedTieBreak|publicExactBinding"
    }
}

final class SpaceFixtureFocusedPublicStateObservationOwner {
    private let expectation:
        SpaceFixtureFocusedPublicStateExpectation
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            SpaceFixtureFocusedPublicStateSnapshot
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
            SpaceFixtureFocusedPublicStateExpectation(
                bundleIdentifier: bundleIdentifier
            )
        self.expectation = expectation
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: {
                SpaceFixtureFocusedPublicStateSnapshot(
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

    func bindTarget(processIdentifier: pid_t) {
        expectation.bind(processIdentifier: processIdentifier)
        conditionOwner.requestReadback(source: .triggerReadback)
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        SpaceFixtureFocusedPublicStateEvidence
    >? {
        guard let snapshotEvidence =
                conditionOwner.waitForResolution(timeout: timeout),
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
        SpaceFixtureFocusedPublicStateEvidence
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
