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
