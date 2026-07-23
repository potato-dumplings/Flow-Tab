import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    func testBoundedImageCacheStoresAndClearsImages() {
        let cache = BoundedImageCache(countLimit: 4, totalCostLimit: 1_024 * 1_024)
        let image = makeColorImage(color: .systemBlue)

        cache.insert(image, forKey: "mail")

        XCTAssertNotNil(cache.image(forKey: "mail"))

        cache.removeAll()

        XCTAssertNil(cache.image(forKey: "mail"))
    }

    func testBoundedImageCacheHandlesImagesWithoutBitmapRepresentations() {
        let cache = BoundedImageCache(countLimit: 4, totalCostLimit: 1_024 * 1_024)
        let vectorOnlyImage = NSImage(size: NSSize(width: 19.2, height: 7.8))

        cache.insert(vectorOnlyImage, forKey: "vector")

        XCTAssertNotNil(cache.image(forKey: "vector"))
    }

    func testAppIconProviderCachesResolvedIconsAndMemoizesMissingApps() {
        let cache = BoundedImageCache(countLimit: 8, totalCostLimit: 1_024 * 1_024)
        var requestedAppIDs: [String] = []
        var requestedIconPaths: [String] = []
        let provider = AppIconProvider(
            cache: cache,
            applicationURLProvider: { appID in
                requestedAppIDs.append(appID)
                if appID == "com.example.present" {
                    return URL(fileURLWithPath: "/Applications/Present.app")
                }
                return nil
            },
            fileIconProvider: { path in
                requestedIconPaths.append(path)
                return self.makeColorImage(color: .systemGreen)
            }
        )

        let presentApp = AppSwitchCandidate(
            id: "com.example.present",
            displayName: "Present",
            groupID: "present",
            lastActiveAt: 10,
            windows: []
        )
        let missingApp = AppSwitchCandidate(
            id: "com.example.missing",
            displayName: "Missing",
            groupID: "missing",
            lastActiveAt: 5,
            windows: []
        )

        let firstIcon = provider.icon(for: presentApp, context: nil)
        let secondIcon = provider.icon(for: presentApp, context: nil)

        XCTAssertNotNil(firstIcon)
        if let firstIcon, let secondIcon {
            XCTAssertTrue(firstIcon === secondIcon)
        } else {
            XCTFail("Expected cached icon for present app")
        }
        XCTAssertEqual(requestedAppIDs.filter { $0 == "com.example.present" }.count, 1)
        XCTAssertEqual(requestedIconPaths, ["/Applications/Present.app"])

        XCTAssertNil(provider.icon(for: missingApp, context: nil))
        XCTAssertNil(provider.icon(for: missingApp, context: nil))
        XCTAssertEqual(requestedAppIDs.filter { $0 == "com.example.missing" }.count, 1)
    }

    func testAppIconProviderPrefersPublishedDockIconResourceWithinAppBundle() throws {
        try withPublishedDockIconFixture { fixture in
            let provider = AppIconProvider(
                applicationURLProvider: { requestedAppID in
                    XCTAssertEqual(requestedAppID, fixture.appID)
                    return fixture.appURL
                },
                fileIconProvider: { _ in fixture.fallbackIcon }
            )
            let app = AppSwitchCandidate(
                id: fixture.appID,
                displayName: "Published Icon",
                groupID: fixture.appID,
                lastActiveAt: 1,
                windows: []
            )

            let icon = try XCTUnwrap(provider.icon(for: app, context: nil))

            XCTAssertEqual(sampledRGB(icon), sampledRGB(fixture.customIcon))
        }
    }

    func testAppIconProviderRejectsPublishedIconIntentsOutsideResourceBoundary() {
        let appURL = URL(fileURLWithPath: "/Applications/Boundary.app", isDirectory: true)
        let resourceBoundary = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let fallbackIcon = makeColorImage(color: .systemGreen)

        for invalidIntent in ["../Outside.png", "/tmp/Outside.png"] {
            var requestedResourceURLs: [URL] = []
            let provider = AppIconProvider(
                fileIconProvider: { _ in fallbackIcon },
                resourceIntentProvider: { _ in invalidIntent },
                applicationResourceURLProvider: { _ in resourceBoundary },
                resourceIconProvider: { url in
                    requestedResourceURLs.append(url)
                    return self.makeColorImage(color: .systemPurple)
                }
            )

            let icon = provider.icon(
                appID: "com.example.boundary",
                bundleIdentifier: "com.example.boundary",
                bundleURL: appURL
            )

            XCTAssertTrue(icon === fallbackIcon)
            XCTAssertTrue(requestedResourceURLs.isEmpty)
        }
    }

    func testAppIconProviderChangesCachedIconWhenPublishedResourceIntentChanges() throws {
        let appURL = URL(fileURLWithPath: "/Applications/ChangingIcon.app", isDirectory: true)
        let resourceBoundary = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let firstIcon = makeColorImage(color: .systemPurple)
        let secondIcon = makeColorImage(color: .systemOrange)
        var resourceIntent = "First.png"
        var requestedResourceNames: [String] = []
        let provider = AppIconProvider(
            resourceIntentProvider: { _ in resourceIntent },
            applicationResourceURLProvider: { _ in resourceBoundary },
            resourceIconProvider: { url in
                requestedResourceNames.append(url.lastPathComponent)
                return url.lastPathComponent == "First.png" ? firstIcon : secondIcon
            }
        )

        let firstResolution = try XCTUnwrap(provider.icon(
            appID: "com.example.changing-icon",
            bundleIdentifier: "com.example.changing-icon",
            bundleURL: appURL
        ))
        let cachedFirstResolution = try XCTUnwrap(provider.icon(
            appID: "com.example.changing-icon",
            bundleIdentifier: "com.example.changing-icon",
            bundleURL: appURL
        ))
        resourceIntent = "Second.png"
        let secondResolution = try XCTUnwrap(provider.icon(
            appID: "com.example.changing-icon",
            bundleIdentifier: "com.example.changing-icon",
            bundleURL: appURL
        ))

        XCTAssertTrue(firstResolution === firstIcon)
        XCTAssertTrue(cachedFirstResolution === firstIcon)
        XCTAssertTrue(secondResolution === secondIcon)
        XCTAssertEqual(requestedResourceNames, ["First.png", "Second.png"])
    }

    @MainActor
    func testHomeAppIconProviderUsesSharedPublishedDockIconResolution() throws {
        try withPublishedDockIconFixture { fixture in
            let summary = RuntimeHomeAppSummary(
                appID: fixture.appID,
                displayName: "Published Icon",
                groupID: fixture.appID,
                lastActiveAt: 1,
                windowCount: 1,
                pid: 1,
                bundleIdentifier: fixture.appID,
                bundleURL: fixture.appURL
            )

            let icon = HomeAppIconProvider.icon(for: summary)

            XCTAssertEqual(sampledRGB(icon), sampledRGB(fixture.customIcon))
        }
    }

    func testRuntimeWindowListSupplementerIncludesLargeOnScreenCGWindowsWhenAXMissesThem() {
        let mergedEntries = RuntimeWindowMappingTestSupport.appendOffSpaceCGWindows(
            entries: [
                .init(
                    windowID: "ax:18405:0",
                    title: "百度一下，你就知道 - Google Chrome - test1",
                    isMinimized: false,
                    cgWindowID: 240001
                ),
                .init(
                    windowID: "ax:18405:1",
                    title: "百度一下，你就知道 - Google Chrome - test2",
                    isMinimized: false,
                    cgWindowID: 240002
                ),
                .init(
                    windowID: "ax:18405:2",
                    title: "百度一下，你就知道 - Google Chrome - test3",
                    isMinimized: false,
                    cgWindowID: 240003
                ),
                .init(
                    windowID: "ax:18405:3",
                    title: "百度一下，你就知道 - Google Chrome - test4",
                    isMinimized: false,
                    cgWindowID: 240004
                )
            ],
            appName: "Google Chrome",
            pid: 18405,
            allCGWindows: [
                .init(
                    id: 240001,
                    title: "百度一下，你就知道 - Google Chrome - test1",
                    bounds: CGRect(x: 0, y: 38, width: 1_728, height: 1_079),
                    isOnscreen: true
                ),
                .init(
                    id: 240002,
                    title: "百度一下，你就知道 - Google Chrome - test2",
                    bounds: CGRect(x: 20, y: 58, width: 1_728, height: 1_079),
                    isOnscreen: true
                ),
                .init(
                    id: 240003,
                    title: "百度一下，你就知道 - Google Chrome - test3",
                    bounds: CGRect(x: 40, y: 78, width: 1_728, height: 1_079),
                    isOnscreen: true
                ),
                .init(
                    id: 240004,
                    title: "百度一下，你就知道 - Google Chrome - test4",
                    bounds: CGRect(x: 60, y: 98, width: 1_728, height: 1_079),
                    isOnscreen: true
                ),
                .init(
                    id: 240005,
                    title: "百度一下，你就知道 - Google Chrome - test5",
                    bounds: CGRect(x: 0, y: 38, width: 1_728, height: 1_079),
                    isOnscreen: true
                )
            ],
            matchedCGWindowIDs: Set<CGWindowID>([240001, 240002, 240003, 240004])
        )

        XCTAssertEqual(mergedEntries.count, 5)
        XCTAssertEqual(mergedEntries.last?.windowID, "cg:18405:240005")
        XCTAssertEqual(mergedEntries.last?.title, "百度一下，你就知道 - Google Chrome - test5")
    }

}

private extension FlowTabPriorityCoverageTests {
    struct PublishedDockIconFixture {
        let appID: String
        let appURL: URL
        let customIcon: NSImage
        let fallbackIcon: NSImage
    }

    func withPublishedDockIconFixture(
        perform assertions: (PublishedDockIconFixture) throws -> Void
    ) throws {
        let appID = "com.example.published-dock-icon.\(UUID().uuidString)"
        let resourceName = "PublishedDockIcon.png"
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowtab-app-icon-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appURL = fixtureRoot.appendingPathComponent("PublishedIcon.app", isDirectory: true)
        let resourcesURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        let infoPlistURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        let customIcon = makeColorImage(color: .systemPurple)
        let fallbackIcon = makeColorImage(color: .systemGreen)

        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": appID,
            "CFBundleName": "Published Icon",
            "CFBundlePackageType": "APPL"
        ]
        try PropertyListSerialization.data(
            fromPropertyList: infoPlist,
            format: .xml,
            options: 0
        ).write(to: infoPlistURL)
        try pngData(for: customIcon).write(to: resourcesURL.appendingPathComponent(resourceName))

        let preferenceKey = "DockIconResourceName" as CFString
        let preferenceDomain = appID as CFString
        CFPreferencesSetAppValue(preferenceKey, resourceName as CFString, preferenceDomain)
        XCTAssertTrue(CFPreferencesAppSynchronize(preferenceDomain))
        defer {
            CFPreferencesSetAppValue(preferenceKey, nil, preferenceDomain)
            CFPreferencesAppSynchronize(preferenceDomain)
            try? FileManager.default.removeItem(at: fixtureRoot)
        }

        try assertions(PublishedDockIconFixture(
            appID: appID,
            appURL: appURL,
            customIcon: customIcon,
            fallbackIcon: fallbackIcon
        ))
    }

    func pngData(for image: NSImage) throws -> Data {
        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    func sampledRGB(_ image: NSImage) -> [Int] {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let color = bitmap.colorAt(
                x: max(0, bitmap.pixelsWide / 2),
                y: max(0, bitmap.pixelsHigh / 2)
            )?.usingColorSpace(.deviceRGB)
        else {
            return []
        }

        return [color.redComponent, color.greenComponent, color.blueComponent].map {
            Int(($0 * 255).rounded())
        }
    }
}
