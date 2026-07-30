import CoreGraphics
import Foundation
import XCTest

struct SwitcherSearchWindowResultObservation: Equatable {
    let identifier: String
    let searchableText: String
    let resultID: String?
    let title: String?
    let appName: String?
    let appID: String?
    let windowID: String?

    init(
        identifier: String,
        searchableText: String,
        resultID: String? = nil,
        title: String? = nil,
        appName: String? = nil,
        appID: String? = nil,
        windowID: String? = nil
    ) {
        self.identifier = identifier
        self.searchableText = searchableText
        self.resultID = resultID
        self.title = title
        self.appName = appName
        self.appID = appID
        self.windowID = windowID
    }

    var windowNumber: CGWindowID? {
        if let windowID,
           let rawWindowID = windowID.split(separator: ":").last,
           let parsed = UInt32(rawWindowID) {
            return CGWindowID(parsed)
        }
        guard
            let rawWindowID = identifier.split(separator: "-").last,
            let parsed = UInt32(rawWindowID)
        else {
            return nil
        }
        return CGWindowID(parsed)
    }

    func matches(title: String, appName: String) -> Bool {
        if let observedTitle = self.title,
           let observedAppName = self.appName {
            return observedTitle == title
                && observedAppName == appName
        }
        return searchableText.localizedCaseInsensitiveContains(
            title
        )
            && searchableText.localizedCaseInsensitiveContains(
                appName
            )
    }

    var diagnosticSummary: String {
        let normalizedSearchableText =
            searchableText.replacingOccurrences(
                of: "\n",
                with: "\\n"
            )
        return "identifier=\(identifier) "
            + "resultID=\(resultID ?? "nil") "
            + "title=\(title ?? "nil") "
            + "appName=\(appName ?? "nil") "
            + "appID=\(appID ?? "nil") "
            + "windowID=\(windowID ?? "nil") "
            + "searchableText=\(normalizedSearchableText)"
    }
}

struct FlowTabUITestSwitcherSearchResultSnapshot: Equatable {
    let results: [SwitcherSearchWindowResultObservation]

    var diagnosticSummary: String {
        let resultSummary = results
            .sorted { $0.identifier < $1.identifier }
            .map(\.diagnosticSummary)
            .joined(separator: " | ")
        return "count=\(results.count) results=[\(resultSummary)]"
    }
}

enum FlowTabUITestSwitcherSearchResultExpectation:
    Equatable
{
    case matchingWindow(title: String, appName: String)
    case appWindowSet(
        appID: String,
        expectedTitles: Set<String>,
        expectedCount: Int?
    )

    func matchingResult(
        in snapshot: FlowTabUITestSwitcherSearchResultSnapshot
    ) -> SwitcherSearchWindowResultObservation? {
        guard
            case let .matchingWindow(title, appName) = self
        else {
            return nil
        }
        return snapshot.results.first {
            $0.matches(title: title, appName: appName)
        }
    }

    func isSatisfied(
        by snapshot: FlowTabUITestSwitcherSearchResultSnapshot
    ) -> Bool {
        switch self {
        case .matchingWindow:
            return matchingResult(in: snapshot) != nil
        case let .appWindowSet(
            appID,
            expectedTitles,
            expectedCount
        ):
            let appResults = snapshot.results.filter {
                $0.appID == appID
            }
            let observedTitles = Set(
                appResults.compactMap(\.title)
            )
            let countMatches =
                expectedCount.map {
                    appResults.count == $0
                } ?? true
            return expectedTitles.isSubset(of: observedTitles)
                && countMatches
        }
    }

    var diagnosticSummary: String {
        switch self {
        case let .matchingWindow(title, appName):
            return "matchingWindow title=\(title) appName=\(appName)"
        case let .appWindowSet(
            appID,
            expectedTitles,
            expectedCount
        ):
            return "appWindowSet appID=\(appID) "
                + "titles=\(expectedTitles.sorted()) "
                + "count=\(expectedCount.map(String.init) ?? "any")"
        }
    }
}

final class FlowTabUITestSwitcherSearchResultObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSwitcherSearchResultSnapshot
        >

    init(
        expectation:
            FlowTabUITestSwitcherSearchResultExpectation,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestSwitcherSearchResultSnapshot
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
        FlowTabUITestSwitcherSearchResultSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherSearchResultSnapshot
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

extension FlowTabUITests {
    func waitForSearchWindowResult(
        in app: XCUIApplication,
        title: String,
        appName: String,
        timeout: TimeInterval
    ) -> SwitcherSearchWindowResultObservation? {
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .matchingWindow(
                    title: title,
                    appName: appName
                )
        let owner =
            FlowTabUITestSwitcherSearchResultObservationOwner(
                expectation: expectation,
                readback: {
                    FlowTabUITestSwitcherSearchResultSnapshot(
                        results:
                            self.searchWindowResultObservations(
                                in: app
                            )
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard
            let evidence = owner.waitForResolution(
                timeout: timeout
            ),
            let result = expectation.matchingResult(
                in: evidence.value
            )
        else {
            XCTFail(
                "Search result projection watchdog expired. "
                    + owner.diagnosticSummary
            )
            return nil
        }
        return result
    }

    func waitForSwitcherSearchResultSet(
        _ diagnosticsSummary: XCUIElement,
        appID: String,
        expectedTitles: Set<String>,
        expectedCount: Int?,
        timeout: TimeInterval
    ) -> Bool {
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .appWindowSet(
                    appID: appID,
                    expectedTitles: expectedTitles,
                    expectedCount: expectedCount
                )
        let owner =
            FlowTabUITestSwitcherSearchResultObservationOwner(
                expectation: expectation,
                readback: {
                    FlowTabUITestSwitcherSearchResultSnapshot(
                        results:
                            self.searchWindowResultObservations(
                                from: diagnosticsSummary
                            )
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard
            owner.waitForResolution(timeout: timeout) != nil
        else {
            XCTFail(
                "Search result-set projection watchdog expired. "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }
}
