import Foundation
import XCTest

struct FlowTabUITestSwitcherWindowTitleSnapshot: Equatable {
    let cardCount: Int
    let titleCounts: [String: Int]

    var diagnosticSummary: String {
        "cardCount=\(cardCount) "
            + "titleCounts=\(titleCountSummary(titleCounts))"
    }
}

struct FlowTabUITestSwitcherWindowTitleExpectation: Equatable {
    let cardCount: Int
    let titleCounts: [String: Int]

    init(titles: [String]) {
        cardCount = titles.count
        titleCounts = titles.reduce(into: [:]) { counts, title in
            counts[title, default: 0] += 1
        }
    }

    func isSatisfied(
        by snapshot: FlowTabUITestSwitcherWindowTitleSnapshot
    ) -> Bool {
        snapshot.cardCount == cardCount
            && snapshot.titleCounts == titleCounts
    }

    var diagnosticSummary: String {
        "cardCount=\(cardCount) "
            + "titleCounts=\(titleCountSummary(titleCounts))"
    }
}

private func titleCountSummary(
    _ counts: [String: Int]
) -> String {
    counts.keys.sorted().map { title in
        "\(title)=\(counts[title, default: 0])"
    }
    .joined(separator: ",")
}

final class FlowTabUITestSwitcherWindowTitleObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSwitcherWindowTitleSnapshot
        >

    init(
        expectation: FlowTabUITestSwitcherWindowTitleExpectation,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestSwitcherWindowTitleSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: expectation.isSatisfied(by:),
            describe: { snapshot in
                "expected{\(expectation.diagnosticSummary)} "
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
        FlowTabUITestSwitcherWindowTitleSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherWindowTitleSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    func waitForSwitcherWindowCards(
        in app: XCUIApplication,
        expectedTitles: [String],
        timeout: TimeInterval
    ) -> Bool {
        let expectation =
            FlowTabUITestSwitcherWindowTitleExpectation(
                titles: expectedTitles
            )
        let cardQuery = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    "flowtab.switcher.window."
                )
            )
        let owner =
            FlowTabUITestSwitcherWindowTitleObservationOwner(
                expectation: expectation,
                readback: {
                    let titles = cardQuery
                        .allElementsBoundByIndex
                        .map(\.label)
                    let titleCounts = titles.reduce(
                        into: [:]
                    ) { counts, title in
                        counts[title, default: 0] += 1
                    }
                    return FlowTabUITestSwitcherWindowTitleSnapshot(
                        cardCount: titles.count,
                        titleCounts: titleCounts
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard
            owner.waitForResolution(timeout: timeout) != nil
        else {
            XCTFail(
                "Switcher window title projection watchdog expired. "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }
}
