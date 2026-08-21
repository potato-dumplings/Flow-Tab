import Carbon
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testSwitcherPanelControllerUpArrowPreservesPendingSearchUntilCommittedIndexUpdate() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .window) {
            let apps = self.searchScenarioApps()
            let runtimeProjectionService = RecordingRuntimeProjectionService(
                appSwitcherApps: apps,
                committedSearchReadiness: .missingCommittedIndex
            )
            let releaseScheduler = ManualModifierReleaseObservationScheduler()
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService),
                modifierReleaseObservationScheduler: releaseScheduler,
                modifierReleaseEventSource: ManualModifierReleaseEventSource()
            )

            XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
            XCTAssertEqual(controller.modelForTesting.session?.mode, .appCycle)

            XCTAssertTrue(
                controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 126))
            )

            XCTAssertFalse(controller.modelForTesting.isSearchActive)
            XCTAssertTrue(controller.modelForTesting.pendingSearchActivationAfterFreshnessBarrier)
            XCTAssertEqual(controller.modelForTesting.session?.mode, .appCycle)
            XCTAssertEqual(
                runtimeProjectionService.searchIndexFreshnessBarrierRequestsRecorded(),
                [.searchFreshnessBarrier]
            )
            controller.globalHotkeyHoldSetPressedOverride = false
            controller.handleFlagsChangedForTesting(
                Self.makeFlagsChangedEvent(
                    keyCode: UInt16(kVK_Option),
                    modifierFlags: []
                )
            )
            XCTAssertFalse(controller.hasPendingModifierReleaseConfirmation)
            XCTAssertEqual(releaseScheduler.pendingCount, 0)

            runtimeProjectionService.installCommittedSearchIndex(for: apps, generatedAt: 20)

            XCTAssertTrue(controller.handleCommittedSearchIndexDidUpdateForTesting())
            XCTAssertTrue(controller.modelForTesting.isSearchActive)
            XCTAssertTrue(controller.modelForTesting.isSearchInputFocused)
            XCTAssertEqual(controller.modelForTesting.searchViewState.scope, .window)
            controller.cancelSelectionForTesting()
        }
    }

    @MainActor
    func testSwitcherPanelControllerRepeatedUpArrowCoalescesPendingSearchFreshnessBarrier() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .window) {
            let runtimeProjectionService = RecordingRuntimeProjectionService(
                appSwitcherApps: self.searchScenarioApps(),
                committedSearchReadiness: .missingCommittedIndex
            )
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
            )

            XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
            for _ in 0..<5 {
                XCTAssertTrue(
                    controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 126))
                )
            }

            XCTAssertFalse(controller.modelForTesting.isSearchActive)
            XCTAssertTrue(controller.modelForTesting.pendingSearchActivationAfterFreshnessBarrier)
            XCTAssertEqual(controller.modelForTesting.session?.mode, .appCycle)
            XCTAssertEqual(
                runtimeProjectionService.searchIndexFreshnessBarrierRequestsRecorded(),
                [.searchFreshnessBarrier]
            )
            controller.cancelSelectionForTesting()
        }
    }

    @MainActor
    func testSwitcherPanelControllerEnterPreservesPendingSearchSession() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: RecordingRuntimeProjectionService(
                        appSwitcherApps: self.searchScenarioApps(),
                        committedSearchReadiness: .missingCommittedIndex
                    )
                )
            )
            controller.modelForTesting.activationOverride = { _, _ in }

            XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
            XCTAssertTrue(
                controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 36))
            )

            XCTAssertNotNil(controller.modelForTesting.session)
            XCTAssertEqual(controller.modelForTesting.session?.mode, .appCycle)
            XCTAssertFalse(controller.modelForTesting.isSearchActive)
            XCTAssertTrue(controller.modelForTesting.pendingSearchActivationAfterFreshnessBarrier)
            controller.cancelSelectionForTesting()
        }
    }
}
