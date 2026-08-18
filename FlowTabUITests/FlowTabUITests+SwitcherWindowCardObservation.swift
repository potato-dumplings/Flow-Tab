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

enum FlowTabUITestSwitcherWindowCardPolicy {
    static let edgeInputsProjectionWatchdog: TimeInterval = 8
    static let multiAppCardIdentityProjectionWatchdog: TimeInterval = 8
}

struct FlowTabUITestSwitcherWindowPageCardExpectation: Equatable {
    let identifier: String
    let title: String
}

enum FlowTabUITestSwitcherWindowPageProjectionPolicy {
    static let minimumCardCount = 6
    static let maximumCardCount = 16
    static let minimumCardWidth: CGFloat = 100
    static let maximumCardGap: CGFloat = 24
}

struct FlowTabUITestSwitcherWindowPageBoundarySnapshot: Equatable {
    let exists: Bool
    let frame: CGRect

    var diagnosticSummary: String {
        "exists=\(exists ? 1 : 0) frame=\(frame)"
    }
}

struct FlowTabUITestSwitcherWindowPageSnapshot: Equatable {
    let cards: [SwitcherWindowCardObservation]
    let nextPageBoundary:
        FlowTabUITestSwitcherWindowPageBoundarySnapshot

    var trailingGap: CGFloat? {
        guard nextPageBoundary.exists,
              let lastCard = cards.max(by: {
                  $0.frame.maxX < $1.frame.maxX
              })
        else {
            return nil
        }
        return nextPageBoundary.frame.minX
            - lastCard.frame.maxX
    }

    var diagnosticSummary: String {
        let cardSnapshot =
            FlowTabUITestSwitcherWindowCardSnapshot(cards: cards)
        return "cards{\(cardSnapshot.diagnosticSummary)} "
            + "nextPage{\(nextPageBoundary.diagnosticSummary)} "
            + "trailingGap="
            + (trailingGap.map { String(describing: $0) } ?? "none")
    }
}

struct FlowTabUITestSwitcherWindowPageExpectation: Equatable {
    let expectedCards: [
        FlowTabUITestSwitcherWindowPageCardExpectation
    ]
    let excludedIdentifiers: Set<String>
    let minimumCardCount: Int
    let maximumCardCount: Int
    let minimumCardWidth: CGFloat
    let maximumCardGap: CGFloat

    init(
        expectedWindows: [(id: String, title: String)],
        excludedWindowIDs: [String],
        minimumCardCount: Int,
        maximumCardCount: Int,
        minimumCardWidth: CGFloat,
        maximumCardGap: CGFloat
    ) {
        expectedCards = expectedWindows.map {
            FlowTabUITestSwitcherWindowPageCardExpectation(
                identifier:
                    "flowtab.switcher.window."
                    + $0.id
                        .flowTabUITestAccessibilityIdentifierComponent,
                title: $0.title
            )
        }
        excludedIdentifiers = Set(excludedWindowIDs.map {
            "flowtab.switcher.window."
                + $0.flowTabUITestAccessibilityIdentifierComponent
        })
        self.minimumCardCount = minimumCardCount
        self.maximumCardCount = maximumCardCount
        self.minimumCardWidth = minimumCardWidth
        self.maximumCardGap = maximumCardGap
    }

    init(
        expectedCards: [
            FlowTabUITestSwitcherWindowPageCardExpectation
        ],
        excludedIdentifiers: Set<String>,
        minimumCardCount: Int,
        maximumCardCount: Int,
        minimumCardWidth: CGFloat,
        maximumCardGap: CGFloat
    ) {
        self.expectedCards = expectedCards
        self.excludedIdentifiers = excludedIdentifiers
        self.minimumCardCount = minimumCardCount
        self.maximumCardCount = maximumCardCount
        self.minimumCardWidth = minimumCardWidth
        self.maximumCardGap = maximumCardGap
    }

    func isSatisfied(
        by snapshot: FlowTabUITestSwitcherWindowPageSnapshot
    ) -> Bool {
        let cards = snapshot.cards.sorted {
            if $0.frame.minX == $1.frame.minX {
                return $0.identifier < $1.identifier
            }
            return $0.frame.minX < $1.frame.minX
        }
        let count = cards.count
        guard count >= minimumCardCount,
              count <= maximumCardCount,
              expectedCards.count >= count,
              Set(cards.map(\.identifier)).count == count,
              Set(cards.map(\.identifier))
                .isDisjoint(with: excludedIdentifiers),
              cards.map(\.identifier)
                == expectedCards.prefix(count).map(\.identifier),
              cards.map(\.title)
                == expectedCards.prefix(count).map(\.title),
              zip(cards, cards.dropFirst()).allSatisfy({ pair in
                  let (previous, current) = pair
                  let gap = current.frame.minX
                      - previous.frame.maxX
                  return gap >= 0
                      && gap <= maximumCardGap
              }),
              cards.allSatisfy({ card in
                  card.hasImage
                      && card.frame.width.isFinite
                      && card.frame.height.isFinite
                      && card.frame.width >= minimumCardWidth
                      && card.frame.height > 0
              }),
              snapshot.nextPageBoundary.exists,
              snapshot.nextPageBoundary.frame.minX.isFinite,
              snapshot.nextPageBoundary.frame.width > 0,
              let trailingGap = snapshot.trailingGap
        else {
            return false
        }
        return trailingGap >= 0
            && trailingGap <= maximumCardGap
    }

    var diagnosticSummary: String {
        let cardSummary = expectedCards.map {
            "\($0.identifier){title=\($0.title)}"
        }
        .joined(separator: ",")
        return "cardCount=\(minimumCardCount)...\(maximumCardCount) "
            + "minimumCardWidth=\(minimumCardWidth) "
            + "maximumCardGap=\(maximumCardGap) "
            + "excludedIdentifiers=\(excludedIdentifiers.sorted()) "
            + "expectedCards=[\(cardSummary)]"
    }
}

private enum FlowTabUITestSwitcherWindowPagePhase: String {
    case initialReadback
    case awaitingTrigger
    case triggerCompleted
}

private final class FlowTabUITestSwitcherWindowPageState {
    var phase: FlowTabUITestSwitcherWindowPagePhase =
        .initialReadback

    var acceptsEvidence: Bool {
        phase == .triggerCompleted
    }
}

final class FlowTabUITestSwitcherWindowPageObservationOwner {
    private let state: FlowTabUITestSwitcherWindowPageState
    private let deferredReadbacks:
        FlowTabUITestDeferredConditionReadbackRegistration
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSwitcherWindowPageSnapshot
        >

    init(
        expectation:
            FlowTabUITestSwitcherWindowPageExpectation,
        scheduledRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestSwitcherWindowPageSnapshot
    ) {
        let state = FlowTabUITestSwitcherWindowPageState()
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration: scheduledRegistration
            )
        self.state = state
        self.deferredReadbacks = deferredReadbacks
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: { callback in
                deferredReadbacks.register(callback)
            },
            readback: readback,
            isSatisfied: { snapshot in
                state.acceptsEvidence
                    && expectation.isSatisfied(by: snapshot)
            },
            describe: { snapshot in
                "phase=\(state.phase.rawValue) "
                    + "expected{\(expectation.diagnosticSummary)} "
                    + "observed{\(snapshot.diagnosticSummary)}"
            }
        )
    }

    func start() {
        state.phase = .initialReadback
        conditionOwner.start()
        state.phase = .awaitingTrigger
    }

    func markTriggerCompleted() {
        guard conditionOwner.resolvedEvidence == nil else {
            return
        }
        state.phase = .triggerCompleted
        conditionOwner.requestReadback(source: .triggerReadback)
        if conditionOwner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherWindowPageSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherWindowPageSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestSnapshot:
        FlowTabUITestSwitcherWindowPageSnapshot? {
        conditionOwner.latestEvidence?.value
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
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
    func startSwitcherWindowPageProjectionObservation(
        in app: XCUIApplication,
        expectation:
            FlowTabUITestSwitcherWindowPageExpectation,
        nextPageIdentifier: String,
        requiresEmptyInitialSnapshot: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> FlowTabUITestSwitcherWindowPageObservationOwner {
        let nextPage = element(
            in: app,
            identifier: nextPageIdentifier
        )
        let owner =
            FlowTabUITestSwitcherWindowPageObservationOwner(
                expectation: expectation,
                readback: {
                    let nextPageExists = nextPage.exists
                    return FlowTabUITestSwitcherWindowPageSnapshot(
                        cards:
                            self.switcherWindowCardObservations(
                                in: app
                            ),
                        nextPageBoundary:
                            FlowTabUITestSwitcherWindowPageBoundarySnapshot(
                                exists: nextPageExists,
                                frame:
                                    nextPageExists
                                        ? nextPage.frame
                                        : .zero
                            )
                    )
                }
            )
        owner.start()
        if requiresEmptyInitialSnapshot,
           let snapshot = owner.latestSnapshot,
           !snapshot.cards.isEmpty
            || snapshot.nextPageBoundary.exists
        {
            XCTFail(
                "Switcher window-page baseline mismatch; "
                    + "expectedCardCount=0 expectedNextPage=0. "
                    + owner.diagnosticSummary,
                file: file,
                line: line
            )
        }
        return owner
    }

    func assertSwitcherWindowPageProjectionAfterTrigger(
        _ owner:
            FlowTabUITestSwitcherWindowPageObservationOwner,
        timeout: TimeInterval,
        description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> FlowTabUITestSwitcherWindowPageSnapshot {
        owner.markTriggerCompleted()
        guard let evidence = owner.waitForResolution(
            timeout: timeout
        ) else {
            XCTFail(
                "\(description) watchdog expired. "
                    + owner.diagnosticSummary,
                file: file,
                line: line
            )
            return owner.latestSnapshot
                ?? FlowTabUITestSwitcherWindowPageSnapshot(
                    cards: [],
                    nextPageBoundary:
                        FlowTabUITestSwitcherWindowPageBoundarySnapshot(
                            exists: false,
                            frame: .zero
                        )
                )
        }
        return evidence.value
    }

    func performAndWaitForSwitcherWindowCards(
        in app: XCUIApplication,
        expectedTitles: [String],
        excludedTitles: [String] = [],
        previousWindowCardIdentifiers: Set<String> = [],
        requiresEmptyInitialSnapshot: Bool = false,
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
        if requiresEmptyInitialSnapshot,
            owner.latestSnapshot?.cards.isEmpty != true
        {
            XCTFail(
                "Switcher window-card baseline mismatch; "
                    + "expectedCardCount=0. "
                    + owner.diagnosticSummary
            )
        }

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
