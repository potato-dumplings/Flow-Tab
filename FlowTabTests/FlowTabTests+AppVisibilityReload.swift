import Combine
import XCTest
@testable import FlowTab

private enum AppVisibilityReloadWatchdogPolicy {
    static let eventDelivery: TimeInterval = 5
}

struct StaticAppVisibilityInventory: AppInventoryProviding {
    let records: [InstalledAppRecord]

    func installedApps() -> [InstalledAppRecord] {
        records
    }
}

extension FlowTabTests {
    @MainActor
    func testAppVisibilityManagerReconcilesInventoryAndRejectsSystemManagedMutation() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        let configurableAppID = "com.example.editor"
        let systemManagedAppID = "com.example.menu-bar"
        userDefaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        userDefaults.set(
            [systemManagedAppID, "com.example.helper"],
            forKey: AppPreferenceKeys.hiddenAppIDs
        )
        let inventory = StaticAppVisibilityInventory(
            records: [
                InstalledAppRecord(
                    id: configurableAppID,
                    displayName: "Editor",
                    bundleIdentifier: configurableAppID,
                    path: "/Applications/Editor.app",
                    isRunning: true
                ),
                InstalledAppRecord(
                    id: systemManagedAppID,
                    displayName: "Menu Bar",
                    bundleIdentifier: systemManagedAppID,
                    path: "/Applications/Menu Bar.app",
                    isRunning: true,
                    visibilityCapability: .systemManaged(reason: .macOSRuntimeMode)
                )
            ]
        )
        let model = AppVisibilityManagerModel(
            inventoryService: inventory,
            userDefaults: userDefaults
        )
        let reloadCompleted = expectation(description: "visibility inventory reconciled")
        let readinessObservation = model.$inventoryReadiness.sink { readiness in
            if readiness == .ready {
                reloadCompleted.fulfill()
            }
        }
        var notificationCount = 0
        let notificationObserver = NotificationCenter.default.addObserver(
            forName: .flowTabAppVisibilityPreferenceChanged,
            object: nil,
            queue: .main
        ) { _ in
            notificationCount += 1
        }
        defer {
            readinessObservation.cancel()
            NotificationCenter.default.removeObserver(notificationObserver)
        }

        model.reload()
        await fulfillment(
            of: [reloadCompleted],
            timeout: AppVisibilityReloadWatchdogPolicy.eventDelivery
        )

        XCTAssertEqual(model.apps.map(\.id), [configurableAppID, systemManagedAppID])
        XCTAssertTrue(model.hiddenAppIDs.isEmpty)
        XCTAssertEqual(notificationCount, 1)

        model.setHidden(true, for: systemManagedAppID)
        XCTAssertTrue(model.hiddenAppIDs.isEmpty)
        XCTAssertEqual(notificationCount, 1)

        model.setHidden(true, for: configurableAppID)
        XCTAssertEqual(model.hiddenAppIDs, [configurableAppID])
        XCTAssertEqual(notificationCount, 2)
    }

    func testAppVisibilityInventoryReadinessAccessibilityIdentifiersAreStable() {
        XCTAssertEqual(
            AppVisibilityInventoryReadiness.idle.accessibilityIdentifier,
            "flowtab.settings.app-visibility.inventory.idle"
        )
        XCTAssertEqual(
            AppVisibilityInventoryReadiness.loading.accessibilityIdentifier,
            "flowtab.settings.app-visibility.inventory.loading"
        )
        XCTAssertEqual(
            AppVisibilityInventoryReadiness.ready.accessibilityIdentifier,
            "flowtab.settings.app-visibility.inventory.ready"
        )
    }

    @MainActor
    func testAppVisibilityQueryProjectionGenerationTracksCommittedChanges() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }
        let model = AppVisibilityManagerModel(userDefaults: userDefaults)
        var observedQueries: [String] = []
        var observedGenerations: [UInt64] = []
        let queryObservation = model.$query.sink {
            observedQueries.append($0)
        }
        let generationObservation = model.$queryProjectionGeneration.sink {
            observedGenerations.append($0)
        }
        defer {
            queryObservation.cancel()
            generationObservation.cancel()
        }

        XCTAssertEqual(
            AppVisibilityQueryProjectionAccessibility.identifierPrefix,
            "flowtab.settings.app-visibility.list.query-generation."
        )
        XCTAssertEqual(
            AppVisibilityQueryProjectionAccessibility.identifier(generation: 0),
            "flowtab.settings.app-visibility.list.query-generation.0"
        )

        model.updateQuery("Mail")
        model.updateQuery("Mail")
        model.updateQuery("ceshi")

        XCTAssertEqual(model.query, "ceshi")
        XCTAssertEqual(model.queryProjectionGeneration, 2)
        XCTAssertEqual(observedQueries, ["", "Mail", "ceshi"])
        XCTAssertEqual(observedGenerations, [0, 1, 2])
    }

    @MainActor
    func testAppVisibilityFilterProjectionGenerationTracksCommittedChanges() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }
        let model = AppVisibilityManagerModel(userDefaults: userDefaults)
        var observedFilters: [AppVisibilityManagerModel.Filter] = []
        var observedGenerations: [UInt64] = []
        let filterObservation = model.$filter.sink {
            observedFilters.append($0)
        }
        let generationObservation = model.$filterProjectionGeneration.sink {
            observedGenerations.append($0)
        }
        defer {
            filterObservation.cancel()
            generationObservation.cancel()
        }

        XCTAssertEqual(
            AppVisibilityFilterProjectionAccessibility.identifierPrefix,
            "flowtab.settings.app-visibility.filter-projection."
        )
        XCTAssertEqual(
            AppVisibilityFilterProjectionAccessibility.identifier(
                filterRawValue: "all",
                generation: 0
            ),
            "flowtab.settings.app-visibility.filter-projection.all.generation.0"
        )

        model.updateFilter(.hidden)
        model.updateFilter(.hidden)
        model.updateFilter(.running)

        XCTAssertEqual(model.filter, .running)
        XCTAssertEqual(model.filterProjectionGeneration, 2)
        XCTAssertEqual(observedFilters, [.all, .hidden, .running])
        XCTAssertEqual(observedGenerations, [0, 1, 2])
    }

    @MainActor
    func testAppVisibilitySelectionProjectionGenerationTracksCommittedChanges() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }
        let model = AppVisibilityManagerModel(userDefaults: userDefaults)
        var observedAppIDs: [String?] = []
        var observedGenerations: [UInt64] = []
        let selectionObservation = model.$selectedAppID.sink {
            observedAppIDs.append($0)
        }
        let generationObservation = model.$selectionProjectionGeneration.sink {
            observedGenerations.append($0)
        }
        defer {
            selectionObservation.cancel()
            generationObservation.cancel()
        }

        XCTAssertEqual(
            AppVisibilityDetailProjectionAccessibility.identifierPrefix,
            "flowtab.settings.app-visibility.detail."
        )
        XCTAssertEqual(
            AppVisibilityDetailProjectionAccessibility.identifierPrefix(
                appID: "com.example.mail"
            ),
            "flowtab.settings.app-visibility.detail.com-example-mail.id-2e85d467.generation."
        )
        XCTAssertEqual(
            AppVisibilityDetailProjectionAccessibility.identifier(
                appID: "com.example.mail",
                generation: 1
            ),
            "flowtab.settings.app-visibility.detail.com-example-mail.id-2e85d467.generation.1"
        )

        model.selectApp("com.example.mail")
        model.selectApp("com.example.mail")
        model.selectApp(nil)
        model.selectApp("com.example.browser")

        XCTAssertEqual(model.selectedAppID, "com.example.browser")
        XCTAssertEqual(model.selectionProjectionGeneration, 3)
        XCTAssertEqual(
            observedAppIDs,
            [nil, "com.example.mail", nil, "com.example.browser"]
        )
        XCTAssertEqual(observedGenerations, [0, 1, 2, 3])
    }

    func testAppVisibilityReloadWatchdogPolicyPreservesEventDeliveryBound() {
        let eventDelivery =
            AppVisibilityReloadWatchdogPolicy.eventDelivery

        XCTAssertEqual(eventDelivery, 5)
        XCTAssertTrue(eventDelivery.isFinite)
        XCTAssertGreaterThan(eventDelivery, 0)
    }

    @MainActor
    func testAppVisibilityManagerRemovesStoredHiddenAppIDsMissingFromInventory() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        let missingAppID = "com.flowtab.hidden.missing"
        userDefaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        AppVisibilityPreferencesStore.saveHiddenAppIDs(
            [missingAppID],
            userDefaults: userDefaults
        )

        await withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-mock-runtime"]) {
            let model = AppVisibilityManagerModel(
                inventoryService: StaticAppVisibilityInventory(records: []),
                userDefaults: userDefaults
            )
            model.updateFilter(.hidden)
            let reloadCompleted = expectation(
                description:
                    "unmetCondition=hiddenAppInventoryCleanupTransitionCompleted expectedVisibleAppIDs=empty"
            )
            reloadCompleted.assertForOverFulfill = true
            var observedLoadingStates: [Bool] = []
            var observedReadinessStates:
                [AppVisibilityInventoryReadiness] = []
            var completionCount = 0
            var lastVisibleAppIDs: [String] = []
            var lastSelectedAppID: String?
            var lastHiddenCount = 0
            var observedSelectionGenerations: [UInt64] = []
            let loadingObservation = model.$isLoading
                .sink { isLoading in
                    XCTAssertTrue(Thread.isMainThread)
                    observedLoadingStates.append(isLoading)
                }
            let readinessObservation = model.$inventoryReadiness
                .sink { readiness in
                    XCTAssertTrue(Thread.isMainThread)
                    observedReadinessStates.append(readiness)
                    guard Array(observedReadinessStates.suffix(2))
                        == [.loading, .ready]
                    else {
                        return
                    }
                    completionCount += 1
                    lastVisibleAppIDs =
                        model.visibleApps.map(\.id)
                    lastSelectedAppID = model.selectedApp?.id
                    lastHiddenCount = model.hiddenCount
                    reloadCompleted.fulfill()
                }
            let selectionGenerationObservation =
                model.$selectionProjectionGeneration.sink {
                    observedSelectionGenerations.append($0)
                }
            defer {
                loadingObservation.cancel()
                readinessObservation.cancel()
                selectionGenerationObservation.cancel()
            }

            XCTAssertEqual(observedLoadingStates, [false])
            XCTAssertEqual(observedReadinessStates, [.idle])
            XCTAssertEqual(completionCount, 0)
            XCTAssertTrue(lastVisibleAppIDs.isEmpty)
            XCTAssertNil(lastSelectedAppID)
            XCTAssertEqual(lastHiddenCount, 0)
            XCTAssertEqual(observedSelectionGenerations, [0])

            model.reload()
            await fulfillment(
                of: [reloadCompleted],
                timeout:
                    AppVisibilityReloadWatchdogPolicy
                        .eventDelivery
            )

            XCTAssertFalse(model.isLoading)
            XCTAssertEqual(model.inventoryReadiness, .ready)
            XCTAssertEqual(
                observedLoadingStates,
                [false, true, false],
                "unmetCondition=singleHiddenAppInventoryLoadingTransition "
                    + "finalLoadingStates=\(observedLoadingStates) "
                    + "finalVisibleAppIDs=\(lastVisibleAppIDs) "
                    + "finalSelectedAppID=\(lastSelectedAppID ?? "nil") "
                    + "finalHiddenCount=\(lastHiddenCount)"
            )
            XCTAssertEqual(
                observedReadinessStates,
                [.idle, .loading, .ready]
            )
            XCTAssertEqual(completionCount, 1)
            XCTAssertEqual(lastHiddenCount, 0)
            XCTAssertTrue(lastVisibleAppIDs.isEmpty)
            XCTAssertNil(lastSelectedAppID)
            XCTAssertEqual(model.hiddenCount, 0)
            XCTAssertTrue(model.visibleApps.isEmpty)
            XCTAssertNil(model.selectedApp)
            XCTAssertEqual(model.selectionProjectionGeneration, 0)
            XCTAssertEqual(observedSelectionGenerations, [0])
            XCTAssertEqual(
                userDefaults.stringArray(forKey: AppPreferenceKeys.hiddenAppIDs),
                []
            )
        }
    }

    @MainActor
    func testAppVisibilityManagerSearchUsesSharedPinyinMatching() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        await withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-mock-runtime"]) {
            let model = AppVisibilityManagerModel(userDefaults: userDefaults)
            model.updateQuery("ceshi")
            let reloadCompleted = expectation(
                description:
                    "unmetCondition=searchableAppInventoryLoadingTransitionCompleted expectedVisibleAppIDs=com.xxx.test"
            )
            reloadCompleted.assertForOverFulfill = true
            var observedLoadingStates: [Bool] = []
            var observedReadinessStates:
                [AppVisibilityInventoryReadiness] = []
            var completionCount = 0
            var lastVisibleAppIDs: [String] = []
            var lastSelectedAppID: String?
            let loadingObservation = model.$isLoading
                .sink { isLoading in
                    XCTAssertTrue(Thread.isMainThread)
                    observedLoadingStates.append(isLoading)
                }
            let readinessObservation = model.$inventoryReadiness
                .sink { readiness in
                    XCTAssertTrue(Thread.isMainThread)
                    observedReadinessStates.append(readiness)
                    guard Array(observedReadinessStates.suffix(2))
                        == [.loading, .ready]
                    else {
                        return
                    }
                    completionCount += 1
                    lastVisibleAppIDs =
                        model.visibleApps.map(\.id)
                    lastSelectedAppID = model.selectedApp?.id
                    reloadCompleted.fulfill()
                }
            defer {
                loadingObservation.cancel()
                readinessObservation.cancel()
            }

            XCTAssertEqual(observedLoadingStates, [false])
            XCTAssertEqual(observedReadinessStates, [.idle])
            XCTAssertEqual(completionCount, 0)
            XCTAssertTrue(lastVisibleAppIDs.isEmpty)
            XCTAssertNil(lastSelectedAppID)

            model.reload()
            await fulfillment(
                of: [reloadCompleted],
                timeout:
                    AppVisibilityReloadWatchdogPolicy
                        .eventDelivery
            )

            XCTAssertFalse(model.isLoading)
            XCTAssertEqual(model.inventoryReadiness, .ready)
            XCTAssertEqual(
                observedLoadingStates,
                [false, true, false],
                "unmetCondition=singleSearchableAppInventoryLoadingTransition "
                    + "finalLoadingStates=\(observedLoadingStates) "
                    + "finalVisibleAppIDs=\(lastVisibleAppIDs) "
                    + "finalSelectedAppID=\(lastSelectedAppID ?? "nil")"
            )
            XCTAssertEqual(
                observedReadinessStates,
                [.idle, .loading, .ready]
            )
            XCTAssertEqual(completionCount, 1)
            XCTAssertEqual(lastVisibleAppIDs, ["com.xxx.test"])
            XCTAssertEqual(lastSelectedAppID, "com.xxx.test")
            XCTAssertEqual(model.visibleApps.map(\.id), ["com.xxx.test"])
            XCTAssertEqual(model.selectedApp?.id, "com.xxx.test")
        }
    }
}
