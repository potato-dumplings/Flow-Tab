import AppKit
import Foundation
import FlowTabCore

final class BoundedImageCache {
    private let storage = NSCache<NSString, NSImage>()

    init(countLimit: Int, totalCostLimit: Int) {
        storage.countLimit = countLimit
        storage.totalCostLimit = totalCostLimit
    }

    func image(forKey key: String) -> NSImage? {
        storage.object(forKey: key as NSString)
    }

    func insert(_ image: NSImage, forKey key: String) {
        storage.setObject(
            image,
            forKey: key as NSString,
            cost: image.estimatedByteCost
        )
    }

    func removeAll() {
        storage.removeAllObjects()
    }
}

private extension NSImage {
    var estimatedByteCost: Int {
        if let bitmap = representations.first(where: { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }) {
            return bitmap.pixelsWide * bitmap.pixelsHigh * 4
        }
        let width = max(1, Int(ceil(size.width)))
        let height = max(1, Int(ceil(size.height)))
        return width * height * 4
    }
}

final class AppIconProvider {
    private let cache: BoundedImageCache
    private let applicationURLProvider: (String) -> URL?
    private let fileIconProvider: (String) -> NSImage
    private var missingAppIDs: Set<String> = []

    init(
        cache: BoundedImageCache = BoundedImageCache(
            countLimit: 256,
            totalCostLimit: 64 * 1_024 * 1_024
        ),
        applicationURLProvider: ((String) -> URL?)? = nil,
        fileIconProvider: ((String) -> NSImage)? = nil
    ) {
        self.cache = cache
        self.applicationURLProvider = applicationURLProvider
            ?? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        self.fileIconProvider = fileIconProvider
            ?? { NSWorkspace.shared.icon(forFile: $0) }
    }

    func icon(for app: AppSwitchCandidate, context: RuntimeAppContext?) -> NSImage? {
        if let cached = cache.image(forKey: app.id) {
            return cached
        }
        if missingAppIDs.contains(app.id) {
            return nil
        }

        if let runtimeIcon = context?.runningApp.icon {
            cache.insert(runtimeIcon, forKey: app.id)
            return runtimeIcon
        }

        guard let url = applicationURLProvider(app.id) else {
            missingAppIDs.insert(app.id)
            return nil
        }

        let icon = fileIconProvider(url.path)
        cache.insert(icon, forKey: app.id)
        return icon
    }
}
