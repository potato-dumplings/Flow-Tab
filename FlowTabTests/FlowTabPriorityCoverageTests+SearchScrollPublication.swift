import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testSwitcherPanelControllerSearchWrapRequestsScrollBackToFirstResult()
        async
    {
        await withTemporarySearchPreferences(
            enabled: true,
            defaultScope: .app
        ) {
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService:
                        RecordingRuntimeProjectionService(
                            appSwitcherApps:
                                self.searchWrapScenarioApps()
                        )
                )
            )
            let model = controller.modelForTesting
            let matchingScrollPublished = expectation(
                description:
                    "exact wrap revision requests first Search result"
            )
            matchingScrollPublished.assertForOverFulfill =
                true
            let initialScrollPublished = expectation(
                description:
                    "first Search result receives focused revision"
            )
            initialScrollPublished.assertForOverFulfill =
                true
            let previousScrollObserver =
                model
                    .onSearchResultScrollRequestForTesting
            var expectedRevision: UInt64?
            var expectedResultID: String?
            var expectedInitialScroll = false
            var observedRequests:
                [(revision: UInt64, resultID: String)] = []
            model.onSearchResultScrollRequestForTesting = {
                resultID in
                previousScrollObserver?(resultID)
                let revision =
                    model.searchResultScrollRevision
                observedRequests.append(
                    (
                        revision: revision,
                        resultID: resultID
                    )
                )
                guard
                    revision == expectedRevision,
                    resultID == expectedResultID
                else {
                    return
                }
                if expectedInitialScroll {
                    initialScrollPublished.fulfill()
                } else {
                    matchingScrollPublished.fulfill()
                }
            }
            defer {
                model
                    .onSearchResultScrollRequestForTesting =
                        previousScrollObserver
                controller.cancelSelectionForTesting()
            }

            XCTAssertTrue(
                controller
                    .presentGlobalHotkeySessionForTesting()
            )
            XCTAssertTrue(model.enterSearchMode())
            controller.updatePanelSizeForTesting(
                visibleFrame: CGRect(
                    x: 0,
                    y: 0,
                    width: 1440,
                    height: 900
                )
            )

            XCTAssertGreaterThan(model.searchResultCount, 0)
            guard
                let firstResultID =
                    model.searchViewState.results.first?.id
            else {
                return XCTFail(
                    "Expected Search activation to publish results synchronously"
                )
            }

            expectedRevision =
                model.searchResultScrollRevision &+ 1
            expectedResultID = firstResultID
            expectedInitialScroll = true
            XCTAssertTrue(
                controller.handleKeyDownForTesting(
                    Self.makeKeyDownEvent(keyCode: 125)
                )
            )
            await fulfillment(
                of: [initialScrollPublished],
                timeout: 1
            )
            XCTAssertEqual(
                model.searchResultScrollRevision,
                expectedRevision
            )

            expectedRevision = nil
            expectedResultID = nil
            let moveCountToLastResult =
                max(0, model.searchResultCount - 1)
            for _ in 0..<moveCountToLastResult {
                XCTAssertTrue(
                    controller.handleKeyDownForTesting(
                        Self.makeKeyDownEvent(keyCode: 125)
                    )
                )
            }
            XCTAssertEqual(
                model.searchViewState.selectedResultIndex,
                model.searchResultCount - 1
            )

            expectedRevision =
                model.searchResultScrollRevision &+ 1
            expectedResultID = firstResultID
            expectedInitialScroll = false
            XCTAssertTrue(
                controller.handleKeyDownForTesting(
                    Self.makeKeyDownEvent(keyCode: 125)
                )
            )
            XCTAssertEqual(
                model.searchResultScrollRevision,
                expectedRevision
            )
            XCTAssertEqual(
                model.searchViewState.selectedResultIndex,
                0
            )
            XCTAssertEqual(
                model.searchViewState.selectedResult?.id,
                firstResultID
            )

            await fulfillment(
                of: [matchingScrollPublished],
                timeout: 1
            )
            XCTAssertTrue(
                observedRequests.contains {
                    $0.revision == expectedRevision
                        && $0.resultID == firstResultID
                }
            )
        }
    }
}
