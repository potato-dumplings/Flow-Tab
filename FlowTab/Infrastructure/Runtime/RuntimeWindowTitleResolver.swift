import Foundation

func normalizedRuntimeWindowTitle(_ title: String?) -> String? {
    guard let title else { return nil }
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

enum RuntimeWindowTitleResolver {
    static func titleLooksLikeAppNameFallback(_ title: String?, appName: String) -> Bool {
        guard let normalizedTitle = normalizedRuntimeWindowTitle(title) else { return false }
        guard let normalizedAppName = normalizedRuntimeWindowTitle(appName) else { return false }
        return normalizedTitle.caseInsensitiveCompare(normalizedAppName) == .orderedSame
    }

    static func supplementalCGWindowTitle(
        appName: String,
        cgWindow: RuntimeCGWindowEntry
    ) -> String {
        normalizedRuntimeWindowTitle(cgWindow.title)
            ?? normalizedRuntimeWindowTitle(appName)
            ?? appName
    }

    static func stableWindowTitle(
        sourceTitle: String?,
        matchedCGTitle: String?,
        appName: String,
        fallbackIndex: Int,
        refreshedAXTitle: String? = nil
    ) -> String {
        let normalizedSourceTitle = normalizedRuntimeWindowTitle(sourceTitle)
        let normalizedMatchedCGTitle = normalizedRuntimeWindowTitle(matchedCGTitle)
        let normalizedRefreshedAXTitle = normalizedRuntimeWindowTitle(refreshedAXTitle)
        let sourceLooksLikeAppNameFallback = titleLooksLikeAppNameFallback(
            normalizedSourceTitle,
            appName: appName
        )

        if !sourceLooksLikeAppNameFallback, let normalizedSourceTitle {
            return normalizedSourceTitle
        }

        if let normalizedMatchedCGTitle,
            !titleLooksLikeAppNameFallback(normalizedMatchedCGTitle, appName: appName)
        {
            return normalizedMatchedCGTitle
        }

        if let normalizedRefreshedAXTitle,
            !titleLooksLikeAppNameFallback(normalizedRefreshedAXTitle, appName: appName)
        {
            RuntimeLog.info(.ax, "\(appName) untitled[\(fallbackIndex)] recovered-from-ax")
            return normalizedRefreshedAXTitle
        }

        if let normalizedMatchedCGTitle {
            return normalizedMatchedCGTitle
        }
        if let normalizedRefreshedAXTitle {
            return normalizedRefreshedAXTitle
        }
        if let normalizedSourceTitle {
            return normalizedSourceTitle
        }

        RuntimeLog.info(.ax, "\(appName) untitled[\(fallbackIndex)] use app-name fallback")
        return appName
    }
}
