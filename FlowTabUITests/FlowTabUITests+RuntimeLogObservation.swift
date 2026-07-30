import Foundation
import XCTest

private enum FlowTabUITestRuntimeLogObservationPolicy {
    static let readbackCadence: TimeInterval = 0.2
    static let maximumDiagnosticCharacterCount = 4_000
}

struct FlowTabUITestRuntimeLogSnapshot: Equatable {
    let baselineFileEventGeneration: UInt64
    let fileEventGeneration: UInt64
    let contents: String

    var diagnosticSummary: String {
        let tail = String(
            contents.suffix(
                FlowTabUITestRuntimeLogObservationPolicy
                    .maximumDiagnosticCharacterCount
            )
        )
        return "baselineFileEventGeneration="
            + "\(baselineFileEventGeneration) "
            + "fileEventGeneration=\(fileEventGeneration) "
            + "characterCount=\(contents.count) "
            + "tail=\(tail)"
    }
}

enum FlowTabUITestRuntimeLogExpectation {
    case allMarkers([String])
    case regularExpression(
        NSRegularExpression,
        pattern: String,
        description: String
    )

    func isSatisfied(
        by snapshot: FlowTabUITestRuntimeLogSnapshot
    ) -> Bool {
        switch self {
        case .allMarkers(let markers):
            return markers.allSatisfy {
                snapshot.contents.contains($0)
            }
        case .regularExpression(let regex, _, _):
            let contents = snapshot.contents
            let range = NSRange(
                contents.startIndex..<contents.endIndex,
                in: contents
            )
            return regex.firstMatch(
                in: contents,
                range: range
            ) != nil
        }
    }

    func diagnosticSummary(
        for snapshot: FlowTabUITestRuntimeLogSnapshot
    ) -> String {
        switch self {
        case .allMarkers(let markers):
            let missing = markers.filter {
                !snapshot.contents.contains($0)
            }
            return "missingMarkers=\(missing)"
        case .regularExpression(
            _,
            let pattern,
            let description
        ):
            return "missingPattern=\(description) "
                + "pattern=\(pattern)"
        }
    }
}

final class FlowTabUITestRuntimeLogObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestRuntimeLogSnapshot
        >

    init(
        expectation:
            FlowTabUITestRuntimeLogExpectation,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestRuntimeLogSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: expectation.isSatisfied(by:),
            describe: { snapshot in
                expectation.diagnosticSummary(
                    for: snapshot
                )
                    + " observed{\(snapshot.diagnosticSummary)}"
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestRuntimeLogSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestRuntimeLogSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITestRuntimeLogObservationBaseline {
    func observationRegistration()
        -> FlowTabUITestConditionObservationRegistration
    {
        let fileEventRegistration =
            fileEventObservationRegistration()
        let scheduledRegistration =
            FlowTabUITestConditionReadbackScheduler
                .mainRunLoopRegistration(
                    cadence:
                        FlowTabUITestRuntimeLogObservationPolicy
                            .readbackCadence
                )
        return { readback in
            let fileEventCancellation =
                fileEventRegistration(readback)
            let scheduledCancellation =
                scheduledRegistration(readback)
            return FlowTabUITestObservationCancellation {
                fileEventCancellation?.cancel()
                scheduledCancellation?.cancel()
            }
        }
    }

    func makeReadback() -> FlowTabUITestRuntimeLogSnapshot {
        FlowTabUITestRuntimeLogSnapshot(
            baselineFileEventGeneration:
                baselineFileEventGeneration,
            fileEventGeneration: fileEventGeneration,
            contents: readContents()
        )
    }
}

extension FlowTabUITests {
    func makeRuntimeLogFileSnapshot()
        -> FlowTabUITestRuntimeLogObservationBaseline
    {
        FlowTabUITestRuntimeLogObservationBaseline(
            logsDirectoryURL: runtimeLogsDirectoryURL()
        )
    }

    func waitForRuntimeLogFiles(
        containing markers: [String],
        since snapshot:
            FlowTabUITestRuntimeLogObservationBaseline,
        timeout: TimeInterval = 8
    ) {
        waitForRuntimeLogFiles(
            satisfying: .allMarkers(markers),
            since: snapshot,
            timeout: timeout
        )
    }

    func waitForRuntimeLogFiles(
        matching pattern: String,
        since snapshot:
            FlowTabUITestRuntimeLogObservationBaseline,
        timeout: TimeInterval = 8,
        description: String
    ) {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(
                pattern: pattern
            )
        } catch {
            XCTFail(
                "Invalid runtime log regex "
                    + "\(pattern): \(error)"
            )
            return
        }
        waitForRuntimeLogFiles(
            satisfying: .regularExpression(
                regex,
                pattern: pattern,
                description: description
            ),
            since: snapshot,
            timeout: timeout
        )
    }

    func runtimeLogContentsSinceSnapshot(
        _ snapshot:
            FlowTabUITestRuntimeLogObservationBaseline
    ) -> String {
        snapshot.readContents()
    }

    func runtimeLogContents() -> String {
        FlowTabUITestRuntimeLogObservationBaseline
            .readAllContents(
                in: runtimeLogsDirectoryURL()
            )
    }

    private func waitForRuntimeLogFiles(
        satisfying expectation:
            FlowTabUITestRuntimeLogExpectation,
        since snapshot:
            FlowTabUITestRuntimeLogObservationBaseline,
        timeout: TimeInterval
    ) {
        let owner =
            FlowTabUITestRuntimeLogObservationOwner(
                expectation: expectation,
                observationRegistration:
                    snapshot.observationRegistration(),
                readback: snapshot.makeReadback
            )
        owner.start()
        defer { owner.cancel() }

        guard
            owner.waitForResolution(timeout: timeout)
                != nil
        else {
            XCTFail(
                "Runtime log watchdog expired in "
                    + "\(snapshot.logsDirectoryURL.path). "
                    + owner.diagnosticSummary
            )
            return
        }
    }

    private func runtimeLogsDirectoryURL() -> URL {
        let fallbackURL = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        )
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )
        .first ?? fallbackURL
        return baseURL.appendingPathComponent(
            "FlowTab/logs",
            isDirectory: true
        )
    }
}
