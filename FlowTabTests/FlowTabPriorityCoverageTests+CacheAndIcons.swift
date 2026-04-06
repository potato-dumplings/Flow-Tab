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

}
