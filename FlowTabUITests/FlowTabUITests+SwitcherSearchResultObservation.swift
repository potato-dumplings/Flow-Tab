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
    let resultsScope: String?
    let resultsQuery: String?
    let committedResultIDs: [String]
    let observedRowIdentifiers: [String]
    let applicationState: XCUIApplication.State?

    init(
        results: [SwitcherSearchWindowResultObservation],
        resultsScope: String? = nil,
        resultsQuery: String? = nil,
        committedResultIDs: [String]? = nil,
        observedRowIdentifiers: [String] = [],
        applicationState: XCUIApplication.State? = nil
    ) {
        self.results = results
        self.resultsScope = resultsScope
        self.resultsQuery = resultsQuery
        self.committedResultIDs =
            committedResultIDs
                ?? results.compactMap(\.resultID)
        self.observedRowIdentifiers = observedRowIdentifiers
        self.applicationState = applicationState
    }

    var diagnosticSummary: String {
        let resultSummary = results
            .sorted { $0.identifier < $1.identifier }
            .map(\.diagnosticSummary)
            .joined(separator: " | ")
        return "scope=\(resultsScope ?? "nil") "
            + "query=\(resultsQuery ?? "nil") "
            + "resultIDs=\(committedResultIDs) "
            + "rowIdentifiers=\(observedRowIdentifiers) "
            + "appState=\(String(describing: applicationState)) "
            + "count=\(results.count) "
            + "results=[\(resultSummary)]"
    }
}

struct FlowTabUITestSwitcherSearchExpectedResultRow:
    Equatable,
    Hashable
{
    let resultID: String
    let rowIdentifier: String

    static func formsValidProjection(
        _ rows: [Self]
    ) -> Bool {
        !rows.isEmpty
            && Set(rows.map(\.resultID)).count == rows.count
            && Set(rows.map(\.rowIdentifier)).count
                == rows.count
    }
}

enum FlowTabUITestSwitcherSearchResultExpectation:
    Equatable
{
    case matchingWindow(title: String, appName: String)
    case committedMatchingWindow(
        scope: String,
        query: String,
        title: String,
        appName: String
    )
    case appWindowSet(
        appID: String,
        expectedTitles: Set<String>,
        expectedCount: Int?
    )
    case exactWindowIdentifiers(
        scope: String,
        query: String,
        identifierFragment: String?,
        expectedCount: Int
    )
    case committedResultRows(
        scope: String,
        query: String,
        rows: [FlowTabUITestSwitcherSearchExpectedResultRow]
    )

    func matchingResult(
        in snapshot: FlowTabUITestSwitcherSearchResultSnapshot
    ) -> SwitcherSearchWindowResultObservation? {
        let title: String
        let appName: String
        switch self {
        case let .matchingWindow(
            expectedTitle,
            expectedAppName
        ):
            title = expectedTitle
            appName = expectedAppName
        case let .committedMatchingWindow(
            scope,
            query,
            expectedTitle,
            expectedAppName
        ):
            guard snapshot.resultsScope == scope,
                  snapshot.resultsQuery == query
            else {
                return nil
            }
            title = expectedTitle
            appName = expectedAppName
        default:
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
        case .matchingWindow,
             .committedMatchingWindow:
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
        case .exactWindowIdentifiers:
            return matchingIdentifiers(in: snapshot) != nil
        case let .committedResultRows(
            scope,
            query,
            rows
        ):
            guard FlowTabUITestSwitcherSearchExpectedResultRow
                .formsValidProjection(rows)
            else {
                return false
            }
            let expectedResultIDs = Set(rows.map(\.resultID))
            let expectedRowIdentifiers = Set(
                rows.map(\.rowIdentifier)
            )
            return snapshot.resultsScope == scope
                && snapshot.resultsQuery == query
                && expectedResultIDs.isSubset(
                    of: Set(snapshot.committedResultIDs)
                )
                && snapshot.observedRowIdentifiers.count
                    == rows.count
                && Set(snapshot.observedRowIdentifiers)
                    == expectedRowIdentifiers
                && snapshot.applicationState
                    == .runningForeground
        }
    }

    func hasCommittedIdentity(
        in snapshot: FlowTabUITestSwitcherSearchResultSnapshot
    ) -> Bool {
        guard
            case let .committedResultRows(
                scope,
                query,
                rows
            ) = self
        else {
            return false
        }
        guard FlowTabUITestSwitcherSearchExpectedResultRow
            .formsValidProjection(rows)
        else {
            return false
        }
        let expectedResultIDs = Set(rows.map(\.resultID))
        return snapshot.resultsScope == scope
            && snapshot.resultsQuery == query
            && expectedResultIDs.isSubset(
                of: Set(snapshot.committedResultIDs)
            )
    }

    func matchingIdentifiers(
        in snapshot: FlowTabUITestSwitcherSearchResultSnapshot
    ) -> [String]? {
        guard
            case let .exactWindowIdentifiers(
                scope,
                query,
                identifierFragment,
                expectedCount
            ) = self,
            snapshot.resultsScope == scope,
            snapshot.resultsQuery == query
        else {
            return nil
        }
        let identifiers = snapshot.results
            .map(\.identifier)
            .filter { identifier in
                identifierFragment.map {
                    identifier.contains($0)
                } ?? true
            }
        guard identifiers.count == expectedCount,
              Set(identifiers).count == identifiers.count
        else {
            return nil
        }
        return identifiers
    }

    var diagnosticSummary: String {
        switch self {
        case let .matchingWindow(title, appName):
            return "matchingWindow title=\(title) appName=\(appName)"
        case let .committedMatchingWindow(
            scope,
            query,
            title,
            appName
        ):
            return "committedMatchingWindow scope=\(scope) "
                + "query=\(query) title=\(title) "
                + "appName=\(appName)"
        case let .appWindowSet(
            appID,
            expectedTitles,
            expectedCount
        ):
            return "appWindowSet appID=\(appID) "
                + "titles=\(expectedTitles.sorted()) "
                + "count=\(expectedCount.map(String.init) ?? "any")"
        case let .exactWindowIdentifiers(
            scope,
            query,
            identifierFragment,
            expectedCount
        ):
            return "exactWindowIdentifiers scope=\(scope) "
                + "query=\(query) "
                + "fragment=\(identifierFragment ?? "<any>") "
                + "count=\(expectedCount)"
        case let .committedResultRows(
            scope,
            query,
            rows
        ):
            let rowSummary = rows.map {
                "resultID=\($0.resultID),"
                    + "rowIdentifier=\($0.rowIdentifier)"
            }.joined(separator: " | ")
            return "committedResultRows scope=\(scope) "
                + "query=\(query) rows=[\(rowSummary)]"
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
        acceptsEvidence: @escaping () -> Bool = {
            true
        },
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

    func requestReadback(
        source: FlowTabUITestConditionObservationSource
    ) {
        conditionOwner.requestReadback(source: source)
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

    var latestSnapshot:
        FlowTabUITestSwitcherSearchResultSnapshot?
    {
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
    func searchWindowResultObservations(
        inDiagnosticsProjection rawValue: String
    ) -> [SwitcherSearchWindowResultObservation] {
        guard !rawValue.isEmpty, rawValue != "inactive" else {
            return []
        }

        var seenResultIDs: Set<String> = []
        return rawValue
            .split(
                separator: "|",
                omittingEmptySubsequences: true
            )
            .compactMap {
                entry -> SwitcherSearchWindowResultObservation? in
                let fields = entry.split(
                    separator: ",",
                    omittingEmptySubsequences: false
                )
                guard fields.count == 6,
                      fields[1] == "window"
                else {
                    return nil
                }

                let decodedFields = fields.map {
                    let rawField = String($0)
                    return rawField.removingPercentEncoding
                        ?? rawField
                }
                let resultID = decodedFields[0]
                guard seenResultIDs.insert(resultID).inserted
                else {
                    return nil
                }
                let appID = decodedFields[2]
                let windowID = decodedFields[3]
                let title = decodedFields[4]
                let appName = decodedFields[5]
                let identifier =
                    "flowtab.switcher.search.window."
                    + resultID
                        .flowTabUITestAccessibilityIdentifierComponent
                return SwitcherSearchWindowResultObservation(
                    identifier: identifier,
                    searchableText:
                        [title, appName, appID, windowID]
                            .joined(separator: "\n"),
                    resultID: resultID,
                    title: title,
                    appName: appName,
                    appID: appID,
                    windowID: windowID
                )
            }
    }

    func searchResultIdentifiers(
        inDiagnosticsProjection rawValue: String
    ) -> [String] {
        guard !rawValue.isEmpty, rawValue != "inactive" else {
            return []
        }

        var seenResultIDs: Set<String> = []
        return rawValue
            .split(
                separator: "|",
                omittingEmptySubsequences: true
            )
            .compactMap { entry in
                let fields = entry.split(
                    separator: ",",
                    omittingEmptySubsequences: false
                )
                guard fields.count == 6,
                      fields[1] == "app"
                        || fields[1] == "window"
                else {
                    return nil
                }
                let rawResultID = String(fields[0])
                let resultID =
                    rawResultID.removingPercentEncoding
                        ?? rawResultID
                guard !resultID.isEmpty,
                      seenResultIDs.insert(resultID).inserted
                else {
                    return nil
                }
                return resultID
            }
    }

    func committedSwitcherSearchResultSnapshot(
        in app: XCUIApplication,
        targetRowIdentifiers: [String] = []
    ) -> FlowTabUITestSwitcherSearchResultSnapshot {
        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        let diagnostics = switcherDiagnosticsSnapshot(
            diagnosticsSummary,
            keys: [
                "searchResultsScope",
                "searchResultsQuery",
                "searchResults"
            ]
        )
        let rawQuery = diagnostics.values[
            "searchResultsQuery"
        ]
        let rawResults =
            diagnostics.values["searchResults"] ?? ""
        let observedRowIdentifiers =
            targetRowIdentifiers.compactMap { identifier in
                let row = element(
                    in: app,
                    identifier: identifier
                )
                return row.exists ? row.identifier : nil
            }
        return FlowTabUITestSwitcherSearchResultSnapshot(
            results:
                searchWindowResultObservations(
                    inDiagnosticsProjection:
                        rawResults
                ),
            resultsScope:
                diagnostics.values["searchResultsScope"],
            resultsQuery:
                rawQuery.map {
                    $0.removingPercentEncoding ?? $0
                },
            committedResultIDs:
                searchResultIdentifiers(
                    inDiagnosticsProjection: rawResults
                ),
            observedRowIdentifiers:
                observedRowIdentifiers,
            applicationState: app.state
        )
    }

    func performAndWaitForSwitcherSearchWindowIdentifiers(
        in app: XCUIApplication,
        scope: String,
        query: String,
        identifierFragment: String? = nil,
        expectedCount: Int,
        timeout: TimeInterval,
        trigger: () -> Void
    ) -> [String] {
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .exactWindowIdentifiers(
                    scope: scope,
                    query: query,
                    identifierFragment: identifierFragment,
                    expectedCount: expectedCount
                )
        var triggerCompleted = false
        let owner =
            FlowTabUITestSwitcherSearchResultObservationOwner(
                expectation: expectation,
                acceptsEvidence: {
                    triggerCompleted
                },
                readback: {
                    self.committedSwitcherSearchResultSnapshot(
                        in: app
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
            ),
            let identifiers = expectation.matchingIdentifiers(
                in: evidence.value
            )
        else {
            XCTFail(
                "Committed Search result projection watchdog "
                    + "expired. \(owner.diagnosticSummary)"
            )
            return owner.latestSnapshot?.results
                .map(\.identifier)
                .filter { identifier in
                    identifierFragment.map {
                        identifier.contains($0)
                    } ?? true
                } ?? []
        }
        return identifiers
    }

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
