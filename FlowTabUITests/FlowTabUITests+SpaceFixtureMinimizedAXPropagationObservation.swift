import Foundation

enum SpaceFixtureMinimizedAXPropagationObservationPolicy {
    static let evidenceWatchdog: TimeInterval = 8
}

struct SpaceFixtureMinimizedAXSourceEvidence: Equatable, Hashable {
    let appName: String
    let processIdentifier: pid_t
    let axWindowID: String
    let cgWindowID: UInt32
    let title: String

    var diagnosticSummary: String {
        "app=\(appName) pid=\(processIdentifier) "
            + "ax=\(axWindowID) cg=\(cgWindowID) "
            + "title=\(title)"
    }
}

struct SpaceFixtureMinimizedAXProjectionEvidence: Equatable, Hashable {
    let appName: String
    let processIdentifier: pid_t
    let axWindowID: String
    let cgWindowID: UInt32
    let title: String

    var diagnosticSummary: String {
        "app=\(appName) pid=\(processIdentifier) "
            + "ax=\(axWindowID) cg=\(cgWindowID) "
            + "title=\(title) minimized=1"
    }
}

struct SpaceFixtureMinimizedAXPropagationEvidence: Equatable {
    let source: SpaceFixtureMinimizedAXSourceEvidence
    let projection: SpaceFixtureMinimizedAXProjectionEvidence
}

private struct SpaceFixtureLocatedMinimizedAXSource {
    let lineIndex: Int
    let evidence: SpaceFixtureMinimizedAXSourceEvidence
}

private struct SpaceFixtureMinimizedAXProjectionLine {
    let lineIndex: Int
    let rawLine: String
    let records: [SpaceFixtureMinimizedAXProjectionEvidence]
}

struct SpaceFixtureMinimizedAXPropagationSnapshot {
    let runtimeLogSnapshot: FlowTabUITestRuntimeLogSnapshot

    fileprivate let sourceRecords:
        [SpaceFixtureLocatedMinimizedAXSource]
    fileprivate let projectionLines:
        [SpaceFixtureMinimizedAXProjectionLine]

    init(runtimeLogSnapshot: FlowTabUITestRuntimeLogSnapshot) {
        self.runtimeLogSnapshot = runtimeLogSnapshot
        let lines = runtimeLogSnapshot.contents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        sourceRecords = lines.enumerated().flatMap {
            lineIndex,
            line in
            SpaceFixtureMinimizedAXPropagationParser
                .sourceRecords(in: line)
                .map {
                    SpaceFixtureLocatedMinimizedAXSource(
                        lineIndex: lineIndex,
                        evidence: $0
                    )
                }
        }
        projectionLines = lines.enumerated().compactMap {
            lineIndex,
            line in
            let records =
                SpaceFixtureMinimizedAXPropagationParser
                .projectionRecords(in: line)
            guard !records.isEmpty else { return nil }
            return SpaceFixtureMinimizedAXProjectionLine(
                lineIndex: lineIndex,
                rawLine: line,
                records: records
            )
        }
    }

    fileprivate var projectionLineCounts: [String: Int] {
        projectionLines.reduce(into: [:]) {
            $0[$1.rawLine, default: 0] += 1
        }
    }

    var diagnosticSummary: String {
        let sources = sourceRecords.suffix(6)
            .map(\.evidence.diagnosticSummary)
            .joined(separator: " | ")
        let projections = projectionLines
            .flatMap(\.records)
            .suffix(6)
            .map(\.diagnosticSummary)
            .joined(separator: " | ")
        let sourceSummary = sources.isEmpty ? "none" : sources
        let projectionSummary = projections.isEmpty
            ? "none"
            : projections
        return "sourceCount=\(sourceRecords.count) "
            + "sources=[\(sourceSummary)] "
            + "projectionCount=\(projectionLines.flatMap(\.records).count) "
            + "projections=[\(projectionSummary)] "
            + "runtime{\(runtimeLogSnapshot.diagnosticSummary)}"
    }
}

private final class SpaceFixtureMinimizedAXPropagationExpectation {
    let appName: String
    let expectedWindowTitle: String

    private(set) var processIdentifier: pid_t?
    private var triggerProjectionLineCounts: [String: Int]?
    private var triggerCompleted = false

    init(appName: String, expectedWindowTitle: String) {
        self.appName = appName
        self.expectedWindowTitle = expectedWindowTitle
    }

    func reset() {
        processIdentifier = nil
        triggerProjectionLineCounts = nil
        triggerCompleted = false
    }

    func bind(processIdentifier: pid_t) {
        self.processIdentifier = processIdentifier
    }

    func beginTrigger(
        from snapshot: SpaceFixtureMinimizedAXPropagationSnapshot
    ) {
        triggerProjectionLineCounts =
            snapshot.projectionLineCounts
        triggerCompleted = false
    }

    func completeTrigger() {
        triggerCompleted = true
    }

    func matchingEvidence(
        in snapshot: SpaceFixtureMinimizedAXPropagationSnapshot
    ) -> SpaceFixtureMinimizedAXPropagationEvidence? {
        guard triggerCompleted,
              let processIdentifier,
              var remainingBaselineLines =
                  triggerProjectionLineCounts
        else {
            return nil
        }
        let sources = snapshot.sourceRecords.filter {
            matches($0.evidence, processIdentifier: processIdentifier)
        }
        for projectionLine in snapshot.projectionLines {
            if remainingBaselineLines[
                projectionLine.rawLine,
                default: 0
            ] > 0 {
                remainingBaselineLines[projectionLine.rawLine]! -= 1
                continue
            }
            for projection in projectionLine.records
                where matches(
                    projection,
                    processIdentifier: processIdentifier
                )
            {
                guard let source = sources.last(where: {
                    $0.lineIndex < projectionLine.lineIndex
                        && representsSameWindow(
                            $0.evidence,
                            projection
                        )
                }) else {
                    continue
                }
                return SpaceFixtureMinimizedAXPropagationEvidence(
                    source: source.evidence,
                    projection: projection
                )
            }
        }
        return nil
    }

    func diagnosticSummary(
        for snapshot: SpaceFixtureMinimizedAXPropagationSnapshot
    ) -> String {
        let pid = processIdentifier.map(String.init) ?? "unbound"
        let matchingSources = processIdentifier.map { expectedPID in
            snapshot.sourceRecords.filter {
                matches(
                    $0.evidence,
                    processIdentifier: expectedPID
                )
            }
        } ?? []
        let resolution = matchingEvidence(in: snapshot)
        let triggerBoundary = triggerProjectionLineCounts == nil
            ? "unarmed"
            : "armed"
        return "expectedApp=\(appName) expectedPID=\(pid) "
            + "expectedTitle=\(expectedWindowTitle) "
            + "triggerBoundary=\(triggerBoundary) "
            + "triggerCompleted=\(triggerCompleted ? 1 : 0) "
            + "missingSourceEvidence=\(matchingSources.isEmpty ? 1 : 0) "
            + "missingPostTriggerProjection=\(resolution == nil ? 1 : 0) "
            + "observed{\(snapshot.diagnosticSummary)}"
    }

    private func matches(
        _ evidence: SpaceFixtureMinimizedAXSourceEvidence,
        processIdentifier: pid_t
    ) -> Bool {
        evidence.appName == appName
            && evidence.processIdentifier == processIdentifier
            && evidence.title == expectedWindowTitle
    }

    private func matches(
        _ evidence: SpaceFixtureMinimizedAXProjectionEvidence,
        processIdentifier: pid_t
    ) -> Bool {
        evidence.appName == appName
            && evidence.processIdentifier == processIdentifier
            && evidence.title == expectedWindowTitle
    }

    private func representsSameWindow(
        _ source: SpaceFixtureMinimizedAXSourceEvidence,
        _ projection: SpaceFixtureMinimizedAXProjectionEvidence
    ) -> Bool {
        source.appName == projection.appName
            && source.processIdentifier
                == projection.processIdentifier
            && source.axWindowID == projection.axWindowID
            && source.cgWindowID == projection.cgWindowID
            && source.title == projection.title
    }
}

final class SpaceFixtureMinimizedAXPropagationObservationOwner {
    private let expectation:
        SpaceFixtureMinimizedAXPropagationExpectation
    private let readback: () -> FlowTabUITestRuntimeLogSnapshot
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            SpaceFixtureMinimizedAXPropagationSnapshot
        >

    convenience init(
        appName: String,
        expectedWindowTitle: String,
        baseline: FlowTabUITestRuntimeLogObservationBaseline
    ) {
        self.init(
            appName: appName,
            expectedWindowTitle: expectedWindowTitle,
            observationRegistration:
                baseline.observationRegistration(),
            readback: baseline.makeReadback
        )
    }

    init(
        appName: String,
        expectedWindowTitle: String,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestRuntimeLogSnapshot
    ) {
        let expectation =
            SpaceFixtureMinimizedAXPropagationExpectation(
                appName: appName,
                expectedWindowTitle: expectedWindowTitle
            )
        self.expectation = expectation
        self.readback = readback
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: {
                SpaceFixtureMinimizedAXPropagationSnapshot(
                    runtimeLogSnapshot: readback()
                )
            },
            isSatisfied: {
                expectation.matchingEvidence(in: $0) != nil
            },
            describe: {
                expectation.diagnosticSummary(for: $0)
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

    func performPreviewTrigger(_ trigger: () -> Void) {
        expectation.beginTrigger(
            from: SpaceFixtureMinimizedAXPropagationSnapshot(
                runtimeLogSnapshot: readback()
            )
        )
        trigger()
        expectation.completeTrigger()
        conditionOwner.requestReadback(source: .triggerReadback)
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        SpaceFixtureMinimizedAXPropagationEvidence
    >? {
        guard let snapshotEvidence =
                conditionOwner.waitForResolution(timeout: timeout),
              let evidence = expectation.matchingEvidence(
                  in: snapshotEvidence.value
              )
        else {
            return nil
        }
        return FlowTabUITestConditionEvidence(
            generation: snapshotEvidence.generation,
            source: snapshotEvidence.source,
            value: evidence
        )
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        SpaceFixtureMinimizedAXPropagationEvidence
    >? {
        guard let snapshotEvidence = conditionOwner.resolvedEvidence,
              let evidence = expectation.matchingEvidence(
                  in: snapshotEvidence.value
              )
        else {
            return nil
        }
        return FlowTabUITestConditionEvidence(
            generation: snapshotEvidence.generation,
            source: snapshotEvidence.source,
            value: evidence
        )
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }

    deinit {
        cancel()
    }
}

private enum SpaceFixtureMinimizedAXPropagationParser {
    private struct LogIdentity {
        let appName: String
        let processIdentifier: pid_t
    }

    static func sourceRecords(
        in line: String
    ) -> [SpaceFixtureMinimizedAXSourceEvidence] {
        guard let identity = logIdentity(
            in: line,
            marker: "chrome-topology"
        ),
        let axList = contents(
            in: line,
            after: " ax=[",
            before: "] cg=["
        ),
        let cgList = trailingContents(
            in: line,
            after: "] cg=[",
            before: "]"
        )
        else {
            return []
        }
        return axList.components(separatedBy: ",ax:")
            .enumerated()
            .compactMap { index, rawSegment in
                let segment = index == 0
                    ? rawSegment
                    : "ax:" + rawSegment
                return sourceRecord(
                    in: segment,
                    cgList: cgList,
                    identity: identity
                )
            }
    }

    static func projectionRecords(
        in line: String
    ) -> [SpaceFixtureMinimizedAXProjectionEvidence] {
        guard let identity = logIdentity(
            in: line,
            marker: "window-entries"
        ),
        let detail = trailingContents(
            in: line,
            after: " detail=[",
            before: "]"
        )
        else {
            return []
        }
        return entrySegments(in: detail).compactMap {
            projectionRecord(in: $0, identity: identity)
        }
    }

    private static func sourceRecord(
        in segment: String,
        cgList: String,
        identity: LogIdentity
    ) -> SpaceFixtureMinimizedAXSourceEvidence? {
        guard segment.contains(":min=1:"),
              let axWindowID = axWindowID(in: segment),
              processIdentifier(in: axWindowID)
                == identity.processIdentifier,
              let title = contents(
                  in: segment,
                  after: axWindowID + ":",
                  before: ":frame="
              ),
              let cgText = contents(
                  in: segment,
                  after: ":bridgeCG=",
                  before: ":"
              ),
              let cgWindowID = UInt32(cgText),
              cgWindowID > 0,
              containsOffscreenCGWindow(
                  cgWindowID,
                  title: title,
                  in: cgList
              )
        else {
            return nil
        }
        return SpaceFixtureMinimizedAXSourceEvidence(
            appName: identity.appName,
            processIdentifier: identity.processIdentifier,
            axWindowID: axWindowID,
            cgWindowID: cgWindowID,
            title: title
        )
    }

    private static func projectionRecord(
        in entry: String,
        identity: LogIdentity
    ) -> SpaceFixtureMinimizedAXProjectionEvidence? {
        guard entry.contains(":ax=1:"),
              entry.contains(":off:minimized=1:"),
              let windowID = contents(
                  in: entry,
                  after: ":id=",
                  before: ":title="
              ),
              let title = contents(
                  in: entry,
                  after: ":title=",
                  before: ":mode="
              ),
              let handle = contents(
                  in: entry,
                  after: ":handle=",
                  before: ":ax="
              ),
              let cgText = contents(
                  in: entry,
                  after: ":cg=",
                  before: ":"
              ),
              let cgWindowID = UInt32(cgText),
              windowID == "cg:\(identity.processIdentifier):\(cgWindowID)",
              processIdentifier(in: handle)
                == identity.processIdentifier
        else {
            return nil
        }
        return SpaceFixtureMinimizedAXProjectionEvidence(
            appName: identity.appName,
            processIdentifier: identity.processIdentifier,
            axWindowID: handle,
            cgWindowID: cgWindowID,
            title: title
        )
    }

    private static func logIdentity(
        in line: String,
        marker: String
    ) -> LogIdentity? {
        guard let markerRange = line.range(of: marker + " app="),
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

    private static func axWindowID(
        in segment: String
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

    private static func containsOffscreenCGWindow(
        _ cgWindowID: UInt32,
        title: String,
        in cgList: String
    ) -> Bool {
        let marker = "\(cgWindowID):\(title):off:spaces=["
        var searchStart = cgList.startIndex
        while let range = cgList.range(
            of: marker,
            range: searchStart..<cgList.endIndex
        ) {
            let hasEntryBoundary = range.lowerBound == cgList.startIndex
                || cgList[cgList.index(before: range.lowerBound)] == ","
            if hasEntryBoundary,
               cgList[range.upperBound...].contains("]:frame=")
            {
                return true
            }
            searchStart = range.upperBound
        }
        return false
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
            range: NSRange(location: 0, length: nsDetail.length)
        ) ?? []
        return matches.enumerated().map { index, match in
            let startsWithComma = nsDetail.substring(
                with: NSRange(location: match.range.location, length: 1)
            ) == ","
            let start = match.range.location
                + (startsWithComma ? 1 : 0)
            let end = index + 1 < matches.count
                ? matches[index + 1].range.location
                : nsDetail.length
            return nsDetail.substring(
                with: NSRange(location: start, length: end - start)
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
