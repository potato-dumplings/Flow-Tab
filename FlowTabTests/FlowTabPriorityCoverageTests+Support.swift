import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    func commitScenarioApps() -> [AppSwitchCandidate] {
        [
            AppSwitchCandidate(
                id: "com.example.mail",
                displayName: "Mail",
                groupID: "office",
                lastActiveAt: 300,
                windows: [
                    WindowCandidate(id: "mail-old", title: "Inbox", isMinimized: false, lastActiveAt: 200),
                    WindowCandidate(id: "mail-new", title: "Draft", isMinimized: false, lastActiveAt: 350)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.code",
                displayName: "Code",
                groupID: "dev",
                lastActiveAt: 290,
                windows: [
                    WindowCandidate(id: "code-1", title: "FlowTab", isMinimized: false, lastActiveAt: 290)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.browser",
                displayName: "Browser",
                groupID: "web",
                lastActiveAt: 280,
                windows: [
                    WindowCandidate(id: "browser-1", title: "Docs", isMinimized: false, lastActiveAt: 280)
                ]
            )
        ]
    }
    func searchScenarioApps() -> [AppSwitchCandidate] {
        [
            AppSwitchCandidate(
                id: "com.example.mail",
                displayName: "Mail",
                groupID: "office",
                lastActiveAt: 300,
                windows: [
                    WindowCandidate(id: "mail-1", title: "Inbox", isMinimized: false, lastActiveAt: 300),
                    WindowCandidate(id: "mail-2", title: "Draft", isMinimized: false, lastActiveAt: 280)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.code",
                displayName: "Code",
                groupID: "dev",
                lastActiveAt: 290,
                windows: [
                    WindowCandidate(id: "code-1", title: "FlowTab", isMinimized: false, lastActiveAt: 290),
                    WindowCandidate(id: "code-2", title: "README", isMinimized: false, lastActiveAt: 270)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.browser",
                displayName: "Browser",
                groupID: "web",
                lastActiveAt: 280,
                windows: [
                    WindowCandidate(id: "browser-1", title: "Docs", isMinimized: false, lastActiveAt: 280)
                ]
            )
        ]
    }
    func searchWrapScenarioApps() -> [AppSwitchCandidate] {
        return (1...10).map { item in
            let suffix = String(format: "%02d", item)
            let rank = 501 - item
            return AppSwitchCandidate(
                id: "com.flowtab.mock.wrap.\(suffix)",
                displayName: "Mock Wrap \(suffix)",
                groupID: "mock",
                lastActiveAt: TimeInterval(rank),
                windows: [
                    WindowCandidate(
                        id: "mock-wrap-\(suffix)-primary",
                        title: "MockWrap\(suffix)Window",
                        isMinimized: false,
                        lastActiveAt: TimeInterval(rank)
                    )
                ]
            )
        }
    }
    func terminateScenarioApps() -> [AppSwitchCandidate] {
        [
            AppSwitchCandidate(
                id: "com.example.mail",
                displayName: "Mail",
                groupID: "office",
                lastActiveAt: 300,
                windows: [
                    WindowCandidate(id: "mail-1", title: "Inbox", isMinimized: false, lastActiveAt: 300)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.code",
                displayName: "Code",
                groupID: "dev",
                lastActiveAt: 290,
                windows: [
                    WindowCandidate(id: "code-1", title: "FlowTab", isMinimized: false, lastActiveAt: 290)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.browser",
                displayName: "Browser",
                groupID: "web",
                lastActiveAt: 280,
                windows: [
                    WindowCandidate(id: "browser-1", title: "Docs", isMinimized: false, lastActiveAt: 280)
                ]
            )
        ]
    }
    func layoutScenarioApps(count: Int) -> [AppSwitchCandidate] {
        (0..<count).map { index in
            let suffix = index + 1
            return AppSwitchCandidate(
                id: "com.example.layout-\(suffix)",
                displayName: "Layout \(suffix)",
                groupID: "layout",
                lastActiveAt: TimeInterval(1_000 - index),
                windows: [
                    WindowCandidate(
                        id: "layout-window-\(suffix)",
                        title: "Window \(suffix)",
                        isMinimized: false,
                        lastActiveAt: TimeInterval(1_000 - index)
                    )
                ]
            )
        }
    }

    func manyWindowLayoutApp(windowCount: Int) -> AppSwitchCandidate {
        let windows = (0..<windowCount).map { index in
            WindowCandidate(
                id: String(format: "many-window-%02d", index),
                title: String(format: "Many Window %02d", index),
                isMinimized: false,
                lastActiveAt: TimeInterval(1_000 - index)
            )
        }
        return AppSwitchCandidate(
            id: "com.example.many-windows",
            displayName: "Many Windows",
            groupID: "layout",
            lastActiveAt: 1_000,
            windows: windows
        )
    }

    func makeRuntimeAppContext(
        appID: String,
        runningApp: NSRunningApplication,
        windows: [WindowCandidate],
        lastConfirmationSource: WindowBindingConfirmationSource? = nil
    ) -> RuntimeAppContext {
        let windowsByID = Dictionary(
            uniqueKeysWithValues: windows.map { window in
                (
                    window.id,
                    RuntimeWindowContext(
                        id: window.id,
                        title: window.title,
                        isMinimized: window.isMinimized,
                        ownerPID: runningApp.processIdentifier,
                        cgWindowID: nil,
                        inferredTitleBarStyle: nil,
                        lastConfirmationSource: lastConfirmationSource
                    )
                )
            }
        )
        return RuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            windowsByID: windowsByID
        )
    }
    func makeCurrentAppWindowProjectionService(
        appID: String,
        runningApp: NSRunningApplication,
        windows: [WindowCandidate],
        generatedAt: TimeInterval = 10
    ) -> RecordingRuntimeSnapshotService {
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: runningApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: generatedAt,
            windows: windows
        )
        let snapshot = RuntimeHomeAppSnapshot(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: candidate.displayName,
                groupID: candidate.groupID,
                lastActiveAt: candidate.lastActiveAt,
                windowCount: windows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: candidate,
            context: makeRuntimeAppContext(appID: appID, runningApp: runningApp, windows: windows)
        )
        return RecordingRuntimeSnapshotService(
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    homeAppSnapshot: snapshot,
                    freshness: RuntimeProjectionFreshness(
                        generatedAt: generatedAt,
                        sourceGeneration: RuntimeReadModelGeneration(projection: 1),
                        dirtyAppIDs: [],
                        dirtyPIDs: [],
                        dirtyCGWindowIDs: [],
                        pendingRepairScopes: [],
                        isCompleteForScope: true
                    )
                )
            ]
        )
    }
    func makeCurrentAppWindowProjectionService(
        appID: String,
        candidate: AppSwitchCandidate,
        context: RuntimeAppContext,
        generatedAt: TimeInterval = 10
    ) -> RecordingRuntimeSnapshotService {
        RecordingRuntimeSnapshotService(
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    homeAppSnapshot: RuntimeHomeAppSnapshot(
                        summary: RuntimeHomeAppSummary(
                            appID: appID,
                            displayName: candidate.displayName,
                            groupID: candidate.groupID,
                            lastActiveAt: candidate.lastActiveAt,
                            windowCount: candidate.windows.count,
                            pid: context.runningApp.processIdentifier
                        ),
                        candidate: candidate,
                        context: context
                    ),
                    freshness: RuntimeProjectionFreshness(
                        generatedAt: generatedAt,
                        sourceGeneration: RuntimeReadModelGeneration(projection: 1),
                        dirtyAppIDs: [],
                        dirtyPIDs: [],
                        dirtyCGWindowIDs: [],
                        pendingRepairScopes: [],
                        isCompleteForScope: true
                    )
                )
            ]
        )
    }
    @MainActor
    func makeAppSwitcherProjectionModel(
        app: AppSwitchCandidate,
        context: RuntimeAppContext,
        generatedAt: TimeInterval = 10
    ) -> (model: LiveSwitcherModel, snapshotService: RecordingRuntimeSnapshotService) {
        let snapshotService = RecordingRuntimeSnapshotService(
            appSwitcherApps: [app],
            contextsByID: [app.id: context],
            generatedAt: generatedAt
        )
        return (
            model: LiveSwitcherModel(snapshotService: snapshotService),
            snapshotService: snapshotService
        )
    }
    func makeIsolatedUserDefaults() -> UserDefaults? {
        let suiteName = "FlowTabPriorityCoverageTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated user defaults suite")
            return nil
        }
        userDefaults.set(suiteName, forKey: "FlowTabPriorityCoverageTestsSuiteName")
        return userDefaults
    }
    func clearIsolatedUserDefaults(_ userDefaults: UserDefaults) {
        guard let suiteName = userDefaults.string(forKey: "FlowTabPriorityCoverageTestsSuiteName") else {
            return
        }
        userDefaults.removePersistentDomain(forName: suiteName)
    }
    func restoreUserDefaultsValue(
        _ value: Any?,
        forKey key: String,
        userDefaults: UserDefaults
    ) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }
    func enableCurrentAppInSwitcherForTesting() -> () -> Void {
        let defaults = UserDefaults.standard
        let previousShowInCommandTab = defaults.object(forKey: AppPreferenceKeys.showInCommandTab)
        let previousHiddenAppIDs = defaults.object(forKey: AppPreferenceKeys.hiddenAppIDs)
        let currentAppID = AppVisibilityPreferencesStore.currentAppID()

        defaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        var hiddenAppIDs = Set(defaults.stringArray(forKey: AppPreferenceKeys.hiddenAppIDs) ?? [])
        if let normalizedCurrentAppID = AppVisibilityFilter.normalizedAppID(currentAppID) {
            hiddenAppIDs.remove(normalizedCurrentAppID)
        }
        defaults.set(
            AppVisibilityFilter.normalizedHiddenAppIDs(Array(hiddenAppIDs)),
            forKey: AppPreferenceKeys.hiddenAppIDs
        )

        return {
            self.restoreUserDefaultsValue(
                previousShowInCommandTab,
                forKey: AppPreferenceKeys.showInCommandTab,
                userDefaults: defaults
            )
            self.restoreUserDefaultsValue(
                previousHiddenAppIDs,
                forKey: AppPreferenceKeys.hiddenAppIDs,
                userDefaults: defaults
            )
        }
    }
    func withTemporarySearchPreferences(
        enabled: Bool,
        defaultScope: SwitcherSearchScope,
        perform body: () async throws -> Void
    ) async rethrows {
        let defaults = UserDefaults.standard
        let previousEnabled = defaults.object(forKey: AppPreferenceKeys.searchEnabled)
        let previousScope = defaults.object(forKey: AppPreferenceKeys.searchDefaultScope)
        defaults.set(enabled, forKey: AppPreferenceKeys.searchEnabled)
        defaults.set(defaultScope.rawValue, forKey: AppPreferenceKeys.searchDefaultScope)
        defer {
            restoreUserDefaultsValue(
                previousEnabled,
                forKey: AppPreferenceKeys.searchEnabled,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousScope,
                forKey: AppPreferenceKeys.searchDefaultScope,
                userDefaults: defaults
            )
        }
        try await body()
    }
    func withTemporaryWindowLayerAutoEnterDelay(
        _ delay: Double,
        perform body: () async throws -> Void
    ) async rethrows {
        let defaults = UserDefaults.standard
        let previousDelay = defaults.object(forKey: AppPreferenceKeys.windowLayerAutoEnterDelay)
        defaults.set(delay, forKey: AppPreferenceKeys.windowLayerAutoEnterDelay)
        defer {
            restoreUserDefaultsValue(
                previousDelay,
                forKey: AppPreferenceKeys.windowLayerAutoEnterDelay,
                userDefaults: defaults
            )
        }
        try await body()
    }
    func makeCarbonHotkeyEvent(
        kind: UInt32,
        signature: OSType,
        id: UInt32,
        includeHotkeyPayload: Bool
    ) -> EventRef {
        var eventRef: EventRef?
        let createStatus = CreateEvent(
            nil,
            OSType(kEventClassKeyboard),
            kind,
            EventTime(0),
            EventAttributes(kEventAttributeNone),
            &eventRef
        )
        XCTAssertEqual(createStatus, noErr)
        guard let eventRef else {
            fatalError("Failed to create Carbon event for tests")
        }

        if includeHotkeyPayload {
            var hotkeyID = EventHotKeyID(signature: signature, id: id)
            let payloadStatus = withUnsafePointer(to: &hotkeyID) { pointer in
                SetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    MemoryLayout<EventHotKeyID>.size,
                    pointer
                )
            }
            XCTAssertEqual(payloadStatus, noErr)
        }
        return eventRef
    }
    static func makeKeyDownEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ) else {
            fatalError("Failed to create key event for tests")
        }
        return event
    }
    static func makeFlagsChangedEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ) else {
            fatalError("Failed to create flagsChanged event for tests")
        }
        return event
    }
    func makeColorImage(
        color: NSColor,
        size: NSSize = NSSize(width: 48, height: 48)
    ) -> NSImage {
        let cgImage = makeSolidPreviewCGImage(
            color: color,
            size: CGSize(width: size.width, height: size.height)
        )
        return NSImage(cgImage: cgImage, size: size)
    }
    func makeSolidPreviewCGImage(
        color: NSColor,
        size: CGSize = CGSize(width: 180, height: 120)
    ) -> CGImage {
        makePreviewCGImage(size: size) { context in
            context.setFillColor(color.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
    func makeStripedPreviewCGImage(
        size: CGSize = CGSize(width: 180, height: 120)
    ) -> CGImage {
        makePreviewCGImage(size: size) { context in
            let stripeWidth: CGFloat = 10
            var x: CGFloat = 0
            var useRed = true
            while x < size.width {
                context.setFillColor((useRed ? NSColor.systemRed : NSColor.systemBlue).cgColor)
                context.fill(CGRect(x: x, y: 0, width: stripeWidth, height: size.height))
                useRed.toggle()
                x += stripeWidth
            }
        }
    }
    func makePreviewCGImage(
        size: CGSize,
        draw: (CGContext) -> Void
    ) -> CGImage {
        guard
            let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            fatalError("Failed to create bitmap context for preview tests")
        }

        draw(context)

        guard let image = context.makeImage() else {
            fatalError("Failed to create CGImage for preview tests")
        }
        return image
    }
}
