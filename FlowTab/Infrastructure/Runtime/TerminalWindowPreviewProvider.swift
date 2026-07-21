import AppKit
import ApplicationServices
import CoreText
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
    let columnCount: Int?
    let rowCount: Int?
    let style: TerminalPreviewStyle
}

enum TerminalScriptingSnapshotError: Error, Equatable {
    case permissionDenied
    case readFailed
    case parseFailed
}

enum TerminalPreviewWindowTarget: Equatable, Hashable {
    case windowID(CGWindowID)
    case windowIndex(Int)
}

protocol TerminalScriptingSnapshotProviding {
    func selectedTabSnapshot(
        ownerPID: pid_t,
        target: TerminalPreviewWindowTarget
    ) -> Result<TerminalTabSnapshot, TerminalScriptingSnapshotError>
}

struct TerminalWindowPreviewProvider: SpecialWindowPreviewProviding {
    private static let terminalBundleIdentifier = "com.apple.Terminal"

    private struct SnapshotCacheKey: Hashable {
        let ownerPID: pid_t
        let target: TerminalPreviewWindowTarget
    }

    private let adapter: any TerminalScriptingSnapshotProviding
    private let isContentPreviewEnabled: () -> Bool

    init(
        adapter: any TerminalScriptingSnapshotProviding = TerminalScriptingAdapter(),
        isContentPreviewEnabled: @escaping () -> Bool = {
            TerminalContentPreviewPreferencesStore.isEnabled()
        }
    ) {
        self.adapter = adapter
        self.isContentPreviewEnabled = isContentPreviewEnabled
    }

    func supports(_ request: WindowPreviewRequest) -> Bool {
        isContentPreviewEnabled()
            && (request.bundleIdentifier == Self.terminalBundleIdentifier
                || request.appID == Self.terminalBundleIdentifier)
    }

    func previews(for requests: [WindowPreviewRequest]) async -> [WindowPreviewResult] {
        guard !requests.isEmpty else { return [] }
        guard isContentPreviewEnabled() else {
            return Array(repeating: .failure(.specialProviderUnavailable), count: requests.count)
        }

        var snapshotsByTarget: [
            SnapshotCacheKey: Result<TerminalTabSnapshot, TerminalScriptingSnapshotError>
        ] = [:]
        return requests.map { request in
            guard let target = Self.target(for: request) else {
                return .failure(.specialProviderUnavailable)
            }
            let cacheKey = SnapshotCacheKey(ownerPID: request.ownerPID, target: target)

            let snapshotResult: Result<TerminalTabSnapshot, TerminalScriptingSnapshotError>
            if let cachedResult = snapshotsByTarget[cacheKey] {
                snapshotResult = cachedResult
            } else {
                let loadedResult = adapter.selectedTabSnapshot(
                    ownerPID: request.ownerPID,
                    target: target
                )
                snapshotsByTarget[cacheKey] = loadedResult
                snapshotResult = loadedResult
            }

            switch snapshotResult {
            case .success(let snapshot):
                return preview(for: request, snapshot: snapshot)
            case .failure(let error):
                return .failure(windowPreviewFailureReason(from: error))
            }
        }
    }

    private func preview(
        for request: WindowPreviewRequest,
        snapshot: TerminalTabSnapshot
    ) -> WindowPreviewResult {
        guard
            let image = TerminalPreviewRenderer.render(
                snapshot: snapshot,
                fallbackTitle: request.preferredTitle,
                windowFrame: request.windowFrame
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

    private static func target(for request: WindowPreviewRequest) -> TerminalPreviewWindowTarget? {
        if let preferredCGWindowID = request.preferredCGWindowID {
            return .windowID(preferredCGWindowID)
        }
        let handleIDs = [request.activationHandleID, request.windowID]
            .compactMap { $0 }
        for handleID in handleIDs {
            if let windowIndex = AXWindowInspector.windowIndex(
                from: handleID,
                expectedPID: request.ownerPID
            ), windowIndex >= 0 {
                return .windowIndex(windowIndex)
            }
        }
        return nil
    }
}

struct TerminalScriptingAdapter: TerminalScriptingSnapshotProviding {
    private static let terminalBundleIdentifier = "com.apple.Terminal"

    func selectedTabSnapshot(
        ownerPID: pid_t,
        target: TerminalPreviewWindowTarget
    ) -> Result<TerminalTabSnapshot, TerminalScriptingSnapshotError> {
        guard
            NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier
                == Self.terminalBundleIdentifier
        else {
            return .failure(.readFailed)
        }
        guard let script = NSAppleScript(source: Self.scriptSource(for: target)) else {
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
        guard snapshots.count == 1, let snapshot = snapshots.first else {
            return .failure(.readFailed)
        }
        return .success(snapshot)
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
            let columnCount = item.numberOfItems >= 9
                ? optionalPositiveInt(from: item.atIndex(9))
                : nil
            let rowCount = item.numberOfItems >= 10
                ? optionalPositiveInt(from: item.atIndex(10))
                : nil
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
                    columnCount: columnCount,
                    rowCount: rowCount,
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

    private static func optionalPositiveInt(
        from descriptor: NSAppleEventDescriptor?
    ) -> Int? {
        guard let descriptor else { return nil }
        let value = Int(descriptor.int32Value)
        return value > 0 ? value : nil
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

    static func scriptSource(for target: TerminalPreviewWindowTarget) -> String {
        let targetSelection: String
        switch target {
        case .windowID(let windowID):
            targetSelection = "set targetWindow to first window whose id is \(windowID)"
        case .windowIndex(let zeroBasedIndex):
            let oneBasedIndex = zeroBasedIndex + 1
            targetSelection = """
            if (count of windows) < \(oneBasedIndex) then return {}
            set targetWindow to window \(oneBasedIndex)
            """
        }

        return """
    on rgbComponents(theColor)
        try
            return {item 1 of theColor, item 2 of theColor, item 3 of theColor}
        on error
            return {0, 0, 0}
        end try
    end rgbComponents

    tell application "Terminal"
        try
            \(targetSelection)
        on error
            return {}
        end try
        try
            set targetTab to selected tab of targetWindow
        on error
            return {}
        end try
        try
            set terminalWindowID to id of targetWindow
        on error
            set terminalWindowID to -1
        end try
        try
            set terminalWindowTitle to (name of targetWindow) as text
        on error
            set terminalWindowTitle to ""
        end try
        try
            set tabContents to («property pcnt» of targetTab) as text
        on error
            set tabContents to ""
        end try
        try
            set tabTitle to («property titl» of targetTab) as text
        on error
            set tabTitle to ""
        end try
        try
            set tabColumnCount to «property ccol» of targetTab
        on error
            set tabColumnCount to -1
        end try
        try
            set tabRowCount to «property crow» of targetTab
        on error
            set tabRowCount to -1
        end try
        try
            set tabSettings to «property tcst» of targetTab
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
        return {{tabTitle, tabContents, styleFontName, styleFontSize, backgroundRGB, normalRGB, terminalWindowID, terminalWindowTitle, tabColumnCount, tabRowCount}}
    end tell
    """
    }
}

enum TerminalPreviewRenderer {
    private static let defaultImageSize = NSSize(width: 1440, height: 900)
    private static let preferredLongEdge = CGFloat(1440)
    private static let maximumLongEdge = CGFloat(2048)
    private static let contentInset = CGFloat(8)
    private static let maxRenderableRows = 160

    static func render(
        snapshot: TerminalTabSnapshot,
        fallbackTitle: String?,
        windowFrame: CGRect? = nil
    ) -> NSImage? {
        render(
            contents: snapshot.contents,
            columnCount: snapshot.columnCount,
            rowCount: snapshot.rowCount,
            style: snapshot.style,
            fallbackTitle: fallbackTitle,
            windowFrame: windowFrame
        )
    }

    private static func render(
        contents: String,
        columnCount: Int?,
        rowCount: Int?,
        style: TerminalPreviewStyle,
        fallbackTitle: String?,
        windowFrame: CGRect?
    ) -> NSImage? {
        let imageSize = imageSize(for: windowFrame)
        let pixelWidth = max(1, Int(ceil(imageSize.width)))
        let pixelHeight = max(1, Int(ceil(imageSize.height)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(cgColor(from: style.backgroundColor, fallback: .black))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.textMatrix = .identity

        let font = resolvedFont(style: style)
        let lineHeight = max(1, ceil(font.ascender - font.descender + font.leading))
        let contentRect = NSRect(
            x: contentInset,
            y: contentInset,
            width: imageSize.width - contentInset * 2,
            height: imageSize.height - contentInset * 2
        )
        let lines = terminalLines(
            contents: contents,
            fallbackTitle: fallbackTitle,
            columnCount: columnCount,
            rowCount: rowCount,
            maxRows: maxRenderableRows
        )
        let inferredColumns = lines.map(terminalColumnCount).max() ?? 1
        let sourceColumns = max(1, columnCount ?? inferredColumns)
        let sourceRows = max(1, min(rowCount ?? lines.count, maxRenderableRows))
        let sourceSize = NSSize(
            width: CGFloat(sourceColumns) * terminalCharacterWidth(font: font),
            height: CGFloat(sourceRows) * lineHeight
        )
        let scaleX = contentRect.width / max(1, sourceSize.width)
        let scaleY = contentRect.height / max(1, sourceSize.height)
        let fittingScale = min(scaleX, scaleY)
        let hasTerminalGridSize = columnCount != nil && rowCount != nil
        let scale = hasTerminalGridSize ? fittingScale : min(1, fittingScale)
        let scaledLineHeight = max(1, lineHeight * scale)
        let scaledFont = scaledFont(from: font, scale: scale)
        let textColor = cgColor(from: style.normalTextColor, fallback: .white)
        drawTerminalGrid(
            lines,
            in: contentRect,
            context: context,
            sourceRows: sourceRows,
            sourceColumns: sourceColumns,
            scaledCharacterWidth: terminalCharacterWidth(font: font) * scale,
            scaledLineHeight: scaledLineHeight,
            font: coreTextFont(from: scaledFont),
            textColor: textColor
        )

        guard let image = context.makeImage() else { return nil }
        return NSImage(cgImage: image, size: imageSize)
    }

    private static func drawTerminalGrid(
        _ lines: [String],
        in contentRect: NSRect,
        context: CGContext,
        sourceRows: Int,
        sourceColumns: Int,
        scaledCharacterWidth: CGFloat,
        scaledLineHeight: CGFloat,
        font: CTFont,
        textColor: CGColor
    ) {
        let gridHeight = CGFloat(sourceRows) * scaledLineHeight
        let originY = contentRect.maxY - gridHeight
        let fontHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        let baselineOffset = max(0, (scaledLineHeight - fontHeight) / 2) + CTFontGetDescent(font)
        var lineCache: [String: CTLine] = [:]

        for (lineIndex, line) in lines.prefix(sourceRows).enumerated() {
            let y = originY + gridHeight - CGFloat(lineIndex + 1) * scaledLineHeight
            for run in TerminalPreviewTextLayout.cellRuns(in: line, maxColumns: sourceColumns) {
                let rect = NSRect(
                    x: contentRect.minX + CGFloat(run.column) * scaledCharacterWidth,
                    y: y,
                    width: CGFloat(run.columnWidth) * scaledCharacterWidth,
                    height: scaledLineHeight
                )
                let key = run.text
                let textLine = lineCache[key] ?? {
                    let line = terminalTextLine(
                        key,
                        font: font,
                        textColor: textColor
                    )
                    lineCache[key] = line
                    return line
                }()
                context.textPosition = CGPoint(x: rect.minX, y: rect.minY + baselineOffset)
                CTLineDraw(textLine, context)
            }
        }
    }

    private static func imageSize(for windowFrame: CGRect?) -> NSSize {
        guard let frame = windowFrame?.standardized,
              frame.width > 0,
              frame.height > 0
        else {
            return defaultImageSize
        }
        let longEdge = max(frame.width, frame.height)
        guard longEdge > 0 else { return defaultImageSize }
        let targetLongEdge = min(max(longEdge, preferredLongEdge), maximumLongEdge)
        let scale = targetLongEdge / longEdge
        return NSSize(
            width: max(1, ceil(frame.width * scale)),
            height: max(1, ceil(frame.height * scale))
        )
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

    private static func scaledFont(from font: NSFont, scale: CGFloat) -> NSFont {
        NSFont(
            descriptor: font.fontDescriptor,
            size: max(1, font.pointSize * scale)
        ) ?? NSFont.monospacedSystemFont(
            ofSize: max(1, font.pointSize * scale),
            weight: .regular
        )
    }

    private static func terminalCharacterWidth(font: NSFont) -> CGFloat {
        max(
            1,
            ceil(("W" as NSString).size(withAttributes: [.font: font]).width)
        )
    }

    private static func terminalLines(
        contents: String,
        fallbackTitle: String?,
        columnCount: Int?,
        rowCount: Int?,
        maxRows: Int
    ) -> [String] {
        let terminalRows = rowLimit(rowCount: rowCount, maxRows: maxRows)
        let contentLines = tailLogicalLines(
            contents: contents,
            limit: terminalRows
        )
        if !contentLines.isEmpty {
            let visualLines: [String]
            if let columnCount, columnCount > 0 {
                visualLines = TerminalPreviewTextLayout.softWrappedLines(
                    from: contentLines,
                    columnCount: columnCount,
                    maxRows: terminalRows
                )
            } else {
                visualLines = TerminalPreviewTextLayout.displayLines(from: contentLines)
            }
            return Array(visualLines.suffix(terminalRows))
        }
        let title = fallbackTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            return [title]
        }
        return ["Terminal"]
    }

    private static func tailLogicalLines(
        contents: String,
        limit: Int
    ) -> [String] {
        guard !contents.isEmpty else { return [] }
        let limit = max(1, limit)
        var collected: [Substring] = []
        collected.reserveCapacity(limit)
        var end = contents.endIndex
        var foundContent = false

        while end > contents.startIndex, collected.count < limit {
            let lineEnd = end
            var lineStart = end
            while lineStart > contents.startIndex {
                let previous = contents.index(before: lineStart)
                guard contents[previous] != "\n", contents[previous] != "\r" else {
                    break
                }
                lineStart = previous
            }

            let line = contents[lineStart..<lineEnd]
            if foundContent || line.contains(where: { !$0.isWhitespace }) {
                foundContent = true
                collected.append(line)
            }

            guard lineStart > contents.startIndex else { break }
            var delimiterStart = contents.index(before: lineStart)
            if contents[delimiterStart] == "\n", delimiterStart > contents.startIndex {
                let previous = contents.index(before: delimiterStart)
                if contents[previous] == "\r" {
                    delimiterStart = previous
                }
            }
            end = delimiterStart
        }

        guard foundContent else { return [] }
        return collected.reversed().map(String.init)
    }

    private static func rowLimit(rowCount: Int?, maxRows: Int) -> Int {
        rowCount.map { min(max(1, $0), maxRows) } ?? maxRows
    }

    private static func terminalColumnCount(_ line: String) -> Int {
        TerminalPreviewTextLayout.columnCount(for: line)
    }

    private static func terminalTextLine(
        _ text: String,
        font: CTFont,
        textColor: CGColor
    ) -> CTLine {
        CTLineCreateWithAttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: font,
                    kCTForegroundColorAttributeName as NSAttributedString.Key: textColor
                ]
            )
        )
    }

    private static func coreTextFont(from font: NSFont) -> CTFont {
        CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
    }

    private static func cgColor(from color: NSColor, fallback: NSColor) -> CGColor {
        (color.usingColorSpace(.deviceRGB) ?? fallback).cgColor
    }

    static func terminalLinesForTesting(
        contents: String,
        fallbackTitle: String?,
        columnCount: Int?,
        rowCount: Int?,
        maxRows: Int
    ) -> [String] {
        terminalLines(
            contents: contents,
            fallbackTitle: fallbackTitle,
            columnCount: columnCount,
            rowCount: rowCount,
            maxRows: maxRows
        )
    }
}
