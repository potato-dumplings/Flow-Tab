import Foundation
import XCTest

struct FlowTabUITestHomeWindowRowSnapshot<Element> {
    let identifier: String
    let label: String
    let value: String
    let element: Element

    func contains(title: String) -> Bool {
        [label, value].contains { source in
            source.localizedCaseInsensitiveContains(title)
        }
    }

    var diagnosticSummary: String {
        "\(identifier){label=\(label), value=\(value)}"
    }
}

struct FlowTabUITestHomeWindowProjectionSnapshot<Element> {
    let rows: [FlowTabUITestHomeWindowRowSnapshot<Element>]
    let visibleStaticTextTitles: [String]

    func row(
        containing title: String
    ) -> FlowTabUITestHomeWindowRowSnapshot<Element>? {
        rows.first { $0.contains(title: title) }
    }

    func contains(title: String) -> Bool {
        visibleStaticTextTitles.contains(title)
            || row(containing: title) != nil
    }

    func unexpectedTitles(from titles: [String]) -> [String] {
        titles.filter(contains(title:))
    }

    var diagnosticSummary: String {
        let rowSummary = rows
            .map(\.diagnosticSummary)
            .joined(separator: ", ")
        return "visibleStaticTexts="
            + "\(visibleStaticTextTitles.sorted()) "
            + "rows=[\(rowSummary)]"
    }
}

enum FlowTabUITestHomeWindowProjectionExpectation: Equatable {
    case rowContaining(String)
    case rowLabelPrefix([String])
    case titleVisible(String)
    case titlesVisible([String])
    case titlesAbsent([String])

    func isSatisfied<Element>(
        by snapshot: FlowTabUITestHomeWindowProjectionSnapshot<Element>
    ) -> Bool {
        switch self {
        case .rowContaining(let title):
            return snapshot.row(containing: title) != nil
        case .rowLabelPrefix(let titles):
            return !titles.isEmpty
                && Array(snapshot.rows.prefix(titles.count).map(\.label))
                    == titles
        case .titleVisible(let title):
            return snapshot.contains(title: title)
        case .titlesVisible(let titles):
            return !titles.isEmpty
                && titles.allSatisfy(snapshot.contains(title:))
        case .titlesAbsent(let titles):
            return snapshot.unexpectedTitles(from: titles).isEmpty
        }
    }

    var titles: [String] {
        switch self {
        case .rowContaining(let title),
             .titleVisible(let title):
            return [title]
        case .rowLabelPrefix:
            return []
        case .titlesVisible(let titles):
            return titles
        case .titlesAbsent(let titles):
            return titles
        }
    }

    var diagnosticSummary: String {
        switch self {
        case .rowContaining(let title):
            return "rowContaining=\(title)"
        case .rowLabelPrefix(let titles):
            return "rowLabelPrefix=\(titles)"
        case .titleVisible(let title):
            return "titleVisible=\(title)"
        case .titlesVisible(let titles):
            return "titlesVisible=\(titles)"
        case .titlesAbsent(let titles):
            return "titlesAbsent=\(titles)"
        }
    }
}

final class FlowTabUITestHomeWindowProjectionObservationOwner<Element> {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestHomeWindowProjectionSnapshot<Element>
        >

    init(
        expectation: FlowTabUITestHomeWindowProjectionExpectation,
        acceptsEvidence: @escaping () -> Bool = { true },
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestHomeWindowProjectionSnapshot<Element>
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                acceptsEvidence()
                    && expectation.isSatisfied(by: $0)
            },
            describe: { snapshot in
                "acceptanceEnabled=\(acceptsEvidence()) "
                    + "expected{\(expectation.diagnosticSummary)} "
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestHomeWindowProjectionSnapshot<Element>
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestHomeWindowProjectionSnapshot<Element>
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestHomeWindowProjectionSnapshot<Element>
    >? {
        conditionOwner.latestEvidence
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

extension FlowTabUITests {
    func homeWindowRows(in app: XCUIApplication) -> [XCUIElement] {
        let prefix = "flowtab.home.window."
        let predicate = NSPredicate(
            format: "identifier BEGINSWITH %@",
            prefix
        )
        let buttonRows = app.buttons
            .matching(predicate)
            .allElementsBoundByIndex
        if !buttonRows.isEmpty {
            return buttonRows
        }

        return app.descendants(matching: .any)
            .matching(predicate)
            .allElementsBoundByIndex
    }

    func waitForHomeWindowRow(
        in app: XCUIApplication,
        title: String,
        timeout: TimeInterval
    ) -> XCUIElement? {
        let expectation =
            FlowTabUITestHomeWindowProjectionExpectation
                .rowContaining(title)
        let resolution = observeHomeWindowProjection(
            in: app,
            expectation: expectation,
            timeout: timeout
        )
        guard
            let row = resolution.evidence?.value.row(
                containing: title
            )
        else {
            XCTFail(
                "Expected a Home window row containing \(title). "
                    + resolution.diagnosticSummary
            )
            return nil
        }
        return row.element
    }

    func performAndWaitForHomeWindowRow(
        in app: XCUIApplication,
        title: String,
        timeout: TimeInterval,
        trigger: () -> Void
    ) -> XCUIElement? {
        var triggerCompleted = false
        let expectation =
            FlowTabUITestHomeWindowProjectionExpectation
                .rowContaining(title)
        let owner =
            FlowTabUITestHomeWindowProjectionObservationOwner(
                expectation: expectation,
                acceptsEvidence: {
                    triggerCompleted
                },
                readback: {
                    self.homeWindowProjectionSnapshot(
                        in: app,
                        expectation: expectation
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        trigger()
        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        guard
            let row = owner.waitForResolution(
                timeout: timeout
            )?.value.row(containing: title)
        else {
            XCTFail(
                "Expected a post-trigger Home window row "
                    + "containing \(title). "
                    + owner.diagnosticSummary
            )
            return nil
        }
        return row.element
    }

    func waitForHomeWindowTitle(
        _ title: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let resolution = observeHomeWindowProjection(
            in: app,
            expectation: .titleVisible(title),
            timeout: timeout
        )
        if resolution.evidence == nil {
            logFlowTabUITestTrace(
                "Home title watchdog expired for \(title). "
                    + resolution.diagnosticSummary
            )
        }
        return resolution.evidence != nil
    }

    func assertHomeWindowTitle(
        _ title: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 12,
        message: String? = nil
    ) {
        let resolution = observeHomeWindowProjection(
            in: app,
            expectation: .titleVisible(title),
            timeout: timeout
        )
        guard resolution.evidence != nil else {
            XCTFail(
                (message ?? "Missing Home window title: \(title)")
                    + ". \(resolution.diagnosticSummary)"
            )
            return
        }
    }

    func assertHomeWindowTitlesAbsent(
        _ titles: [String],
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) {
        let resolution = observeHomeWindowProjection(
            in: app,
            expectation: .titlesAbsent(titles),
            timeout: timeout
        )
        guard resolution.evidence != nil else {
            XCTFail(
                "Unexpected visible Home window titles. "
                    + resolution.diagnosticSummary
            )
            return
        }
    }

    func performAndWaitForHomeWindowTitlePrefix(
        _ expectedTitles: [String],
        in app: XCUIApplication,
        timeout: TimeInterval,
        trigger: () -> Void
    ) -> Bool {
        var triggerCompleted = false
        let expectation =
            FlowTabUITestHomeWindowProjectionExpectation
                .rowLabelPrefix(expectedTitles)
        let owner =
            FlowTabUITestHomeWindowProjectionObservationOwner(
                expectation: expectation,
                acceptsEvidence: {
                    triggerCompleted
                },
                readback: {
                    self.homeWindowProjectionSnapshot(
                        in: app,
                        expectation: expectation
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        trigger()
        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        guard
            owner.waitForResolution(timeout: timeout) != nil
        else {
            XCTFail(
                "Home window title prefix did not satisfy "
                    + "\(expectedTitles). "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    private func observeHomeWindowProjection(
        in app: XCUIApplication,
        expectation: FlowTabUITestHomeWindowProjectionExpectation,
        timeout: TimeInterval
    ) -> (
        evidence: FlowTabUITestConditionEvidence<
            FlowTabUITestHomeWindowProjectionSnapshot<XCUIElement>
        >?,
        diagnosticSummary: String
    ) {
        let owner =
            FlowTabUITestHomeWindowProjectionObservationOwner(
                expectation: expectation,
                readback: {
                    self.homeWindowProjectionSnapshot(
                        in: app,
                        expectation: expectation
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }
        let evidence = owner.waitForResolution(timeout: timeout)
        return (evidence, owner.diagnosticSummary)
    }

    func homeWindowProjectionSnapshot(
        in app: XCUIApplication,
        expectation: FlowTabUITestHomeWindowProjectionExpectation
    ) -> FlowTabUITestHomeWindowProjectionSnapshot<XCUIElement> {
        let visibleStaticTextTitles =
            expectation.titles.filter { title in
                app.staticTexts[title].exists
            }
        if case .titleVisible = expectation,
           !visibleStaticTextTitles.isEmpty
        {
            return FlowTabUITestHomeWindowProjectionSnapshot(
                rows: [],
                visibleStaticTextTitles: visibleStaticTextTitles
            )
        }

        let rows = homeWindowRows(in: app).map { element in
            FlowTabUITestHomeWindowRowSnapshot(
                identifier: element.identifier,
                label: element.label,
                value: elementStringValue(element),
                element: element
            )
        }
        return FlowTabUITestHomeWindowProjectionSnapshot(
            rows: rows,
            visibleStaticTextTitles: visibleStaticTextTitles
        )
    }
}
