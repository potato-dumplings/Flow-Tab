import Foundation
import XCTest

enum FlowTabUITestLogsProjectionPolicy {
    static let seededRowIdentifierPrefix =
        "flowtab.logs.line.seeded."
    static let tabNavigationWatchdog: TimeInterval = 5
    static let exactProjectionWatchdog: TimeInterval = 8
}

struct FlowTabUITestLogsProjectionSnapshot: Equatable {
    let tabContentExists: Bool
    let linesContainerExists: Bool
    let rowIdentifiers: [String]
    let selectedLevel: String?

    init(
        tabContentExists: Bool,
        linesContainerExists: Bool,
        rowIdentifiers: [String],
        selectedLevel: String? = nil
    ) {
        self.tabContentExists = tabContentExists
        self.linesContainerExists = linesContainerExists
        self.rowIdentifiers = rowIdentifiers
        self.selectedLevel = selectedLevel
    }

    var identifierCounts: [String: Int] {
        rowIdentifiers.reduce(into: [:]) {
            counts,
            identifier in
            counts[identifier, default: 0] += 1
        }
    }

    var diagnosticSummary: String {
        "tabContentExists=\(tabContentExists) "
            + "linesContainerExists=\(linesContainerExists) "
            + "selectedLevel=\(selectedLevel ?? "nil") "
            + "rowCount=\(rowIdentifiers.count) "
            + "identifierCounts="
            + "\(logsIdentifierCountSummary(identifierCounts))"
    }
}

struct FlowTabUITestLogsProjectionExpectation: Equatable {
    let rowCount: Int
    let identifierCounts: [String: Int]
    let prohibitedIdentifiers: Set<String>
    let selectedLevel: String?

    init(
        visibleIdentifiers: [String],
        hiddenIdentifiers: [String],
        selectedLevel: String? = nil
    ) {
        rowCount = visibleIdentifiers.count
        identifierCounts = visibleIdentifiers.reduce(into: [:]) {
            counts,
            identifier in
            counts[identifier, default: 0] += 1
        }
        prohibitedIdentifiers = Set(hiddenIdentifiers)
        self.selectedLevel = selectedLevel
    }

    func isSatisfied(
        by snapshot: FlowTabUITestLogsProjectionSnapshot
    ) -> Bool {
        snapshot.tabContentExists
            && snapshot.linesContainerExists
            && snapshot.rowIdentifiers.count == rowCount
            && snapshot.identifierCounts == identifierCounts
            && Set(snapshot.identifierCounts.keys)
                .isDisjoint(with: prohibitedIdentifiers)
            && (selectedLevel == nil
                || snapshot.selectedLevel == selectedLevel)
    }

    var diagnosticSummary: String {
        "rowCount=\(rowCount) "
            + "identifierCounts="
            + "\(logsIdentifierCountSummary(identifierCounts)) "
            + "prohibitedIdentifiers="
            + "\(prohibitedIdentifiers.sorted()) "
            + "selectedLevel=\(selectedLevel ?? "any")"
    }
}

struct FlowTabUITestSeededLogProjectionExpectation: Equatable {
    let identifier: String
    let cleartextMarker: String
}

struct FlowTabUITestSeededLogProjectionRowSnapshot: Equatable {
    let identifier: String
    let content: String

    var hasStructuredMessageMetadata: Bool {
        content.contains("message.type=structured")
    }

    var fingerprint: String? {
        guard let markerRange = content.range(of: "message.fingerprint=") else {
            return nil
        }
        let suffix = content[markerRange.upperBound...]
        let fingerprint = suffix.prefix {
            !$0.isWhitespace
        }
        guard !fingerprint.isEmpty else { return nil }
        return String(fingerprint)
    }

    var diagnosticSummary: String {
        "identifier=\(identifier) "
            + "contentLength=\(content.count) "
            + "hasStructuredMessageMetadata="
            + "\(hasStructuredMessageMetadata) "
            + "fingerprint=\(fingerprint ?? "nil")"
    }
}

struct FlowTabUITestSeededLogsProjectionSnapshot: Equatable {
    let applicationState: XCUIApplication.State
    let logsContentExists: Bool
    let privacyNoticeExists: Bool
    let linesContainerExists: Bool
    let emptyHintExists: Bool
    let selectedLevel: String?
    let rows: [FlowTabUITestSeededLogProjectionRowSnapshot]

    var identifierCounts: [String: Int] {
        rows.reduce(into: [:]) { counts, row in
            counts[row.identifier, default: 0] += 1
        }
    }

    var diagnosticSummary: String {
        let rowSummary = rows
            .map(\.diagnosticSummary)
            .joined(separator: ";")
        return "applicationState="
            + "\(String(describing: applicationState)) "
            + "logsContentExists=\(logsContentExists) "
            + "privacyNoticeExists=\(privacyNoticeExists) "
            + "linesContainerExists=\(linesContainerExists) "
            + "emptyHintExists=\(emptyHintExists) "
            + "selectedLevel=\(selectedLevel ?? "nil") "
            + "identifierCounts="
            + "\(logsIdentifierCountSummary(identifierCounts)) "
            + "rows=[\(rowSummary)]"
    }
}

struct FlowTabUITestSeededLogsProjectionExpectation: Equatable {
    let selectedLevel: String
    let rows: [FlowTabUITestSeededLogProjectionExpectation]

    var identifierCounts: [String: Int] {
        rows.reduce(into: [:]) { counts, row in
            counts[row.identifier, default: 0] += 1
        }
    }

    func fingerprints(
        in snapshot: FlowTabUITestSeededLogsProjectionSnapshot
    ) -> [String]? {
        guard
            snapshot.applicationState == .runningForeground,
            snapshot.logsContentExists,
            snapshot.privacyNoticeExists,
            snapshot.linesContainerExists,
            !snapshot.emptyHintExists,
            snapshot.selectedLevel == selectedLevel,
            snapshot.rows.count == rows.count,
            snapshot.identifierCounts == identifierCounts
        else {
            return nil
        }

        let snapshotsByIdentifier = Dictionary(
            grouping: snapshot.rows, by: \.identifier
        )
        var fingerprints: [String] = []
        for expectedRow in rows {
            guard
                let matchingRows =
                    snapshotsByIdentifier[expectedRow.identifier],
                matchingRows.count == 1,
                let matchingRow = matchingRows.first,
                !matchingRow.content.contains(
                    expectedRow.cleartextMarker
                ),
                matchingRow.hasStructuredMessageMetadata,
                let fingerprint = matchingRow.fingerprint
            else {
                return nil
            }
            fingerprints.append(fingerprint)
        }
        return fingerprints
    }

    func isSatisfied(
        by snapshot: FlowTabUITestSeededLogsProjectionSnapshot
    ) -> Bool {
        fingerprints(in: snapshot) != nil
    }

    var diagnosticSummary: String {
        "selectedLevel=\(selectedLevel) "
            + "identifierCounts="
            + "\(logsIdentifierCountSummary(identifierCounts)) "
            + "requiresRedactedStructuredFingerprint=true"
    }
}

private func logsIdentifierCountSummary(
    _ counts: [String: Int]
) -> String {
    counts.keys.sorted().map { identifier in
        "\(identifier)=\(counts[identifier, default: 0])"
    }
    .joined(separator: ",")
}

final class FlowTabUITestLogsProjectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestLogsProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestLogsProjectionExpectation,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        acceptsResolution: @escaping () -> Bool = {
            true
        },
        readback: @escaping () ->
            FlowTabUITestLogsProjectionSnapshot
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
                    + "expected{\(expectation.diagnosticSummary)} "
                    + "observed{\(snapshot.diagnosticSummary)}"
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestLogsProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestLogsProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestLogsProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
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

final class FlowTabUITestSeededLogsProjectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSeededLogsProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestSeededLogsProjectionExpectation,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        acceptsResolution: @escaping () -> Bool = { true },
        readback: @escaping () ->
            FlowTabUITestSeededLogsProjectionSnapshot
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
                    + "expected{\(expectation.diagnosticSummary)} "
                    + "observed{\(snapshot.diagnosticSummary)}"
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestSeededLogsProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSeededLogsProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSeededLogsProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
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

private struct FlowTabUITestSeededLogsProjectionElements {
    let logsContent: XCUIElement
    let privacyNotice: XCUIElement
    let linesContainer: XCUIElement
    let emptyHint: XCUIElement
    let logsLevel: XCUIElement
    let seededRows: XCUIElementQuery
}

extension FlowTabUITests {
    func assertSeededLogsProjection(
        in app: XCUIApplication,
        targetDescription: String,
        selectedLevel: String,
        expectedRows:
            [FlowTabUITestSeededLogProjectionExpectation],
        trigger: () -> Bool
    ) -> [String]? {
        let expectation =
            FlowTabUITestSeededLogsProjectionExpectation(
                selectedLevel: selectedLevel,
                rows: expectedRows
            )
        let elements = seededLogsProjectionElements(in: app)
        let readback = seededLogsProjectionReadback(
            in: app,
            elements: elements
        )
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration:
                    FlowTabUITestConditionReadbackScheduler
                        .mainRunLoopRegistration(
                            cadence:
                                FlowTabUITestConditionObservationPolicy
                                    .xcuiReadbackCadence
                        )
            )
        var triggerDidComplete = false
        let owner =
            FlowTabUITestSeededLogsProjectionObservationOwner(
                expectation: expectation,
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                acceptsResolution: { triggerDidComplete },
                readback: readback
            )
        owner.start()
        defer {
            owner.cancel()
            deferredReadbacks.cancel()
        }

        guard owner.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "Seeded Logs initial readback was unavailable. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return nil
        }
        XCTAssertNil(owner.resolvedEvidence)

        let triggerSucceeded = trigger()
        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        if owner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }
        guard triggerSucceeded else {
            XCTFail(
                "Seeded Logs navigation trigger failed. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return nil
        }

        guard
            let evidence = owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsProjectionPolicy
                        .exactProjectionWatchdog
            ),
            let fingerprints = expectation.fingerprints(
                in: evidence.value
            )
        else {
            XCTFail(
                "Seeded Logs projection watchdog expired. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return nil
        }
        return fingerprints
    }

    private func seededLogsProjectionElements(
        in app: XCUIApplication
    ) -> FlowTabUITestSeededLogsProjectionElements {
        FlowTabUITestSeededLogsProjectionElements(
            logsContent: element(
                in: app,
                identifier: Identifier.logsTabContent
            ),
            privacyNotice: element(
                in: app,
                identifier: Identifier.logsPrivacyNotice
            ),
            linesContainer: element(
                in: app,
                identifier: Identifier.logsLines
            ),
            emptyHint: element(
                in: app,
                identifier: Identifier.logsEmptyHint
            ),
            logsLevel: element(
                in: app,
                identifier: Identifier.logsLevel
            ),
            seededRows: app.descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "identifier BEGINSWITH %@",
                        FlowTabUITestLogsProjectionPolicy
                            .seededRowIdentifierPrefix
                    )
                )
        )
    }

    private func seededLogsProjectionReadback(
        in app: XCUIApplication,
        elements: FlowTabUITestSeededLogsProjectionElements
    ) -> () -> FlowTabUITestSeededLogsProjectionSnapshot {
        {
            let applicationState = app.state
            guard applicationState == .runningForeground else {
                return FlowTabUITestSeededLogsProjectionSnapshot(
                    applicationState: applicationState,
                    logsContentExists: false,
                    privacyNoticeExists: false,
                    linesContainerExists: false,
                    emptyHintExists: false,
                    selectedLevel: nil,
                    rows: []
                )
            }
            let logsLevelExists = elements.logsLevel.exists
            let rowSnapshots = elements.seededRows
                .allElementsBoundByIndex
                .map { row in
                    FlowTabUITestSeededLogProjectionRowSnapshot(
                        identifier: row.identifier,
                        content: (row.value as? String) ?? row.label
                    )
                }
            return FlowTabUITestSeededLogsProjectionSnapshot(
                applicationState: applicationState,
                logsContentExists: elements.logsContent.exists,
                privacyNoticeExists: elements.privacyNotice.exists,
                linesContainerExists: elements.linesContainer.exists,
                emptyHintExists: elements.emptyHint.exists,
                selectedLevel: logsLevelExists
                    ? self.elementStringValue(elements.logsLevel)
                    : nil,
                rows: rowSnapshots
            )
        }
    }

    func assertLogVisibility(
        at logLevel: String,
        visibleIdentifiers: [String],
        hiddenIdentifiers: [String]
    ) {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-seed-logs",
                "4",
                "--flowtab-ui-runtime-log-level",
                logLevel,
                "-showPermissionReminder",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(app)
        defer {
            if app.state == .runningForeground
                || app.state == .runningBackground
            {
                app.terminate()
            }
        }

        let expectation =
            FlowTabUITestLogsProjectionExpectation(
                visibleIdentifiers: visibleIdentifiers,
                hiddenIdentifiers: hiddenIdentifiers
            )
        let logsTabContent = element(
            in: app,
            identifier: Identifier.logsTabContent
        )
        let logsLines = element(
            in: app,
            identifier: Identifier.logsLines
        )
        let seededRows = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    FlowTabUITestLogsProjectionPolicy
                        .seededRowIdentifierPrefix
                )
            )
        var triggerDidComplete = false
        let owner =
            FlowTabUITestLogsProjectionObservationOwner(
                expectation: expectation,
                acceptsResolution: {
                    triggerDidComplete
                },
                readback: {
                    let identifiers = seededRows
                        .allElementsBoundByIndex
                        .map(\.identifier)
                    return FlowTabUITestLogsProjectionSnapshot(
                        tabContentExists:
                            logsTabContent.exists,
                        linesContainerExists:
                            logsLines.exists,
                        rowIdentifiers: identifiers
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        let didOpenLogs = tapFirstHittable(
            in: app.buttons.matching(
                identifier: Identifier.logsTabButton
            ),
            timeout:
                FlowTabUITestLogsProjectionPolicy
                    .tabNavigationWatchdog
        )
        triggerDidComplete = true
        guard didOpenLogs else {
            XCTFail(
                "Failed to open logs tab at level \(logLevel)"
            )
            return
        }

        guard
            owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsProjectionPolicy
                        .exactProjectionWatchdog
            ) != nil
        else {
            XCTFail(
                "Logs projection watchdog expired at level "
                    + "\(logLevel). \(owner.diagnosticSummary)"
            )
            return
        }
    }

    func assertLogVisibilityTransition(
        in app: XCUIApplication,
        targetDescription: String,
        initialSelectedLevel: String,
        initialVisibleIdentifiers: [String],
        selectedLevel: String,
        visibleIdentifiers: [String],
        hiddenIdentifiers: [String],
        trigger: () -> Void
    ) {
        let initialExpectation =
            FlowTabUITestLogsProjectionExpectation(
                visibleIdentifiers: initialVisibleIdentifiers,
                hiddenIdentifiers: [],
                selectedLevel: initialSelectedLevel
            )
        let targetExpectation =
            FlowTabUITestLogsProjectionExpectation(
                visibleIdentifiers: visibleIdentifiers,
                hiddenIdentifiers: hiddenIdentifiers,
                selectedLevel: selectedLevel
            )
        let logsTabContent = element(
            in: app,
            identifier: Identifier.logsTabContent
        )
        let logsLines = element(
            in: app,
            identifier: Identifier.logsLines
        )
        let logsLevel = element(
            in: app,
            identifier: Identifier.logsLevel
        )
        let seededRows = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    FlowTabUITestLogsProjectionPolicy
                        .seededRowIdentifierPrefix
                )
            )
        let readback: () ->
            FlowTabUITestLogsProjectionSnapshot = {
                let levelExists = logsLevel.exists
                return FlowTabUITestLogsProjectionSnapshot(
                    tabContentExists:
                        logsTabContent.exists,
                    linesContainerExists:
                        logsLines.exists,
                    rowIdentifiers: seededRows
                        .allElementsBoundByIndex
                        .map(\.identifier),
                    selectedLevel: levelExists
                        ? self.elementStringValue(logsLevel)
                        : nil
                )
            }
        let baselineOwner =
            FlowTabUITestLogsProjectionObservationOwner(
                expectation: initialExpectation,
                readback: readback
            )
        baselineOwner.start()
        guard
            baselineOwner.waitForResolution(
                timeout:
                    FlowTabUITestLogsProjectionPolicy
                        .exactProjectionWatchdog
            ) != nil
        else {
            XCTFail(
                "Logs projection baseline watchdog expired. "
                    + "target=\(targetDescription) "
                    + baselineOwner.diagnosticSummary
            )
            baselineOwner.cancel()
            return
        }
        baselineOwner.cancel()

        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration:
                    FlowTabUITestConditionReadbackScheduler
                        .mainRunLoopRegistration(
                            cadence:
                                FlowTabUITestConditionObservationPolicy
                                    .xcuiReadbackCadence
                        )
            )
        var triggerDidComplete = false
        let owner =
            FlowTabUITestLogsProjectionObservationOwner(
                expectation: targetExpectation,
                observationRegistration: {
                    readback in
                    deferredReadbacks.register(readback)
                },
                acceptsResolution: {
                    triggerDidComplete
                },
                readback: readback
            )
        owner.start()
        defer {
            owner.cancel()
            deferredReadbacks.cancel()
        }

        guard let initialEvidence = owner.latestEvidence,
              initialEvidence.source == .initialReadback,
              initialExpectation.isSatisfied(
                by: initialEvidence.value
              )
        else {
            XCTFail(
                "Logs projection initial baseline was incomplete. "
                    + "target=\(targetDescription) "
                    + "expected{\(initialExpectation.diagnosticSummary)} "
                    + owner.diagnosticSummary
            )
            return
        }
        XCTAssertNil(owner.resolvedEvidence)

        trigger()
        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        if owner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }

        XCTAssertNotNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsProjectionPolicy
                        .exactProjectionWatchdog
            ),
            "Logs projection transition watchdog expired. "
                + "target=\(targetDescription) "
                + owner.diagnosticSummary
        )
    }
}
