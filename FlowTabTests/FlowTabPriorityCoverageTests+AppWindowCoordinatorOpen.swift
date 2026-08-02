import Foundation
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testAppWindowCoordinatorOpenMethodsSelectRequestedTabBeforeActivation() async {
        let previousSelectedTab =
            HomeTabState.shared.selectedTab
        let previousActivationOverride =
            AppWindowCoordinator
                .activateMainWindowOrOpenHomeSceneOverride
        var operations: [AppWindowCoordinator.OpenOperation] = []
        defer {
            operations.forEach { $0.cancel() }
            HomeTabState.shared.selectedTab =
                previousSelectedTab
            AppWindowCoordinator
                .activateMainWindowOrOpenHomeSceneOverride =
                previousActivationOverride
        }

        let cases: [AppWindowOpenCase] = [
            AppWindowOpenCase(
                name: "home",
                initial: .settings,
                expected: .home,
                open: { AppWindowCoordinator.openHome() }
            ),
            AppWindowOpenCase(
                name: "logs",
                initial: .home,
                expected: .logs,
                open: { AppWindowCoordinator.openLogs() }
            ),
            AppWindowOpenCase(
                name: "settings",
                initial: .logs,
                expected: .settings,
                open: { AppWindowCoordinator.openSettings() }
            )
        ]

        for item in cases {
            var observedTabsAtActivation: [HomeTab] = []
            HomeTabState.shared.selectedTab = item.initial
            AppWindowCoordinator
                .activateMainWindowOrOpenHomeSceneOverride = {
                XCTAssertTrue(Thread.isMainThread)
                observedTabsAtActivation.append(
                    HomeTabState.shared.selectedTab
                )
            }

            XCTAssertTrue(observedTabsAtActivation.isEmpty)
            let operation = item.open()
            operations.append(operation)
            XCTAssertEqual(
                HomeTabState.shared.selectedTab,
                item.initial,
                "unmetCondition=openRequestRemainsQueuedUntilMainActorDelivery case=\(item.name)"
            )
            XCTAssertTrue(observedTabsAtActivation.isEmpty)

            await operation.value

            XCTAssertEqual(
                HomeTabState.shared.selectedTab,
                item.expected
            )
            XCTAssertEqual(
                observedTabsAtActivation,
                [item.expected]
            )

            await operation.value
            XCTAssertEqual(
                observedTabsAtActivation,
                [item.expected]
            )
        }
    }
}

private struct AppWindowOpenCase {
    let name: String
    let initial: HomeTab
    let expected: HomeTab
    let open: () -> AppWindowCoordinator.OpenOperation
}
