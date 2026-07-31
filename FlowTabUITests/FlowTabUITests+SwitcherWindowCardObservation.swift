import CoreGraphics
import Foundation
import XCTest

struct SwitcherWindowCardObservation: Equatable {
    let identifier: String
    let title: String
    let value: String
    let frame: CGRect
    let hasImage: Bool

    var diagnosticSummary: String {
        "\(identifier){title=\(title),value=\(value),"
            + "frame=\(frame),hasImage=\(hasImage)}"
    }
}

struct FlowTabUITestSwitcherWindowCardSnapshot: Equatable {
    let cards: [SwitcherWindowCardObservation]

    var identifiers: Set<String> {
        Set(cards.map(\.identifier))
    }

    var titleCounts: [String: Int] {
        cards.reduce(into: [:]) { counts, card in
            counts[card.title, default: 0] += 1
        }
    }

    var diagnosticSummary: String {
        let cardSummary = cards
            .sorted {
                ($0.title, $0.identifier)
                    < ($1.title, $1.identifier)
            }
            .map(\.diagnosticSummary)
            .joined(separator: ",")
        return "cardCount=\(cards.count) "
            + "identifierCount=\(identifiers.count) "
            + "titleCounts=\(switcherCardTitleCountSummary(titleCounts)) "
            + "cards=[\(cardSummary)]"
    }
}

struct FlowTabUITestSwitcherWindowCardExpectation: Equatable {
    let cardCount: Int
    let titleCounts: [String: Int]
    let excludedTitles: Set<String>
    let previousWindowCardIdentifiers: Set<String>

    init(
        expectedTitles: [String],
        excludedTitles: [String],
        previousWindowCardIdentifiers: Set<String>
    ) {
        cardCount = expectedTitles.count
        titleCounts = expectedTitles.reduce(into: [:]) {
            counts,
            title in
            counts[title, default: 0] += 1
        }
        self.excludedTitles = Set(excludedTitles)
        self.previousWindowCardIdentifiers =
            previousWindowCardIdentifiers
    }

    func isSatisfied(
        by snapshot: FlowTabUITestSwitcherWindowCardSnapshot
    ) -> Bool {
        snapshot.cards.count == cardCount
            && snapshot.identifiers.count == cardCount
            && snapshot.titleCounts == titleCounts
            && Set(snapshot.titleCounts.keys)
                .isDisjoint(with: excludedTitles)
            && (
                previousWindowCardIdentifiers.isEmpty
                    || snapshot.identifiers.isDisjoint(
                        with: previousWindowCardIdentifiers
                    )
            )
    }

    var diagnosticSummary: String {
        "cardCount=\(cardCount) "
            + "titleCounts=\(switcherCardTitleCountSummary(titleCounts)) "
            + "excludedTitles=\(excludedTitles.sorted()) "
            + "previousIdentifiers="
            + "\(previousWindowCardIdentifiers.sorted())"
    }
}

private func switcherCardTitleCountSummary(
    _ counts: [String: Int]
) -> String {
    counts.keys.sorted().map { title in
        "\(title)=\(counts[title, default: 0])"
    }
    .joined(separator: ",")
}

final class FlowTabUITestSwitcherWindowCardObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSwitcherWindowCardSnapshot
        >

    init(
        expectation:
            FlowTabUITestSwitcherWindowCardExpectation,
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
            FlowTabUITestSwitcherWindowCardSnapshot
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
        FlowTabUITestSwitcherWindowCardSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    func requestReadback(
        source: FlowTabUITestConditionObservationSource
    ) {
        conditionOwner.requestReadback(source: source)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherWindowCardSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestSnapshot:
        FlowTabUITestSwitcherWindowCardSnapshot? {
        conditionOwner.latestEvidence?.value
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    func performAndWaitForSwitcherWindowCards(
        in app: XCUIApplication,
        expectedTitles: [String],
        excludedTitles: [String] = [],
        previousWindowCardIdentifiers: Set<String> = [],
        timeout: TimeInterval,
        trigger: () -> Void
    ) -> [SwitcherWindowCardObservation] {
        let expectation =
            FlowTabUITestSwitcherWindowCardExpectation(
                expectedTitles: expectedTitles,
                excludedTitles: excludedTitles,
                previousWindowCardIdentifiers:
                    previousWindowCardIdentifiers
            )
        var triggerCompleted = false
        let owner =
            FlowTabUITestSwitcherWindowCardObservationOwner(
                expectation: expectation,
                acceptsResolution: {
                    triggerCompleted
                },
                readback: {
                    FlowTabUITestSwitcherWindowCardSnapshot(
                        cards:
                            self.switcherWindowCardObservations(
                                in: app
                            )
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        trigger()
        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        guard
            let evidence = owner.waitForResolution(
                timeout: timeout
            )
        else {
            XCTFail(
                "Switcher window-card projection watchdog "
                    + "expired. \(owner.diagnosticSummary)"
            )
            return owner.latestSnapshot?.cards ?? []
        }
        return evidence.value.cards
    }

    func switcherWindowCardObservations(
        in app: XCUIApplication
    ) -> [SwitcherWindowCardObservation] {
        var seenIdentifiers: Set<String> = []
        let elements = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    "flowtab.switcher.window."
                )
            )
            .allElementsBoundByAccessibilityElement
        return elements.compactMap {
            element -> SwitcherWindowCardObservation? in
            guard element.exists else { return nil }
            let identifier = element.identifier
            guard seenIdentifiers.insert(identifier).inserted else {
                return nil
            }
            let title = element.label.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !title.isEmpty else { return nil }
            let value = elementStringValue(element)
            let imageMarker = self.element(
                in: app,
                identifier: previewImageIdentifier(
                    for: identifier
                )
            )
            return SwitcherWindowCardObservation(
                identifier: identifier,
                title: title,
                value: value,
                frame: element.frame,
                hasImage:
                    value.contains("preview=image")
                    || imageMarker.exists
            )
        }
    }

    func previewImageIdentifier(
        for windowIdentifier: String
    ) -> String {
        let windowPrefix = "flowtab.switcher.window."
        let imagePrefix =
            "flowtab.switcher.window-preview-image."
        guard windowIdentifier.hasPrefix(windowPrefix) else {
            return "\(imagePrefix)\(windowIdentifier)"
        }
        return imagePrefix
            + windowIdentifier.dropFirst(windowPrefix.count)
    }
}
