import XCTest
@testable import FlowTabCore

final class GroupingTests: XCTestCase {
    func testBuildGroupsPreservesFirstSeenGroupOrderAndAppOrderInsideGroup() {
        let groups = Grouping.buildGroups(
            from: [
                app(id: "com.example.A", groupID: "dev"),
                app(id: "com.example.B", groupID: "web"),
                app(id: "com.example.C", groupID: "dev")
            ]
        )

        XCTAssertEqual(groups.map(\.id), ["dev", "web"])
        XCTAssertEqual(groups[0].apps.map(\.id), ["com.example.A", "com.example.C"])
        XCTAssertEqual(groups[1].apps.map(\.id), ["com.example.B"])
    }

    func testBuildGroupsNormalizesEmptyGroupIDToAppScopedGroup() {
        let groups = Grouping.buildGroups(
            from: [
                app(id: "com.example.A", groupID: ""),
                app(id: "com.example.B", groupID: ""),
                app(id: "com.example.C", groupID: "dev")
            ]
        )

        XCTAssertEqual(groups.map(\.id), ["app:com.example.A", "app:com.example.B", "dev"])
        XCTAssertEqual(groups[0].apps.map(\.id), ["com.example.A"])
        XCTAssertEqual(groups[1].apps.map(\.id), ["com.example.B"])
        XCTAssertEqual(groups[2].apps.map(\.id), ["com.example.C"])
    }

    func testGroupIndexReturnsContainingGroupIndex() {
        let groups = Grouping.buildGroups(
            from: [
                app(id: "com.example.A", groupID: "dev"),
                app(id: "com.example.B", groupID: "web"),
                app(id: "com.example.C", groupID: "dev")
            ]
        )

        XCTAssertEqual(Grouping.groupIndex(containing: "com.example.C", groups: groups), 0)
        XCTAssertEqual(Grouping.groupIndex(containing: "com.example.B", groups: groups), 1)
    }

    func testGroupIndexReturnsZeroWhenAppDoesNotExist() {
        let groups = Grouping.buildGroups(from: [app(id: "com.example.A", groupID: "dev")])
        XCTAssertEqual(Grouping.groupIndex(containing: "com.example.unknown", groups: groups), 0)
    }

    func testBuildGroupsReturnsEmptyWhenInputIsEmpty() {
        XCTAssertTrue(Grouping.buildGroups(from: []).isEmpty)
    }

    private func app(id: String, groupID: String) -> AppSwitchCandidate {
        AppSwitchCandidate(
            id: id,
            displayName: id,
            groupID: groupID,
            lastActiveAt: 0,
            windows: []
        )
    }
}
