import CoreGraphics
import Darwin
import Foundation
import XCTest

enum FlowTabUITestRuntimeLogObservationPolicy {
    static let defaultWatchdog: TimeInterval = 8
    static let quitShortcutTerminationRequestWatchdog: TimeInterval = 8
    static let openWindowMutationReconciliationWatchdog: TimeInterval = 8
    static let multiAppOpenWindowMutationReconciliationWatchdog: TimeInterval = 8
    static let fullscreenMultiAppWindowMutationReconciliationWatchdog:
        TimeInterval = 8
    static let selectedWindowMutationReconciliationWatchdog: TimeInterval = 8
    static let readbackCadence: TimeInterval = 0.2
    static let maximumDiagnosticCharacterCount = 4_000
}

enum FlowTabUITestRuntimeLogRecordPattern {
    static func exactTerminationRequest(
        bundleIdentifier: String
    ) -> String {
        let escapedBundleIdentifier =
            NSRegularExpression.escapedPattern(
                for: bundleIdentifier
            )
        return #"(?m)terminate request app=[^\r\n]* appID=\#(escapedBundleIdentifier) sent=true\r?$"#
    }

    static func exactRuntimeAXDestroyed(
        bundleIdentifier: String,
        processIdentifier: pid_t,
        affectedCGWindowID: CGWindowID
    ) -> String {
        let escapedBundleIdentifier =
            NSRegularExpression.escapedPattern(
                for: bundleIdentifier
            )
        return "(?m)runtimeAXDestroyed "
            + "appID=\(escapedBundleIdentifier) "
            + "pid=\(processIdentifier) "
            + "axWindowID=ax:\(processIdentifier):[0-9]+ "
            + "affectedCGWindowID=\(affectedCGWindowID)\\r?$"
    }

    static func exactReadyCurrentAppRepair(
        bundleIdentifier: String,
        processIdentifier: pid_t,
        windowCount: Int
    ) -> String {
        let escapedBundleIdentifier =
            NSRegularExpression.escapedPattern(
                for: bundleIdentifier
            )
        return "(?m)focusedCurrentAppRepairEvidence result=ready "
            + "appID=\(escapedBundleIdentifier) "
            + "pid=\(processIdentifier) "
            + "selectedPID=\(processIdentifier) "
            + "windows=\(windowCount)(?: |\\r?$)"
    }
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

extension FlowTabUITestRuntimeLogExpectation {
    static func exactRuntimeAXDestroyed(
        bundleIdentifier: String,
        processIdentifier: pid_t,
        affectedCGWindowID: CGWindowID
    ) throws -> Self {
        let pattern =
            FlowTabUITestRuntimeLogRecordPattern
                .exactRuntimeAXDestroyed(
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: processIdentifier,
                    affectedCGWindowID: affectedCGWindowID
                )
        return .regularExpression(
            try NSRegularExpression(pattern: pattern),
            pattern: pattern,
            description:
                "exact runtime AX-destroyed bundle/PID/CG reconciliation"
        )
    }

    static func exactReadyCurrentAppRepair(
        bundleIdentifier: String,
        processIdentifier: pid_t,
        windowCount: Int
    ) throws -> Self {
        let pattern =
            FlowTabUITestRuntimeLogRecordPattern
                .exactReadyCurrentAppRepair(
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: processIdentifier,
                    windowCount: windowCount
                )
        return .regularExpression(
            try NSRegularExpression(pattern: pattern),
            pattern: pattern,
            description:
                "exact bundle/PID ready current-App repair"
        )
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
        acceptsResolution: @escaping () -> Bool = {
            true
        },
        readback: @escaping () ->
            FlowTabUITestRuntimeLogSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                acceptsResolution()
                    && expectation.isSatisfied(by: $0)
            },
            describe: { snapshot in
                "acceptsResolution=\(acceptsResolution()) "
                    + expectation.diagnosticSummary(
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

    func requestReadback(
        source: FlowTabUITestConditionObservationSource
    ) {
        conditionOwner.requestReadback(source: source)
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

final class FlowTabUITestSwitcherTriggerDeliveryObservationOwner {
    private let receiptOwner:
        FlowTabUITestRuntimeLogObservationOwner
    private let completionOwner:
        FlowTabUITestRuntimeLogObservationOwner

    convenience init(
        notificationName: String,
        baseline:
            FlowTabUITestRuntimeLogObservationBaseline
    ) {
        self.init(
            notificationName: notificationName,
            observationRegistration:
                baseline.observationRegistration(),
            readback: baseline.makeReadback
        )
    }

    init(
        notificationName: String,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestRuntimeLogSnapshot
    ) {
        receiptOwner =
            FlowTabUITestRuntimeLogObservationOwner(
                expectation: .allMarkers([
                    "received switcher trigger notification "
                        + "name=\(notificationName)"
                ]),
                observationRegistration:
                    observationRegistration,
                readback: readback
            )
        completionOwner =
            FlowTabUITestRuntimeLogObservationOwner(
                expectation: .allMarkers([
                    "completed switcher trigger notification "
                        + "name=\(notificationName) "
                        + "presented=1 syntheticModifierHeld=1"
                ]),
                observationRegistration:
                    observationRegistration,
                readback: readback
            )
    }

    func start() {
        receiptOwner.start()
        completionOwner.start()
    }

    func waitForReceipt(timeout: TimeInterval) -> Bool {
        receiptOwner.waitForResolution(timeout: timeout)
            != nil
    }

    func waitForCompletion(timeout: TimeInterval) -> Bool {
        completionOwner.waitForResolution(timeout: timeout)
            != nil
    }

    var receiptResolvedEvidence:
        FlowTabUITestConditionEvidence<
            FlowTabUITestRuntimeLogSnapshot
        >?
    {
        receiptOwner.resolvedEvidence
    }

    var completionResolvedEvidence:
        FlowTabUITestConditionEvidence<
            FlowTabUITestRuntimeLogSnapshot
        >?
    {
        completionOwner.resolvedEvidence
    }

    var receiptDiagnosticSummary: String {
        receiptOwner.diagnosticSummary
    }

    var completionDiagnosticSummary: String {
        completionOwner.diagnosticSummary
    }

    func cancel() {
        receiptOwner.cancel()
        completionOwner.cancel()
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
        timeout: TimeInterval =
            FlowTabUITestRuntimeLogObservationPolicy
                .defaultWatchdog
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
        timeout: TimeInterval =
            FlowTabUITestRuntimeLogObservationPolicy
                .defaultWatchdog,
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
