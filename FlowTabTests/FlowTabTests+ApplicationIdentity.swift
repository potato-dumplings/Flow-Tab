import Combine
import Foundation
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabTests {
    @MainActor
    func testCurrentAppActivationPolicyProjectsIntoHiddenAppIDs() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        let currentAppID = Bundle.main.bundleIdentifier
            ?? "pid:\(ProcessInfo.processInfo.processIdentifier)"
        userDefaults.set(false, forKey: AppPreferenceKeys.showInCommandTab)
        let hiddenModel = AppVisibilityManagerModel(
            inventoryService: AppInventoryService(searchDirectories: []),
            userDefaults: userDefaults
        )
        let inventoryReady = expectation(description: "current FlowTab inventory ready")
        let readinessObservation = hiddenModel.$inventoryReadiness.sink { readiness in
            if readiness == .ready {
                inventoryReady.fulfill()
            }
        }
        defer { readinessObservation.cancel() }

        XCTAssertTrue(hiddenModel.hiddenAppIDs.contains(currentAppID))
        XCTAssertEqual(hiddenModel.hiddenCount, 1)

        hiddenModel.reload()
        await fulfillment(of: [inventoryReady], timeout: 5)
        XCTAssertEqual(
            hiddenModel.apps.first(where: { $0.id == currentAppID })?.visibilityCapability,
            .configurable
        )

        hiddenModel.setHidden(false, for: currentAppID)
        XCTAssertTrue(AppVisibilityPreferencesStore.loadShowInCommandTab(userDefaults: userDefaults))
        XCTAssertFalse(hiddenModel.hiddenAppIDs.contains(currentAppID))
        XCTAssertEqual(hiddenModel.hiddenCount, 0)

        hiddenModel.setHidden(true, for: currentAppID)
        XCTAssertFalse(AppVisibilityPreferencesStore.loadShowInCommandTab(userDefaults: userDefaults))
        XCTAssertTrue(hiddenModel.hiddenAppIDs.contains(currentAppID))
        XCTAssertEqual(hiddenModel.hiddenCount, 1)
    }

    func testAppVisibilityReconciliationStrictlyKeepsConfigurableInstalledApps() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        let currentAppID = AppVisibilityPreferencesStore.currentAppID()
        userDefaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        userDefaults.set(
            [
                " com.example.editor ",
                "com.example.menu-bar",
                "com.example.helper",
                "com.example.uninstalled",
                currentAppID
            ],
            forKey: AppPreferenceKeys.hiddenAppIDs
        )

        let result = AppVisibilityPreferencesStore.reconcileHiddenAppIDs(
            preferenceConfigurableAppIDs: ["com.example.editor", currentAppID],
            userDefaults: userDefaults
        )

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(result.hiddenAppIDs, ["com.example.editor"])
        XCTAssertEqual(
            userDefaults.stringArray(forKey: AppPreferenceKeys.hiddenAppIDs),
            ["com.example.editor"]
        )

        let stableResult = AppVisibilityPreferencesStore.reconcileHiddenAppIDs(
            preferenceConfigurableAppIDs: ["com.example.editor", currentAppID],
            userDefaults: userDefaults
        )
        XCTAssertFalse(stableResult.didChange)
        XCTAssertEqual(stableResult.hiddenAppIDs, ["com.example.editor"])
    }

    func testSystemManagedVisibilityReasonIsLocalizedInChineseAndEnglish() {
        XCTAssertEqual(
            AppStrings.text(
                .appVisibilitySystemManagedReason,
                language: .simplifiedChinese
            ),
            "该应用在安装包中声明为菜单栏或后台应用，运行方式由 macOS 管理，因此 FlowTab 无法设置其可见性。"
        )
        XCTAssertEqual(
            AppStrings.text(
                .appVisibilitySystemManagedReason,
                language: .english
            ),
            "This app declares itself as a menu bar or background app in its bundle. macOS manages how it runs, so FlowTab cannot configure its visibility."
        )
    }

    func testAppVisibilityReconciliationMergesCurrentFlowTabPolicy() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        let currentAppID = AppVisibilityPreferencesStore.currentAppID()
        userDefaults.set(false, forKey: AppPreferenceKeys.showInCommandTab)
        userDefaults.set([], forKey: AppPreferenceKeys.hiddenAppIDs)

        let result = AppVisibilityPreferencesStore.reconcileHiddenAppIDs(
            preferenceConfigurableAppIDs: [currentAppID],
            userDefaults: userDefaults
        )

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(result.hiddenAppIDs, [currentAppID])
    }

    func testAppInventoryClassifiesTopLevelApplicationBundlesAndSkipsNestedHelpers() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("FlowTabAppInventory-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        func makeApplication(
            name: String,
            bundleIdentifier: String,
            flags: [String: Any] = [:],
            parent: URL? = nil
        ) throws {
            let appURL = (parent ?? root)
                .appendingPathComponent("\(name).app", isDirectory: true)
            let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
            try fileManager.createDirectory(
                at: contentsURL,
                withIntermediateDirectories: true
            )
            var info: [String: Any] = [
                "CFBundleIdentifier": bundleIdentifier,
                "CFBundleName": name,
                "CFBundlePackageType": "APPL"
            ]
            flags.forEach { info[$0.key] = $0.value }
            let data = try PropertyListSerialization.data(
                fromPropertyList: info,
                format: .xml,
                options: 0
            )
            try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
        }

        try makeApplication(name: "Editor", bundleIdentifier: "com.example.editor")
        try makeApplication(
            name: "Menu Bar",
            bundleIdentifier: "com.example.menu-bar",
            flags: ["LSUIElement": true]
        )
        try makeApplication(
            name: "Background",
            bundleIdentifier: "com.example.background",
            flags: ["LSBackgroundOnly": true]
        )
        let editorContents = root
            .appendingPathComponent("Editor.app/Contents", isDirectory: true)
        try makeApplication(
            name: "Editor Helper",
            bundleIdentifier: "com.example.editor.helper",
            parent: editorContents.appendingPathComponent("Helpers", isDirectory: true)
        )

        let records = AppInventoryService(searchDirectories: [root]).installedApps()
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })

        XCTAssertEqual(recordsByID["com.example.editor"]?.visibilityCapability, .configurable)
        XCTAssertEqual(
            recordsByID["com.example.menu-bar"]?.visibilityCapability,
            .systemManaged(reason: .staticBundleDeclaration)
        )
        XCTAssertEqual(
            recordsByID["com.example.background"]?.visibilityCapability,
            .systemManaged(reason: .staticBundleDeclaration)
        )
        XCTAssertNil(recordsByID["com.example.editor.helper"])
    }
}
