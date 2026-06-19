import AppKit
import Foundation

struct RuntimeChromeWindowFocusBridge {
    private static let scriptStatePropagationDelaySeconds: TimeInterval = 0.05
    private static let candidateGeometryMatchThreshold: Double = 220
    private static let strongCandidateGeometryMatchThreshold: Double = 80
    private static let candidateScoreTieTolerance = 0.001
    private static let candidateMinimumScoreSeparation: Double = 80

    struct ScriptableBrowserSpec: Equatable {
        let bundleIdentifier: String
        let appleScriptApplicationID: String
        let debugName: String

        static let chrome = ScriptableBrowserSpec(
            bundleIdentifier: "com.google.Chrome",
            appleScriptApplicationID: "com.google.Chrome",
            debugName: "chrome"
        )
    }

    struct CandidateQuery {
        let candidates: [Candidate]
        let chromeWindowCount: Int
        let error: String?
    }

    struct Candidate: Equatable {
        let windowID: Int64
        let name: String
        let activeTabTitle: String
        let bounds: CGRect
        let titleAffinity: Int
        let geometryDistance: Double
        let matchedTitle: Bool
        let matchedGeometry: Bool
        let score: Double

        init(
            windowID: Int64,
            name: String,
            activeTabTitle: String,
            bounds: CGRect,
            titleAffinity: Int,
            geometryDistance: Double
        ) {
            self.windowID = windowID
            self.name = name
            self.activeTabTitle = activeTabTitle
            self.bounds = bounds
            self.titleAffinity = titleAffinity
            self.geometryDistance = geometryDistance
            matchedTitle = titleAffinity == 0
            matchedGeometry = geometryDistance <= RuntimeChromeWindowFocusBridge.candidateGeometryMatchThreshold
            score = Double(titleAffinity * 1000) + geometryDistance
        }

        var hasStrongSignals: Bool {
            matchedTitle
                && geometryDistance <= RuntimeChromeWindowFocusBridge.strongCandidateGeometryMatchThreshold
        }

        var logDescription: String {
            "\(windowID):score=\(String(format: "%.1f", score)):titleAffinity=\(titleAffinity):geometry=\(String(format: "%.1f", geometryDistance)):title=\(matchedTitle ? 1 : 0):frame=\(matchedGeometry ? 1 : 0):name=\(chromeActivationLogValue(name)):tab=\(chromeActivationLogValue(activeTabTitle)):frame=\(chromeActivationFrameDescription(bounds))"
        }
    }

    enum CandidateConfidence: String {
        case singleCandidate
        case uniqueStrongSignals
        case separatedScore
        case targetOrdinalTieBreak
    }

    enum CandidateDecision: Equatable {
        case selected(candidate: Candidate, confidence: CandidateConfidence)
        case ambiguous(candidates: [Candidate], reason: String)
        case unavailable(reason: String)

        var selectedCandidate: Candidate? {
            switch self {
            case let .selected(candidate, _):
                candidate
            case .ambiguous, .unavailable:
                nil
            }
        }

        var logDescription: String {
            switch self {
            case let .selected(candidate, confidence):
                "selected:\(candidate.windowID):confidence=\(confidence.rawValue)"
            case let .ambiguous(candidates, reason):
                "ambiguous:reason=\(reason):candidates=\(candidates.prefix(5).map(\.logDescription).joined(separator: ","))"
            case let .unavailable(reason):
                "unavailable:reason=\(chromeActivationLogValue(reason))"
            }
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

    private static let supportedBrowserSpecs: [ScriptableBrowserSpec] = [
        .chrome
    ]

    static func canAttempt(for app: NSRunningApplication) -> Bool {
        scriptableBrowserSpec(for: app) != nil
    }

    static func scriptableBrowserSpec(for app: NSRunningApplication) -> ScriptableBrowserSpec? {
        guard let bundleIdentifier = app.bundleIdentifier else { return nil }
        return scriptableBrowserSpec(forBundleIdentifier: bundleIdentifier)
    }

    static func scriptableBrowserSpec(
        forBundleIdentifier bundleIdentifier: String
    ) -> ScriptableBrowserSpec? {
        supportedBrowserSpecs.first { $0.bundleIdentifier == bundleIdentifier }
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
        candidateQuery(
            browser: .chrome,
            expectedTitle: expectedTitle,
            expectedFrame: expectedFrame
        )
    }

    static func candidateQuery(
        browser: ScriptableBrowserSpec,
        expectedTitle: String,
        expectedFrame: CGRect?
    ) -> CandidateQuery {
        let listResult = chromeWindows(browser: browser)
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
                guard titleAffinity <= 1 || geometryDistance <= candidateGeometryMatchThreshold else {
                    return nil
                }
                return Candidate(
                    windowID: window.windowID,
                    name: window.name,
                    activeTabTitle: window.activeTabTitle,
                    bounds: window.bounds,
                    titleAffinity: titleAffinity,
                    geometryDistance: geometryDistance
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
        focusWindow(windowID: windowID, browser: .chrome)
    }

    static func focusWindow(
        windowID: Int64,
        browser: ScriptableBrowserSpec
    ) -> FocusResult {
        let result = execute(focusWindowScript(windowID: windowID, browser: browser))
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

    static var scriptStatePropagationDelaySecondsForTesting: TimeInterval {
        scriptStatePropagationDelaySeconds
    }

    static func focusWindowScriptForTesting(windowID: Int64) -> String {
        focusWindowScript(windowID: windowID, browser: .chrome)
    }

    static func focusWindowScriptForTesting(
        windowID: Int64,
        bundleIdentifier: String
    ) -> String? {
        guard let browser = scriptableBrowserSpec(forBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return focusWindowScript(windowID: windowID, browser: browser)
    }

    static func windowListScriptForTesting(bundleIdentifier: String) -> String? {
        guard let browser = scriptableBrowserSpec(forBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return windowListScript(browser: browser)
    }

    private static func focusWindowScript(
        windowID: Int64,
        browser: ScriptableBrowserSpec
    ) -> String {
        let propagationDelay = chromeScriptDelayLiteral(scriptStatePropagationDelaySeconds)
        let script = """
        tell application id "\(browser.appleScriptApplicationID)"
            set targetWindowID to \(windowID)
            set index of window id targetWindowID to 1
            activate
            delay \(propagationDelay)
            set index of window id targetWindowID to 1
            delay \(propagationDelay)
            return id of front window as text
        end tell
        """
        return script
    }

    static func selectCandidate(
        _ candidates: [Candidate],
        targetCGWindowID: CGWindowID,
        fallbackTitle: String,
        fallbackFrame: CGRect?,
        currentCGWindows: [RuntimeCGWindowEntry]
    ) -> Candidate? {
        candidateDecision(
            candidates,
            targetCGWindowID: targetCGWindowID,
            fallbackTitle: fallbackTitle,
            fallbackFrame: fallbackFrame,
            currentCGWindows: currentCGWindows
        ).selectedCandidate
    }

    static func candidateDecision(
        _ query: CandidateQuery,
        targetCGWindowID: CGWindowID,
        fallbackTitle: String,
        fallbackFrame: CGRect?,
        currentCGWindows: [RuntimeCGWindowEntry]
    ) -> CandidateDecision {
        if let error = query.error {
            return .unavailable(reason: "candidate-query-error:\(error)")
        }
        return candidateDecision(
            query.candidates,
            targetCGWindowID: targetCGWindowID,
            fallbackTitle: fallbackTitle,
            fallbackFrame: fallbackFrame,
            currentCGWindows: currentCGWindows
        )
    }

    static func candidateDecision(
        _ candidates: [Candidate],
        targetCGWindowID: CGWindowID,
        fallbackTitle: String,
        fallbackFrame: CGRect?,
        currentCGWindows: [RuntimeCGWindowEntry]
    ) -> CandidateDecision {
        guard let firstCandidate = candidates.first else {
            return .unavailable(reason: "no-candidates")
        }
        guard candidates.count > 1 else {
            return .selected(candidate: firstCandidate, confidence: .singleCandidate)
        }

        let strongCandidates = candidates.filter(\.hasStrongSignals)
        if strongCandidates.count == 1, let candidate = strongCandidates.first {
            return .selected(candidate: candidate, confidence: .uniqueStrongSignals)
        }

        let bestScore = firstCandidate.score
        let bestCandidates = candidates.filter {
            abs($0.score - bestScore) <= candidateScoreTieTolerance
        }
        if bestCandidates.count > 1 {
            guard
                let targetIndex = chromeTargetOrdinal(
                    targetCGWindowID: targetCGWindowID,
                    fallbackTitle: fallbackTitle,
                    fallbackFrame: fallbackFrame,
                    currentCGWindows: currentCGWindows
                ),
                targetIndex < bestCandidates.count
            else {
                return .ambiguous(candidates: bestCandidates, reason: "score-tie")
            }
            return .selected(
                candidate: bestCandidates[targetIndex],
                confidence: .targetOrdinalTieBreak
            )
        }

        let secondCandidate = candidates[1]
        guard secondCandidate.score - firstCandidate.score >= candidateMinimumScoreSeparation else {
            return .ambiguous(
                candidates: Array(candidates.prefix(2)),
                reason: "insufficient-score-separation"
            )
        }

        return .selected(candidate: firstCandidate, confidence: .separatedScore)
    }

    private static func chromeWindows(
        browser: ScriptableBrowserSpec
    ) -> (windows: [ChromeWindow], error: String?) {
        let result = execute(windowListScript(browser: browser))
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

    private static func windowListScript(browser: ScriptableBrowserSpec) -> String {
        let script = """
        set rowSeparator to ASCII character 30
        set fieldSeparator to ASCII character 31
        set output to ""
        tell application id "\(browser.appleScriptApplicationID)"
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
        return script
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

    private static func chromeScriptDelayLiteral(_ value: TimeInterval) -> String {
        String(format: "%.2f", value)
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
        currentCGWindows: [RuntimeCGWindowEntry]
    ) -> Int? {
        guard
            let targetWindow = currentCGWindows.first(where: { $0.id == targetCGWindowID }),
            let targetFrame = (targetWindow.bounds ?? fallbackFrame)?.standardized
        else {
            return nil
        }
        let fallbackTitle = normalizedChromeTitleIfPresent(fallbackTitle)
        let targetTitle = normalizedChromeTitleIfPresent(targetWindow.title)
        guard targetTitle != nil || fallbackTitle != nil else { return nil }

        let siblings = currentCGWindows
            .filter { window in
                guard RuntimeCGWindowFacts.passesValidityConstraints(window) else {
                    return false
                }
                guard let frame = window.bounds?.standardized else { return false }
                guard frameDistance(frame, targetFrame) <= 4 else { return false }
                return chromeCGTitleMatchesOrdinalBucket(
                    window.title,
                    targetTitle: targetTitle,
                    fallbackTitle: fallbackTitle
                )
            }
            .sorted { lhs, rhs in lhs.id < rhs.id }
        guard siblings.count > 1 else { return nil }
        return siblings.firstIndex { $0.id == targetCGWindowID }
    }

    private static func chromeCGTitleMatchesOrdinalBucket(
        _ title: String?,
        targetTitle: String?,
        fallbackTitle: String?
    ) -> Bool {
        let title = normalizedChromeTitleIfPresent(title)
        if let targetTitle {
            return title == targetTitle
        }
        return title == nil || title == fallbackTitle
    }

    private static func normalizedChromeTitleIfPresent(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalizedTitle = normalizedChromeTitle(value)
        return normalizedTitle.isEmpty ? nil : normalizedTitle
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
