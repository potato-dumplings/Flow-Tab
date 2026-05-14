import AppKit
import Foundation

struct RuntimeChromeWindowFocusBridge {
    struct CandidateQuery {
        let candidates: [Candidate]
        let chromeWindowCount: Int
        let error: String?
    }

    struct Candidate {
        let windowID: Int64
        let name: String
        let activeTabTitle: String
        let bounds: CGRect
        let score: Double

        var logDescription: String {
            "\(windowID):score=\(String(format: "%.1f", score)):name=\(chromeActivationLogValue(name)):tab=\(chromeActivationLogValue(activeTabTitle)):frame=\(chromeActivationFrameDescription(bounds))"
        }
    }

    struct FocusResult {
        let accepted: Bool
        let frontWindowID: Int64?
        let error: String?
    }

    private struct ChromeWindow {
        let windowID: Int64
        let name: String
        let activeTabTitle: String
        let bounds: CGRect
    }

    static func canAttempt(for app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "com.google.Chrome"
    }

    static func candidates(
        expectedTitle: String,
        expectedFrame: CGRect?
    ) -> [Candidate] {
        candidateQuery(
            expectedTitle: expectedTitle,
            expectedFrame: expectedFrame
        ).candidates
    }

    static func candidateQuery(
        expectedTitle: String,
        expectedFrame: CGRect?
    ) -> CandidateQuery {
        let listResult = chromeWindows()
        let candidates = listResult.windows
            .compactMap { window -> Candidate? in
                let titleAffinity = chromeTitleAffinity(
                    expectedTitle: expectedTitle,
                    windowName: window.name,
                    activeTabTitle: window.activeTabTitle
                )
                let geometryDistance = chromeGeometryDistance(
                    expectedFrame: expectedFrame,
                    chromeBounds: window.bounds
                )
                guard titleAffinity <= 1 || geometryDistance <= 220 else {
                    return nil
                }
                return Candidate(
                    windowID: window.windowID,
                    name: window.name,
                    activeTabTitle: window.activeTabTitle,
                    bounds: window.bounds,
                    score: Double(titleAffinity * 1000) + geometryDistance
                )
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score < rhs.score
                }
                return lhs.windowID < rhs.windowID
            }
        return CandidateQuery(
            candidates: candidates,
            chromeWindowCount: listResult.windows.count,
            error: listResult.error
        )
    }

    static func focusWindow(windowID: Int64) -> FocusResult {
        let script = """
        tell application id "com.google.Chrome"
            set targetWindowID to \(windowID)
            set index of window id targetWindowID to 1
            activate
            delay 0.05
            set index of window id targetWindowID to 1
            delay 0.05
            return id of front window as text
        end tell
        """
        let result = execute(script)
        if let error = result.error {
            return FocusResult(accepted: false, frontWindowID: nil, error: error)
        }
        let frontWindowID = parseInteger(result.value ?? "")
        return FocusResult(
            accepted: frontWindowID == windowID,
            frontWindowID: frontWindowID,
            error: nil
        )
    }

    static func selectCandidate(
        _ candidates: [Candidate],
        targetCGWindowID: CGWindowID,
        fallbackTitle: String,
        fallbackFrame: CGRect?,
        currentCGWindows: [RuntimeSnapshotProvider.CGWindowEntry]
    ) -> Candidate? {
        guard let firstCandidate = candidates.first else { return nil }
        let bestScore = firstCandidate.score
        let bestCandidates = candidates.filter { abs($0.score - bestScore) < 0.001 }
        guard bestCandidates.count > 1 else { return firstCandidate }

        guard
            let targetIndex = chromeTargetOrdinal(
                targetCGWindowID: targetCGWindowID,
                fallbackTitle: fallbackTitle,
                fallbackFrame: fallbackFrame,
                currentCGWindows: currentCGWindows
            ),
            targetIndex < bestCandidates.count
        else {
            return firstCandidate
        }
        return bestCandidates[targetIndex]
    }

    private static func chromeWindows() -> (windows: [ChromeWindow], error: String?) {
        let script = """
        set rowSeparator to ASCII character 30
        set fieldSeparator to ASCII character 31
        set output to ""
        tell application id "com.google.Chrome"
            repeat with chromeWindow in every window
                set windowBounds to bounds of chromeWindow
                set output to output & (id of chromeWindow as text) & fieldSeparator
                set output to output & (name of chromeWindow as text) & fieldSeparator
                set output to output & (title of active tab of chromeWindow as text) & fieldSeparator
                set output to output & (item 1 of windowBounds as text) & fieldSeparator
                set output to output & (item 2 of windowBounds as text) & fieldSeparator
                set output to output & (item 3 of windowBounds as text) & fieldSeparator
                set output to output & (item 4 of windowBounds as text) & rowSeparator
            end repeat
        end tell
        return output
        """
        let result = execute(script)
        guard result.error == nil else {
            return ([], result.error)
        }
        guard let value = result.value else {
            return ([], "empty-result")
        }
        let rowSeparator = String(UnicodeScalar(30))
        let fieldSeparator = String(UnicodeScalar(31))
        let windows = value
            .split(separator: Character(rowSeparator), omittingEmptySubsequences: true)
            .compactMap { row -> ChromeWindow? in
                let fields = row
                    .split(separator: Character(fieldSeparator), omittingEmptySubsequences: false)
                    .map(String.init)
                guard fields.count == 7 else { return nil }
                guard let windowID = parseInteger(fields[0]) else { return nil }
                guard
                    let minX = parseDouble(fields[3]),
                    let minY = parseDouble(fields[4]),
                    let maxX = parseDouble(fields[5]),
                    let maxY = parseDouble(fields[6])
                else {
                    return nil
                }
                return ChromeWindow(
                    windowID: windowID,
                    name: fields[1],
                    activeTabTitle: fields[2],
                    bounds: CGRect(
                        x: minX,
                        y: minY,
                        width: max(0, maxX - minX),
                        height: max(0, maxY - minY)
                    ).standardized
                )
            }
        return (windows, nil)
    }

    private static func execute(_ source: String) -> (value: String?, error: String?) {
        guard let script = NSAppleScript(source: source) else {
            return (nil, "compile-failed")
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            return (nil, String(describing: errorInfo))
        }
        return (descriptor.stringValue, nil)
    }

    private static func chromeTitleAffinity(
        expectedTitle: String,
        windowName: String,
        activeTabTitle: String
    ) -> Int {
        let expected = normalizedChromeTitle(expectedTitle)
        guard !expected.isEmpty else { return 2 }
        let names = [windowName, activeTabTitle].map(normalizedChromeTitle)
        if names.contains(expected) {
            return 0
        }
        if names.contains(where: { !$0.isEmpty && (expected.contains($0) || $0.contains(expected)) }) {
            return 1
        }
        return 2
    }

    private static func normalizedChromeTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func chromeGeometryDistance(
        expectedFrame: CGRect?,
        chromeBounds: CGRect
    ) -> Double {
        guard let expectedFrame = expectedFrame?.standardized else { return 10_000 }
        let chromeBounds = chromeBounds.standardized
        let directDistance = frameDistance(expectedFrame, chromeBounds)
        let bottomAlignedDistance =
            abs(expectedFrame.minX - chromeBounds.minX)
            + abs(expectedFrame.width - chromeBounds.width)
            + abs(expectedFrame.maxY - chromeBounds.maxY)
            + (abs(expectedFrame.minY - chromeBounds.minY) * 0.3)
            + (abs(expectedFrame.height - chromeBounds.height) * 0.3)
        return min(directDistance, bottomAlignedDistance)
    }

    private static func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        abs(lhs.minX - rhs.minX)
            + abs(lhs.minY - rhs.minY)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }

    private static func chromeTargetOrdinal(
        targetCGWindowID: CGWindowID,
        fallbackTitle: String,
        fallbackFrame: CGRect?,
        currentCGWindows: [RuntimeSnapshotProvider.CGWindowEntry]
    ) -> Int? {
        guard
            let targetWindow = currentCGWindows.first(where: { $0.id == targetCGWindowID }),
            let targetFrame = (targetWindow.bounds ?? fallbackFrame)?.standardized
        else {
            return nil
        }
        let targetTitle = normalizedChromeTitle(targetWindow.title ?? fallbackTitle)
        guard !targetTitle.isEmpty else { return nil }

        let siblings = currentCGWindows
            .filter { window in
                guard RuntimeSnapshotProvider.cgWindowPassesValidityConstraints(window) else {
                    return false
                }
                guard let frame = window.bounds?.standardized else { return false }
                guard frameDistance(frame, targetFrame) <= 4 else { return false }
                return normalizedChromeTitle(window.title ?? "") == targetTitle
            }
            .sorted { lhs, rhs in lhs.id < rhs.id }
        guard siblings.count > 1 else { return nil }
        return siblings.firstIndex { $0.id == targetCGWindowID }
    }

    private static func parseInteger(_ value: String) -> Int64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let integer = Int64(trimmed) {
            return integer
        }
        guard let double = Double(trimmed) else { return nil }
        return Int64(double)
    }

    private static func parseDouble(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private func chromeActivationFrameDescription(_ frame: CGRect?) -> String {
    guard let frame else { return "nil" }
    return "\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.size.width))x\(Int(frame.size.height))"
}

private func chromeActivationLogValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
