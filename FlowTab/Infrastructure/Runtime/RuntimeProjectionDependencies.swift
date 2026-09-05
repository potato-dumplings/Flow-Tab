import Foundation

struct RuntimeProjectionDependencies {
    let windowRecordStore: RuntimeWindowRecordStore
    let reconciliationCoordinator: RuntimeReconciliationCoordinator
    var factProvider: any RuntimeProjectionRepairFactProviding
    var windowEntries: any RuntimeWindowEntryProjecting
    var focusedWindowFacts: (any RuntimeFocusedWindowFactCollecting)? = nil
    var mainTableProjectionBuilder: any RuntimeMainTableProjectionBuilding
    var appDirectoryProvider: (any RuntimeAppDirectoryProviding)?
    var axWindowRepairAvailability: @Sendable () -> Bool

    static func system() -> Self {
        let store = RuntimeWindowRecordStore()
        let coordinator = RuntimeReconciliationCoordinator()
        return Self(
            windowRecordStore: store,
            reconciliationCoordinator: coordinator,
            factProvider: RuntimeSystemRepairFactProvider(
                cgWindowListProvider: RuntimeSystemCGWindowListProvider(),
                spaceTopologyProvider: RuntimeSystemSpaceTopologyProvider(),
                windowRecordStore: store,
                reconciliationCoordinator: coordinator
            ),
            windowEntries: RuntimeWindowEntryProjector(windowRecordStore: store),
            mainTableProjectionBuilder: RuntimeMainTableProjectionBuilder(windowRecordStore: store),
            appDirectoryProvider: RuntimeAppDirectoryProviderFactory.makeDefault(),
            axWindowRepairAvailability: { AccessibilityPermissionChecker.isTrusted() }
        )
    }

    func makeRepairProvider() -> RuntimeProjectionRepairProvider {
        RuntimeProjectionRepairProvider(
            windowRecordStore: windowRecordStore,
            reconciliationCoordinator: reconciliationCoordinator,
            runtimeFactProvider: factProvider,
            windowEntries: windowEntries,
            focusedWindowFacts: focusedWindowFacts
        )
    }
}
