import AppKit
import ApplicationServices
import Foundation

struct TerminalPreviewStyle {
    let backgroundColor: NSColor
    let normalTextColor: NSColor
    let fontName: String?
    let fontSize: CGFloat

    static let `default` = TerminalPreviewStyle(
        backgroundColor: .black,
        normalTextColor: .white,
        fontName: nil,
        fontSize: 13
    )
}

struct TerminalTabSnapshot {
    let flatIndex: Int
    let terminalWindowID: CGWindowID?
    let windowTitle: String
    let customTitle: String
    let contents: String
    let style: TerminalPreviewStyle
}

enum TerminalScriptingSnapshotError: Error, Equatable {
    case permissionDenied
    case readFailed
    case parseFailed
}

protocol TerminalScriptingSnapshotProviding {
    func tabSnapshots(ownerPID: pid_t) -> Result<[TerminalTabSnapshot], TerminalScriptingSnapshotError>
}

struct TerminalWindowPreviewProvider: SpecialWindowPreviewProviding {
    private static let terminalBundleIdentifier = "com.apple.Terminal"

    private let adapter: any TerminalScriptingSnapshotProviding

    init(adapter: any TerminalScriptingSnapshotProviding = TerminalScriptingAdapter()) {
        self.adapter = adapter
    }

    func supports(_ request: WindowPreviewRequest) -> Bool {
        request.bundleIdentifier == Self.terminalBundleIdentifier
            || request.appID == Self.terminalBundleIdentifier
    }

    func previews(for requests: [WindowPreviewRequest]) async -> [WindowPreviewResult] {
        guard !requests.isEmpty else { return [] }
        var snapshotsByPID: [pid_t: Result<[TerminalTabSnapshot], TerminalScriptingSnapshotError>] = [:]
        return requests.map { request in
            let snapshotResult: Result<[TerminalTabSnapshot], TerminalScriptingSnapshotError>
            if let cachedResult = snapshotsByPID[request.ownerPID] {
                snapshotResult = cachedResult
            } else {
                let loadedResult = adapter.tabSnapshots(ownerPID: request.ownerPID)
                snapshotsByPID[request.ownerPID] = loadedResult
                snapshotResult = loadedResult
            }

            switch snapshotResult {
            case .success(let snapshots):
                return preview(for: request, snapshots: snapshots)
            case .failure(let error):
                return .failure(windowPreviewFailureReason(from: error))
            }
        }
    }

    private func preview(
        for request: WindowPreviewRequest,
        snapshots: [TerminalTabSnapshot]
    ) -> WindowPreviewResult {
        guard let snapshot = Self.matchingSnapshot(for: request, snapshots: snapshots) else {
            return .failure(.specialProviderUnavailable)
        }
        guard
            let image = TerminalPreviewRenderer.render(
                snapshot: snapshot,
                fallbackTitle: request.preferredTitle
            )
        else {
            return .failure(.transientSystemError)
        }
        return .success(
            image: image,
            resolvedWindowID: request.preferredCGWindowID,
            titleBarStyle: .dark,
            source: .special(appID: request.appID)
        )
    }

    private func windowPreviewFailureReason(
        from error: TerminalScriptingSnapshotError
    ) -> WindowPreviewFailureReason {
        switch error {
        case .permissionDenied:
            return .permissionDenied
        case .readFailed, .parseFailed:
            return .specialProviderUnavailable
        }
    }

    private static func matchingSnapshot(
        for request: WindowPreviewRequest,
        snapshots: [TerminalTabSnapshot]
    ) -> TerminalTabSnapshot? {
        if let preferredCGWindowID = request.preferredCGWindowID,
           let snapshot = snapshots.first(where: { $0.terminalWindowID == preferredCGWindowID }) {
            return snapshot
        }

        let normalizedTitle = request.preferredTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedTitle, !normalizedTitle.isEmpty {
            let matches = snapshots.filter { snapshot in
                [snapshot.windowTitle, snapshot.customTitle].contains {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedTitle
                }
            }
            if matches.count == 1 {
                return matches[0]
            }
        }

        let handleIDs = [request.activationHandleID, request.windowID]
            .compactMap { $0 }
        for handleID in handleIDs {
            if let flatIndex = AXWindowInspector.windowIndex(
                from: handleID,
                expectedPID: request.ownerPID
            ), let snapshot = snapshots.first(where: { $0.flatIndex == flatIndex }) {
                return snapshot
            }
        }

        if snapshots.count == 1 {
            return snapshots[0]
        }
        RuntimeLog.debug(
            .preview,
            "terminal preview match failed pid=\(request.ownerPID) windowID=\(request.windowID) activationHandle=\(request.activationHandleID ?? "nil") snapshots=\(snapshots.count)"
        )
        return nil
    }
}

struct TerminalScriptingAdapter: TerminalScriptingSnapshotProviding {
    func tabSnapshots(ownerPID: pid_t) -> Result<[TerminalTabSnapshot], TerminalScriptingSnapshotError> {
        guard NSRunningApplication(processIdentifier: ownerPID) != nil else {
            return .failure(.readFailed)
        }
        guard let script = NSAppleScript(source: Self.scriptSource) else {
            return .failure(.readFailed)
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            RuntimeLog.debug(.preview, "terminal preview script failed pid=\(ownerPID)")
            if Self.isAutomationPermissionDenied(errorInfo) {
                return .failure(.permissionDenied)
            }
            return .failure(.readFailed)
        }
        guard let snapshots = Self.parseTabSnapshots(from: descriptor) else {
            return .failure(.parseFailed)
        }
        return .success(snapshots)
    }

    private static func parseTabSnapshots(
        from descriptor: NSAppleEventDescriptor
    ) -> [TerminalTabSnapshot]? {
        guard descriptor.numberOfItems > 0 else { return [] }
        var snapshots: [TerminalTabSnapshot] = []
        snapshots.reserveCapacity(descriptor.numberOfItems)

        for itemIndex in 1...descriptor.numberOfItems {
            guard let item = descriptor.atIndex(itemIndex), item.numberOfItems >= 6 else {
                return nil
            }
            let terminalWindowID = item.numberOfItems >= 7
                ? cgWindowID(from: item.atIndex(7))
                : nil
            let windowTitle = item.numberOfItems >= 8
                ? string(from: item.atIndex(8)) ?? ""
                : ""
            let style = TerminalPreviewStyle(
                backgroundColor: color(from: item.atIndex(5), fallback: .black),
                normalTextColor: color(from: item.atIndex(6), fallback: .white),
                fontName: string(from: item.atIndex(3)),
                fontSize: CGFloat(max(1, int(from: item.atIndex(4), fallback: 13)))
            )
            snapshots.append(
                TerminalTabSnapshot(
                    flatIndex: snapshots.count,
                    terminalWindowID: terminalWindowID,
                    windowTitle: windowTitle,
                    customTitle: string(from: item.atIndex(1)) ?? "",
                    contents: string(from: item.atIndex(2)) ?? "",
                    style: style
                )
            )
        }

        return snapshots
    }

    private static func isAutomationPermissionDenied(_ errorInfo: NSDictionary) -> Bool {
        let errorNumber = (errorInfo["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue
        return errorNumber == -1743
    }

    private static func string(from descriptor: NSAppleEventDescriptor?) -> String? {
        descriptor?.stringValue
    }

    private static func int(
        from descriptor: NSAppleEventDescriptor?,
        fallback: Int
    ) -> Int {
        guard let descriptor else { return fallback }
        return Int(descriptor.int32Value)
    }

    private static func cgWindowID(from descriptor: NSAppleEventDescriptor?) -> CGWindowID? {
        guard let descriptor else { return nil }
        let value = descriptor.int32Value
        guard value > 0 else { return nil }
        return CGWindowID(value)
    }

    private static func color(
        from descriptor: NSAppleEventDescriptor?,
        fallback: NSColor
    ) -> NSColor {
        guard let descriptor, descriptor.numberOfItems >= 3 else { return fallback }
        let components = (1...3).map {
            max(0, Int(descriptor.atIndex($0)?.int32Value ?? 0))
        }
        let maxComponent = max(components.max() ?? 0, 1)
        let divisor = maxComponent > 255 ? 65_535.0 : 255.0
        return NSColor(
            calibratedRed: min(1, CGFloat(Double(components[0]) / divisor)),
            green: min(1, CGFloat(Double(components[1]) / divisor)),
            blue: min(1, CGFloat(Double(components[2]) / divisor)),
            alpha: 1
        )
    }

    private static let scriptSource = """
    on rgbComponents(theColor)
        try
            return {item 1 of theColor, item 2 of theColor, item 3 of theColor}
        on error
            return {0, 0, 0}
        end try
    end rgbComponents

    tell application "Terminal"
        set tabRows to {}
        repeat with windowIndex from 1 to count of windows
            try
                set terminalWindowID to id of window windowIndex
            on error
                set terminalWindowID to -1
            end try
            try
                set terminalWindowTitle to (name of window windowIndex) as text
            on error
                set terminalWindowTitle to ""
            end try
            repeat with tabIndex from 1 to count of «class ttab» of window windowIndex
                try
                    set tabContents to («property pcnt» of «class ttab» tabIndex of window windowIndex) as text
                on error
                    set tabContents to ""
                end try
                try
                    set tabTitle to («property titl» of «class ttab» tabIndex of window windowIndex) as text
                on error
                    set tabTitle to ""
                end try
                try
                    set tabSettings to «property tcst» of «class ttab» tabIndex of window windowIndex
                    set styleFontName to («property font» of tabSettings) as text
                    set styleFontSize to «property ptsz» of tabSettings
                    set backgroundRGB to my rgbComponents(«property pbcl» of tabSettings)
                    set normalRGB to my rgbComponents(«property ptxc» of tabSettings)
                on error
                    set styleFontName to ""
                    set styleFontSize to 13
                    set backgroundRGB to {0, 0, 0}
                    set normalRGB to {65535, 65535, 65535}
                end try
                set end of tabRows to {tabTitle, tabContents, styleFontName, styleFontSize, backgroundRGB, normalRGB, terminalWindowID, terminalWindowTitle}
            end repeat
        end repeat
        return tabRows
    end tell
    """
}

enum TerminalPreviewRenderer {
    private static let imageSize = NSSize(width: 960, height: 600)
    private static let contentInset = CGFloat(18)

    static func render(
        snapshot: TerminalTabSnapshot,
        fallbackTitle: String?
    ) -> NSImage? {
        render(
            contents: snapshot.contents,
            style: snapshot.style,
            fallbackTitle: fallbackTitle
        )
    }

    private static func render(
        contents: String,
        style: TerminalPreviewStyle,
        fallbackTitle: String?
    ) -> NSImage? {
        let image = NSImage(size: imageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        style.backgroundColor.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: imageSize)).fill()

        let font = resolvedFont(style: style)
        let lineHeight = max(1, ceil(font.ascender - font.descender + font.leading))
        let contentRect = NSRect(
            x: contentInset,
            y: contentInset,
            width: imageSize.width - contentInset * 2,
            height: imageSize.height - contentInset * 2
        )
        let maxLines = max(1, Int(contentRect.height / lineHeight))
        let maxColumns = terminalColumnCapacity(font: font, contentWidth: contentRect.width)
        let renderedText = terminalText(
            contents: contents,
            fallbackTitle: fallbackTitle,
            maxLines: maxLines,
            maxColumns: maxColumns
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: style.normalTextColor,
            .font: font,
            .paragraphStyle: terminalParagraphStyle(lineHeight: lineHeight)
        ]
        (renderedText as NSString).draw(
            with: contentRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
            attributes: attributes
        )

        return image
    }

    private static func resolvedFont(style: TerminalPreviewStyle) -> NSFont {
        let displaySize = min(18, max(9, style.fontSize))
        if let fontName = style.fontName,
           !fontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let font = NSFont(name: fontName, size: displaySize) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: displaySize, weight: .regular)
    }

    private static func terminalColumnCapacity(font: NSFont, contentWidth: CGFloat) -> Int {
        let characterWidth = max(
            1,
            ceil(("W" as NSString).size(withAttributes: [.font: font]).width)
        )
        return max(1, Int(contentWidth / characterWidth))
    }

    private static func terminalText(
        contents: String,
        fallbackTitle: String?,
        maxLines: Int,
        maxColumns: Int
    ) -> String {
        let normalized = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let visualLines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap { wrappedTerminalLine(String($0), maxColumns: maxColumns) }
        if let lastContentIndex = visualLines.lastIndex(
            where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        ) {
            let visibleLines = visualLines[...lastContentIndex].suffix(maxLines)
            return visibleLines.joined(separator: "\n")
        }
        let title = fallbackTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            return title
        }
        return "Terminal"
    }

    private static func wrappedTerminalLine(_ line: String, maxColumns: Int) -> [String] {
        guard !line.isEmpty else { return [""] }
        var wrapped: [String] = []
        var startIndex = line.startIndex
        while startIndex < line.endIndex {
            let endIndex = line.index(
                startIndex,
                offsetBy: maxColumns,
                limitedBy: line.endIndex
            ) ?? line.endIndex
            wrapped.append(String(line[startIndex..<endIndex]))
            startIndex = endIndex
        }
        return wrapped
    }

    private static func terminalParagraphStyle(lineHeight: CGFloat) -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.maximumLineHeight = lineHeight
        return paragraphStyle
    }
}
