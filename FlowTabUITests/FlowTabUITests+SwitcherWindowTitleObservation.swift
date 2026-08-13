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

struct FlowTabUITestSwitcherWindowTitleCountReadback {
    let cardCount: () -> Int
    let titleCount: (String) -> Int

    func snapshot(
        observing titles: Set<String>
    ) -> FlowTabUITestSwitcherWindowTitleSnapshot {
        let observedCardCount = cardCount()
        var titleCounts: [String: Int] = [:]
        for title in titles.sorted() {
            let count = titleCount(title)
            if count > 0 {
                titleCounts[title] = count
            }
        }
        return FlowTabUITestSwitcherWindowTitleSnapshot(
            cardCount: observedCardCount,
            titleCounts: titleCounts
        )
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
        let observedTitles = Set(expectedTitles)
        let owner =
            FlowTabUITestSwitcherWindowTitleObservationOwner(
                expectation: expectation,
                readback: {
                    let cardQuery = app.descendants(matching: .any)
                        .matching(
                            NSPredicate(
                                format: "identifier BEGINSWITH %@",
                                "flowtab.switcher.window."
                            )
                        )
                    return FlowTabUITestSwitcherWindowTitleCountReadback(
                        cardCount: { cardQuery.count },
                        titleCount: { title in
                            cardQuery.matching(
                                NSPredicate(
                                    format: "label == %@",
                                    title
                                )
                            ).count
                        }
                    ).snapshot(
                        observing: observedTitles
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
