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
    private enum CacheKeyPrefix {
        static let bundle = "bundle"
        static let publishedResource = "published-resource"
    }

    private static let dockIconResourceNamePreferenceKey = "DockIconResourceName"

    private let cache: BoundedImageCache
    private let applicationURLProvider: (String) -> URL?
    private let fileIconProvider: (String) -> NSImage
    private let resourceIntentProvider: (String) -> String?
    private let applicationResourceURLProvider: (URL) -> URL?
    private let resourceIconProvider: (URL) -> NSImage?
    private var applicationURLsByLookupKey: [String: URL] = [:]
    private var missingApplicationLookupKeys: Set<String> = []

    init(
        cache: BoundedImageCache = BoundedImageCache(
            countLimit: 256,
            totalCostLimit: 64 * 1_024 * 1_024
        ),
        applicationURLProvider: ((String) -> URL?)? = nil,
        fileIconProvider: ((String) -> NSImage)? = nil,
        resourceIntentProvider: ((String) -> String?)? = nil,
        applicationResourceURLProvider: ((URL) -> URL?)? = nil,
        resourceIconProvider: ((URL) -> NSImage?)? = nil
    ) {
        self.cache = cache
        self.applicationURLProvider = applicationURLProvider
            ?? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        self.fileIconProvider = fileIconProvider
            ?? { NSWorkspace.shared.icon(forFile: $0) }
        self.resourceIntentProvider = resourceIntentProvider ?? { bundleIdentifier in
            CFPreferencesCopyAppValue(
                Self.dockIconResourceNamePreferenceKey as CFString,
                bundleIdentifier as CFString
            ) as? String
        }
        self.applicationResourceURLProvider = applicationResourceURLProvider
            ?? { Bundle(url: $0)?.resourceURL }
        self.resourceIconProvider = resourceIconProvider
            ?? { NSImage(contentsOf: $0) }
    }

    func icon(for app: AppSwitchCandidate, context: RuntimeAppContext?) -> NSImage? {
        icon(
            appID: app.id,
            bundleIdentifier: context?.runningApp.bundleIdentifier,
            bundleURL: context?.runningApp.bundleURL,
            runtimeIcon: context?.runningApp.icon
        )
    }

    func icon(
        appID: String,
        bundleIdentifier: String?,
        bundleURL: URL?,
        runtimeIcon: NSImage? = nil
    ) -> NSImage? {
        let preferenceDomain = resolvedPreferenceDomain(
            appID: appID,
            bundleIdentifier: bundleIdentifier,
            bundleURL: bundleURL
        )
        let resourceIntent = resourceIntentProvider(preferenceDomain)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var resolvedApplicationURL = bundleURL?.standardizedFileURL
        if let resourceIntent, !resourceIntent.isEmpty {
            resolvedApplicationURL = resolvedApplicationURL ?? applicationURL(
                appID: appID,
                bundleIdentifier: bundleIdentifier
            )
            if let resolvedApplicationURL,
               let resourceURL = publishedResourceURL(
                   intent: resourceIntent,
                   applicationURL: resolvedApplicationURL
               ),
               let icon = cachedOrLoadedPublishedIcon(
                   at: resourceURL,
                   preferenceDomain: preferenceDomain
               ) {
                return icon
            }
        }

        if let runtimeIcon {
            return runtimeIcon
        }

        resolvedApplicationURL = resolvedApplicationURL ?? applicationURL(
            appID: appID,
            bundleIdentifier: bundleIdentifier
        )
        guard let resolvedApplicationURL else {
            return nil
        }

        let cacheKey = "\(CacheKeyPrefix.bundle):\(resolvedApplicationURL.path)"
        if let cached = cache.image(forKey: cacheKey) {
            return cached
        }

        let icon = fileIconProvider(resolvedApplicationURL.path)
        cache.insert(icon, forKey: cacheKey)
        return icon
    }

    private func resolvedPreferenceDomain(
        appID: String,
        bundleIdentifier: String?,
        bundleURL: URL?
    ) -> String {
        if let bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }
        if let bundleIdentifier = bundleURL.flatMap({ Bundle(url: $0)?.bundleIdentifier }),
           !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }
        return appID
    }

    private func applicationURL(appID: String, bundleIdentifier: String?) -> URL? {
        let lookupIdentifiers = [bundleIdentifier, appID]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { identifiers, identifier in
                if !identifiers.contains(identifier) {
                    identifiers.append(identifier)
                }
            }
        let lookupKey = lookupIdentifiers.joined(separator: "|")

        if let cachedURL = applicationURLsByLookupKey[lookupKey] {
            return cachedURL
        }
        if missingApplicationLookupKeys.contains(lookupKey) {
            return nil
        }

        for identifier in lookupIdentifiers {
            if let url = applicationURLProvider(identifier)?.standardizedFileURL {
                applicationURLsByLookupKey[lookupKey] = url
                return url
            }
        }

        missingApplicationLookupKeys.insert(lookupKey)
        return nil
    }

    private func publishedResourceURL(intent: String, applicationURL: URL) -> URL? {
        guard !(intent as NSString).isAbsolutePath else { return nil }
        guard let resourceBoundary = applicationResourceURLProvider(applicationURL) else {
            return nil
        }

        let canonicalBoundary = resourceBoundary
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let canonicalCandidate = resourceBoundary
            .appendingPathComponent(intent)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard canonicalCandidate.isStrictDescendant(of: canonicalBoundary) else {
            return nil
        }
        return canonicalCandidate
    }

    private func cachedOrLoadedPublishedIcon(
        at resourceURL: URL,
        preferenceDomain: String
    ) -> NSImage? {
        let cacheKey = "\(CacheKeyPrefix.publishedResource):\(preferenceDomain):\(resourceURL.path)"
        if let cached = cache.image(forKey: cacheKey) {
            return cached
        }
        guard let icon = resourceIconProvider(resourceURL) else {
            return nil
        }
        cache.insert(icon, forKey: cacheKey)
        return icon
    }
}

private extension URL {
    func isStrictDescendant(of boundary: URL) -> Bool {
        let boundaryComponents = boundary.pathComponents
        let candidateComponents = pathComponents
        guard candidateComponents.count > boundaryComponents.count else { return false }
        return Array(candidateComponents.prefix(boundaryComponents.count)) == boundaryComponents
    }
}
