import XCTest
@testable import FlowTabCore

final class StableIdentityOrderTests: XCTestCase {
    private struct Item: Equatable {
        let id: String
        let value: Int
    }

    func testReconcileKeepsRetainedIdentitiesStableAndAppendsNewIdentities() {
        let current = [
            Item(id: "mail", value: 1),
            Item(id: "browser", value: 2),
            Item(id: "notes", value: 3),
        ]
        let updated = [
            Item(id: "notes", value: 30),
            Item(id: "calendar", value: 40),
            Item(id: "mail", value: 10),
        ]

        let reconciled = StableIdentityOrder.reconcile(
            current: current,
            updated: updated,
            identity: { $0.id }
        )

        XCTAssertEqual(reconciled, [
            Item(id: "mail", value: 10),
            Item(id: "notes", value: 30),
            Item(id: "calendar", value: 40),
        ])
    }

    func testReconcileUsesUpdatedOrderWhenThereIsNoVisibleOrder() {
        let updated = [
            Item(id: "notes", value: 3),
            Item(id: "mail", value: 1),
        ]

        XCTAssertEqual(
            StableIdentityOrder.reconcile(
                current: [],
                updated: updated,
                identity: { $0.id }
            ),
            updated
        )
    }

    func testReconcilePlacesNewRuntimeLeaderAheadOfVisibleOrder() {
        let current = [
            Item(id: "mail", value: 1),
            Item(id: "browser", value: 2),
        ]
        let updated = [
            Item(id: "calendar", value: 30),
            Item(id: "browser", value: 20),
            Item(id: "mail", value: 10),
        ]

        XCTAssertEqual(
            StableIdentityOrder.reconcile(
                current: current,
                updated: updated,
                identity: { $0.id }
            ),
            [
                Item(id: "calendar", value: 30),
                Item(id: "mail", value: 10),
                Item(id: "browser", value: 20),
            ]
        )
    }
}
