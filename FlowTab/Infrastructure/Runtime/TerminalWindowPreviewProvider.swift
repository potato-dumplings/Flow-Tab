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
    let columnCount: Int?
    let rowCount: Int?
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
                    set tabColumnCount to «property ccol» of «class ttab» tabIndex of window windowIndex
                on error
                    set tabColumnCount to -1
                end try
                try
                    set tabRowCount to «property crow» of «class ttab» tabIndex of window windowIndex
                on error
                    set tabRowCount to -1
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
                set end of tabRows to {tabTitle, tabContents, styleFontName, styleFontSize, backgroundRGB, normalRGB, terminalWindowID, terminalWindowTitle, tabColumnCount, tabRowCount}
            end repeat
        end repeat
        return tabRows
    end tell
    """
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
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: style.normalTextColor,
            .font: scaledFont,
            .paragraphStyle: terminalParagraphStyle(lineHeight: scaledLineHeight)
        ]
        drawTerminalGrid(
            lines,
            in: contentRect,
            sourceRows: sourceRows,
            sourceColumns: sourceColumns,
            scaledCharacterWidth: terminalCharacterWidth(font: font) * scale,
            scaledLineHeight: scaledLineHeight,
            attributes: attributes
        )

        return image
    }

    private static func drawTerminalGrid(
        _ lines: [String],
        in contentRect: NSRect,
        sourceRows: Int,
        sourceColumns: Int,
        scaledCharacterWidth: CGFloat,
        scaledLineHeight: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let gridHeight = CGFloat(sourceRows) * scaledLineHeight
        let originY = contentRect.maxY - gridHeight
        for (lineIndex, line) in lines.prefix(sourceRows).enumerated() {
            let y = originY + gridHeight - CGFloat(lineIndex + 1) * scaledLineHeight
            var column = 0
            for character in line {
                let columnWidth = terminalColumnWidth(character)
                defer { column += columnWidth }
                guard column < sourceColumns, character != "\t", character != " " else {
                    continue
                }
                let rect = NSRect(
                    x: contentRect.minX + CGFloat(column) * scaledCharacterWidth,
                    y: y,
                    width: CGFloat(columnWidth) * scaledCharacterWidth,
                    height: scaledLineHeight
                )
                (String(character) as NSString).draw(
                    with: rect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
                    attributes: attributes
                )
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
        let normalized = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if let lastContentIndex = lines.lastIndex(
            where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        ) {
            let contentLines = Array(lines[...lastContentIndex])
            let terminalRows = rowCount.map { min(max(1, $0), maxRows) } ?? maxRows
            let visualLines: [String]
            if let columnCount, columnCount > 0 {
                visualLines = softWrapTerminalLines(
                    contentLines,
                    columnCount: columnCount
                )
            } else {
                visualLines = contentLines
            }
            return Array(visualLines.suffix(max(1, terminalRows)))
        }
        let title = fallbackTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            return [title]
        }
        return ["Terminal"]
    }

    private static func softWrapTerminalLines(
        _ lines: [String],
        columnCount: Int
    ) -> [String] {
        let columns = max(1, columnCount)
        return lines.flatMap { line -> [String] in
            guard !line.isEmpty else { return [""] }
            var rows: [String] = []
            var currentRow = ""
            var currentColumns = 0

            for character in line {
                let characterColumns = terminalColumnWidth(character)
                if currentColumns > 0, currentColumns + characterColumns > columns {
                    rows.append(currentRow)
                    currentRow = ""
                    currentColumns = 0
                }
                currentRow.append(character)
                currentColumns += characterColumns
                if currentColumns >= columns {
                    rows.append(currentRow)
                    currentRow = ""
                    currentColumns = 0
                }
            }

            if !currentRow.isEmpty || rows.isEmpty {
                rows.append(currentRow)
            }
            return rows
        }
    }

    private static func terminalColumnCount(_ line: String) -> Int {
        line.reduce(0) { count, character in
            count + terminalColumnWidth(character)
        }
    }

    private static func terminalColumnWidth(_ character: Character) -> Int {
        if character == "\t" {
            return 4
        }
        return character.unicodeScalars.contains(where: isWideTerminalScalar) ? 2 : 1
    }

    private static func isWideTerminalScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F,
             0x2329...0x232A,
             0x2E80...0xA4CF,
             0xAC00...0xD7A3,
             0xF900...0xFAFF,
             0xFE10...0xFE19,
             0xFE30...0xFE6F,
             0xFF00...0xFF60,
             0xFFE0...0xFFE6,
             0x1F300...0x1FAFF:
            return true
        default:
            return false
        }
    }

    private static func terminalParagraphStyle(lineHeight: CGFloat) -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.maximumLineHeight = lineHeight
        return paragraphStyle
    }
}
