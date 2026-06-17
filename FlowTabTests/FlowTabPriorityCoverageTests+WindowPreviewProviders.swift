import AppKit
import Combine
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    func testWindowPreviewResolverUsesSpecialProviderBeforeGeneric() async {
        let specialProvider = FakeSpecialWindowPreviewProvider(
            supportedAppID: "com.apple.Terminal",
            result: .success(
                image: makeColorImage(color: .systemGreen),
                resolvedWindowID: nil,
                titleBarStyle: .dark,
                source: .special(appID: "com.apple.Terminal")
            )
        )
        let genericProvider = FakeGenericWindowPreviewProvider(
            result: .failure(.transientSystemError)
        )
        let resolver = WindowPreviewProviderResolver(
            specialProviders: [specialProvider],
            genericProvider: genericProvider
        )

        let results = await resolver.previewOutcomes(
            for: [makePreviewRequest(appID: "com.apple.Terminal")],
            captureSemaphore: nil
        )

        XCTAssertEqual(specialProvider.callCount, 1)
        XCTAssertEqual(genericProvider.callCount, 0)
        XCTAssertEqual(results.first?.source, .special(appID: "com.apple.Terminal"))
        XCTAssertNotNil(results.first?.image)
    }

    func testWindowPreviewResolverFallsBackToGenericProviderWhenNoSpecialProviderMatches() async {
        let specialProvider = FakeSpecialWindowPreviewProvider(
            supportedAppID: "com.apple.Terminal",
            result: .failure(.specialProviderUnavailable)
        )
        let genericProvider = FakeGenericWindowPreviewProvider(
            result: .success(
                image: makeColorImage(color: .systemBlue),
                resolvedWindowID: 24_001,
                titleBarStyle: .light,
                source: .genericScreenshot
            )
        )
        let resolver = WindowPreviewProviderResolver(
            specialProviders: [specialProvider],
            genericProvider: genericProvider
        )

        let results = await resolver.previewOutcomes(
            for: [makePreviewRequest(appID: "com.example.Editor")],
            captureSemaphore: nil
        )

        XCTAssertEqual(specialProvider.callCount, 0)
        XCTAssertEqual(genericProvider.callCount, 1)
        XCTAssertEqual(results.first?.source, .genericScreenshot)
        XCTAssertEqual(results.first?.resolvedWindowID, 24_001)
        XCTAssertNotNil(results.first?.image)
    }

    func testTerminalPreviewRendererCreatesImageForContents() {
        let image = renderTerminalPreview(
            contents: "DONE Compiled successfully\nhttp://127.0.0.1:8080/",
            style: .default,
            fallbackTitle: "Build"
        )

        XCTAssertNotNil(cgImage(from: image))
    }

    func testTerminalPreviewRendererCreatesImageForEmptyContents() {
        let image = renderTerminalPreview(
            contents: "",
            style: .default,
            fallbackTitle: "Shell"
        )

        XCTAssertNotNil(cgImage(from: image))
    }

    func testTerminalPreviewRendererWrapsLongLogicalLinesToKnownTerminalGrid() {
        let image = renderTerminalPreview(
            contents: String(repeating: "W", count: 400),
            style: TerminalPreviewStyle(
                backgroundColor: .black,
                normalTextColor: .white,
                fontName: nil,
                fontSize: 18
            ),
            columnCount: 80,
            rowCount: 24,
            windowFrame: CGRect(x: 0, y: 0, width: 960, height: 640)
        )

        XCTAssertGreaterThan(textRowClusterCount(from: image), 1)
    }

    func testTerminalPreviewRendererUsesDynamicTerminalGridAndWindowAspect() {
        let scenarios: [(name: String, columns: Int, rows: Int, frame: CGRect)] = [
            ("standard 80x24", 80, 24, CGRect(x: 0, y: 0, width: 960, height: 640)),
            ("wide 132x30", 132, 30, CGRect(x: 0, y: 0, width: 1440, height: 900)),
            ("large 190x44", 190, 44, CGRect(x: 0, y: 0, width: 2048, height: 1282))
        ]
        let leftText = "DONE Compiled successfully in 3201ms"
        let rightAlignedText = "下午10:07:38"

        for scenario in scenarios {
            let spacing = max(
                1,
                scenario.columns
                    - terminalDisplayColumnCount(leftText)
                    - terminalDisplayColumnCount(rightAlignedText)
            )
            let image = renderTerminalPreview(
                contents: leftText + String(repeating: " ", count: spacing) + rightAlignedText,
                style: TerminalPreviewStyle(
                    backgroundColor: .black,
                    normalTextColor: .white,
                    fontName: nil,
                    fontSize: 13
                ),
                columnCount: scenario.columns,
                rowCount: scenario.rows,
                windowFrame: scenario.frame
            )
            let metrics = textInkMetrics(from: image)
            let imageSize = image?.size ?? .zero
            let imageAspect = Double(imageSize.width / max(1, imageSize.height))
            let frameAspect = Double(scenario.frame.width / scenario.frame.height)

            XCTAssertEqual(metrics.rowClusters, 1, scenario.name)
            XCTAssertLessThanOrEqual(
                Int(imageSize.width) - metrics.maxX,
                24,
                scenario.name
            )
            XCTAssertEqual(imageAspect, frameAspect, accuracy: 0.01, scenario.name)
        }
    }

    func testTerminalPreviewRendererUsesContentsBeforeFallbackWhenTrailingRowsAreBlank() {
        let image = renderTerminalPreview(
            contents: "X" + String(repeating: "\n", count: 80),
            style: TerminalPreviewStyle(
                backgroundColor: .black,
                normalTextColor: .white,
                fontName: nil,
                fontSize: 18
            ),
            fallbackTitle: String(repeating: "W", count: 80)
        )

        XCTAssertNotNil(image)
        XCTAssertLessThan(textInkWidth(from: image), 80)
    }

    func testTerminalPreviewRendererPreparesOnlyVisibleTailRowsFromLongScrollback() {
        let hiddenScrollback = (0..<1_000)
            .map { "hidden-\($0)-" + String(repeating: "W", count: 120) }
            .joined(separator: "\n")
        let lines = TerminalPreviewRenderer.terminalLinesForTesting(
            contents: hiddenScrollback + "\nvisible-1\nvisible-2",
            fallbackTitle: nil,
            columnCount: 80,
            rowCount: 2,
            maxRows: 160
        )

        XCTAssertEqual(lines, ["visible-1", "visible-2"])
    }

    func testTerminalPreviewTextLayoutUsesTerminalCellsForTabsWideAndZeroWidthCharacters() {
        let runs = TerminalPreviewTextLayout.cellRuns(
            in: "A\tB\u{200B}界",
            maxColumns: 12
        )

        XCTAssertEqual(runs.map(\.text), ["A", "B", "界"])
        XCTAssertEqual(runs.map(\.column), [0, 8, 9])
        XCTAssertEqual(runs.map(\.columnWidth), [1, 1, 2])
    }

    func testTerminalPreviewRendererStripsANSISequencesBeforePreparingRows() {
        let lines = TerminalPreviewRenderer.terminalLinesForTesting(
            contents: "\u{001B}[31mred\u{001B}[0m ok",
            fallbackTitle: nil,
            columnCount: 80,
            rowCount: 1,
            maxRows: 160
        )

        XCTAssertEqual(lines, ["red ok"])
    }

    func testTerminalPreviewProviderMatchesAXIndexToTerminalSnapshot() async {
        let currentApp = NSRunningApplication.current
        let adapter = FakeTerminalScriptingAdapter(
            result: .success([
                makeTerminalSnapshot(
                    flatIndex: 0,
                    title: "Server",
                    contents: "first",
                    backgroundColor: NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1)
                ),
                makeTerminalSnapshot(
                    flatIndex: 1,
                    title: "Shell",
                    contents: "second",
                    backgroundColor: NSColor(calibratedRed: 0, green: 0, blue: 1, alpha: 1)
                )
            ])
        )
        let provider = TerminalWindowPreviewProvider(adapter: adapter)
        let request = makePreviewRequest(
            appID: "com.apple.Terminal",
            windowID: "cg:\(currentApp.processIdentifier):24242",
            title: "Runtime Terminal Window",
            activationHandleID: AXWindowInspector.makeWindowID(
                pid: currentApp.processIdentifier,
                index: 1
            )
        )

        let result = await provider.preview(for: request)

        XCTAssertEqual(adapter.callCount, 1)
        XCTAssertEqual(result.source, .special(appID: "com.apple.Terminal"))
        XCTAssertNotNil(result.image)
        let color = sampledBackgroundColor(from: result.image)
        XCTAssertGreaterThan(color?.blueComponent ?? 0, 0.8)
        XCTAssertLessThan(color?.redComponent ?? 1, 0.2)
    }

    func testTerminalPreviewProviderPrefersTerminalWindowIDWhenAXIndexIncludesHelpTag() async {
        let currentApp = NSRunningApplication.current
        let adapter = FakeTerminalScriptingAdapter(
            result: .success([
                makeTerminalSnapshot(
                    flatIndex: 0,
                    title: "Session",
                    contents: "session",
                    terminalWindowID: 19_828,
                    windowTitle: "session-viewer",
                    backgroundColor: NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1)
                ),
                makeTerminalSnapshot(
                    flatIndex: 1,
                    title: "Build",
                    contents: "build",
                    terminalWindowID: 138_245,
                    windowTitle: "fed-template-administrative-inspection",
                    backgroundColor: NSColor(calibratedRed: 0, green: 1, blue: 0, alpha: 1)
                ),
                makeTerminalSnapshot(
                    flatIndex: 2,
                    title: "Shell",
                    contents: "shell",
                    terminalWindowID: 245_444,
                    windowTitle: "FlowTabApp — -bash — 190×44",
                    backgroundColor: NSColor(calibratedRed: 0, green: 0, blue: 1, alpha: 1)
                )
            ])
        )
        let provider = TerminalWindowPreviewProvider(adapter: adapter)
        let request = makePreviewRequest(
            appID: "com.apple.Terminal",
            windowID: "cg:\(currentApp.processIdentifier):245444",
            title: "FlowTabApp — -bash — 190×44",
            cgWindowID: 245_444,
            activationHandleID: AXWindowInspector.makeWindowID(
                pid: currentApp.processIdentifier,
                index: 3
            )
        )

        let result = await provider.preview(for: request)

        XCTAssertEqual(adapter.callCount, 1)
        XCTAssertEqual(result.source, .special(appID: "com.apple.Terminal"))
        XCTAssertNotNil(result.image)
        let color = sampledBackgroundColor(from: result.image)
        XCTAssertGreaterThan(color?.blueComponent ?? 0, 0.8)
        XCTAssertLessThan(color?.redComponent ?? 1, 0.2)
    }

    func testTerminalPreviewProviderReadsTerminalStateOnceForBatch() async {
        let currentApp = NSRunningApplication.current
        let adapter = FakeTerminalScriptingAdapter(
            result: .success([
                makeTerminalSnapshot(flatIndex: 0, title: "Server", contents: "first"),
                makeTerminalSnapshot(flatIndex: 1, title: "Shell", contents: "second")
            ])
        )
        let provider = TerminalWindowPreviewProvider(adapter: adapter)
        let requests = [
            makePreviewRequest(
                appID: "com.apple.Terminal",
                windowID: AXWindowInspector.makeWindowID(
                    pid: currentApp.processIdentifier,
                    index: 0
                ),
                title: "Server"
            ),
            makePreviewRequest(
                appID: "com.apple.Terminal",
                windowID: AXWindowInspector.makeWindowID(
                    pid: currentApp.processIdentifier,
                    index: 1
                ),
                title: "Shell"
            )
        ]

        let results = await provider.previews(for: requests)

        XCTAssertEqual(adapter.callCount, 1)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.image != nil })
        XCTAssertTrue(results.allSatisfy { $0.source == .special(appID: "com.apple.Terminal") })
    }

    func testTerminalPreviewProviderReturnsStructuredPermissionFailure() async {
        let adapter = FakeTerminalScriptingAdapter(result: .failure(.permissionDenied))
        let provider = TerminalWindowPreviewProvider(adapter: adapter)

        let result = await provider.preview(
            for: makePreviewRequest(appID: "com.apple.Terminal")
        )

        XCTAssertNil(result.image)
        XCTAssertEqual(result.failureReason, .permissionDenied)
        XCTAssertNil(result.source)
    }

    @MainActor
    func testLiveSwitcherModelUsesPreviewProviderResolverForTerminalPreview() async {
        let currentApp = NSRunningApplication.current
        let appID = "com.apple.Terminal"
        let windows = [
            WindowCandidate(
                id: AXWindowInspector.makeWindowID(pid: currentApp.processIdentifier, index: 0),
                title: "Server",
                isMinimized: false,
                lastActiveAt: 30
            ),
            WindowCandidate(
                id: AXWindowInspector.makeWindowID(pid: currentApp.processIdentifier, index: 1),
                title: "Shell",
                isMinimized: false,
                lastActiveAt: 20
            )
        ]
        let app = AppSwitchCandidate(
            id: appID,
            displayName: "Terminal",
            groupID: "terminal",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let (model, snapshotService) = makeAppSwitcherProjectionModel(app: app, context: context)
        model.runtimeProjectionMaintenanceEnabled = false
        let specialProvider = FakeSpecialWindowPreviewProvider(
            supportedAppID: appID,
            result: .success(
                image: makeColorImage(color: .systemGreen),
                resolvedWindowID: nil,
                titleBarStyle: .dark,
                source: .special(appID: appID)
            )
        )
        let genericProvider = FakeGenericWindowPreviewProvider(
            result: .failure(.transientSystemError)
        )
        model.previewProviderResolver = WindowPreviewProviderResolver(
            specialProviders: [specialProvider],
            genericProvider: genericProvider
        )

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.autoEnterWindowLayerIfPossible())
        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.lightweightSnapshotRequestCount(), 0)

        let published = expectation(description: "terminal preview provider published results")
        var cancellables: Set<AnyCancellable> = []
        model.objectWillChange.sink {
            published.fulfill()
        }.store(in: &cancellables)

        let initialSnapshot = model.windowPreviewSnapshotForTesting(visibleRange: 0..<2)
        XCTAssertTrue(initialSnapshot.isEmpty)

        await fulfillment(of: [published], timeout: 1.0)

        let completedSnapshot = model.windowPreviewSnapshotForTesting(visibleRange: 0..<2)
        XCTAssertEqual(completedSnapshot.count, 2)
        XCTAssertTrue(completedSnapshot.allSatisfy(\.hasImage))
        XCTAssertEqual(specialProvider.callCount, 2)
        XCTAssertEqual(genericProvider.callCount, 0)
        XCTAssertEqual(cancellables.count, 1)
    }

    @MainActor
    func testLiveSwitcherModelUsesFallbackWhenTerminalProviderFails() async {
        let currentApp = NSRunningApplication.current
        let appID = "com.apple.Terminal"
        let windows = [
            WindowCandidate(
                id: AXWindowInspector.makeWindowID(pid: currentApp.processIdentifier, index: 0),
                title: "Server",
                isMinimized: false,
                lastActiveAt: 30
            ),
            WindowCandidate(
                id: AXWindowInspector.makeWindowID(pid: currentApp.processIdentifier, index: 1),
                title: "Shell",
                isMinimized: false,
                lastActiveAt: 20
            )
        ]
        let app = AppSwitchCandidate(
            id: appID,
            displayName: "Terminal",
            groupID: "terminal",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let (model, snapshotService) = makeAppSwitcherProjectionModel(app: app, context: context)
        model.runtimeProjectionMaintenanceEnabled = false
        let specialProvider = FakeSpecialWindowPreviewProvider(
            supportedAppID: appID,
            result: .failure(.specialProviderUnavailable)
        )
        let genericProvider = FakeGenericWindowPreviewProvider(
            result: .success(
                image: makeColorImage(color: .systemRed),
                resolvedWindowID: 24_002,
                titleBarStyle: nil,
                source: .genericScreenshot
            )
        )
        model.previewProviderResolver = WindowPreviewProviderResolver(
            specialProviders: [specialProvider],
            genericProvider: genericProvider
        )

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.autoEnterWindowLayerIfPossible())
        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.lightweightSnapshotRequestCount(), 0)

        let published = expectation(description: "terminal preview failure published")
        var cancellables: Set<AnyCancellable> = []
        model.objectWillChange.sink {
            published.fulfill()
        }.store(in: &cancellables)

        let initialSnapshot = model.windowPreviewSnapshotForTesting(visibleRange: 0..<1)
        XCTAssertTrue(initialSnapshot.isEmpty)

        await fulfillment(of: [published], timeout: 1.0)

        let completedSnapshot = model.windowPreviewSnapshotForTesting(visibleRange: 0..<1)
        XCTAssertEqual(completedSnapshot.count, 1)
        XCTAssertFalse(completedSnapshot[0].hasImage)
        XCTAssertEqual(specialProvider.callCount, 1)
        XCTAssertEqual(genericProvider.callCount, 0)
        guard
            case let .failed(reason, retryAfterGeneration?) =
                model.previewCaptureStatesForTesting().values.first
        else {
            return XCTFail("Expected terminal provider failure state")
        }
        XCTAssertEqual(reason, .specialProviderUnavailable)
        XCTAssertEqual(retryAfterGeneration, model.previewCaptureGeneration + 1)
        XCTAssertEqual(cancellables.count, 1)
    }

    private func makePreviewRequest(
        appID: String,
        windowID: String? = nil,
        title: String = "Window",
        cgWindowID: CGWindowID? = 24_000,
        activationHandleID: String? = nil
    ) -> WindowPreviewRequest {
        let currentApp = NSRunningApplication.current
        let windowContext = RuntimeWindowContext(
            id: windowID ?? "window-1",
            title: title,
            isMinimized: false,
            ownerPID: currentApp.processIdentifier,
            cgWindowID: cgWindowID,
            activationHandleID: activationHandleID
        )
        return WindowPreviewRequest(
            appID: appID,
            bundleIdentifier: appID,
            ownerPID: currentApp.processIdentifier,
            windowID: windowContext.id,
            preferredCGWindowID: windowContext.cgWindowID,
            preferredTitle: windowContext.title,
            windowFrame: windowContext.frame,
            inferTitleBarStyle: true,
            activationHandleID: windowContext.activationHandleID
        )
    }

    private func renderTerminalPreview(
        contents: String,
        style: TerminalPreviewStyle = .default,
        fallbackTitle: String? = nil,
        columnCount: Int? = nil,
        rowCount: Int? = nil,
        windowFrame: CGRect? = nil
    ) -> NSImage? {
        let snapshot = makeTerminalSnapshot(
            flatIndex: 0,
            title: fallbackTitle ?? "Terminal",
            contents: contents,
            style: style,
            columnCount: columnCount,
            rowCount: rowCount
        )
        return TerminalPreviewRenderer.render(
            snapshot: snapshot,
            fallbackTitle: fallbackTitle,
            windowFrame: windowFrame
        )
    }

    private func makeTerminalSnapshot(
        flatIndex: Int,
        title: String,
        contents: String,
        terminalWindowID: CGWindowID? = nil,
        windowTitle: String = "",
        backgroundColor: NSColor = .black,
        style: TerminalPreviewStyle? = nil,
        columnCount: Int? = nil,
        rowCount: Int? = nil
    ) -> TerminalTabSnapshot {
        TerminalTabSnapshot(
            flatIndex: flatIndex,
            terminalWindowID: terminalWindowID,
            windowTitle: windowTitle,
            customTitle: title,
            contents: contents,
            columnCount: columnCount,
            rowCount: rowCount,
            style: style ?? TerminalPreviewStyle(
                backgroundColor: backgroundColor,
                normalTextColor: .white,
                fontName: nil,
                fontSize: 13
            )
        )
    }

    private func cgImage(from image: NSImage?) -> CGImage? {
        guard let image else { return nil }
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private func sampledBackgroundColor(from image: NSImage?) -> NSColor? {
        guard let cgImage = cgImage(from: image) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB)
    }

    private func textRowClusterCount(from image: NSImage?) -> Int {
        textInkMetrics(from: image).rowClusters
    }

    private func textInkWidth(from image: NSImage?) -> Int {
        let bounds = textInkBounds(from: image)
        return bounds.minX == Int.max ? 0 : bounds.maxX - bounds.minX + 1
    }

    private func textInkBounds(from image: NSImage?) -> (minX: Int, maxX: Int) {
        let metrics = textInkMetrics(from: image)
        return (metrics.minX, metrics.maxX)
    }

    private func textInkMetrics(from image: NSImage?) -> (minX: Int, maxX: Int, rowClusters: Int) {
        guard let cgImage = cgImage(from: image) else { return (Int.max, 0, 0) }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard
            bitmap.bitsPerSample == 8,
            bitmap.samplesPerPixel >= 3,
            !bitmap.isPlanar,
            let bitmapData = bitmap.bitmapData
        else {
            return textInkMetricsByColorLookup(bitmap)
        }

        var minX = Int.max
        var maxX = 0
        var clusters = 0
        var isInsideCluster = false

        for y in 0..<bitmap.pixelsHigh {
            var rowHasText = false
            for x in 0..<bitmap.pixelsWide {
                let pixelOffset = y * bitmap.bytesPerRow + x * bitmap.samplesPerPixel
                let brightness = Int(bitmapData[pixelOffset])
                    + Int(bitmapData[pixelOffset + 1])
                    + Int(bitmapData[pixelOffset + 2])
                if brightness > 600 {
                    rowHasText = true
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                }
            }
            if rowHasText, !isInsideCluster {
                clusters += 1
                isInsideCluster = true
            } else if !rowHasText {
                isInsideCluster = false
            }
        }

        return (minX, maxX, clusters)
    }

    private func textInkMetricsByColorLookup(_ bitmap: NSBitmapImageRep) -> (
        minX: Int,
        maxX: Int,
        rowClusters: Int
    ) {
        var minX = Int.max
        var maxX = 0
        var clusters = 0
        var isInsideCluster = false

        for y in 0..<bitmap.pixelsHigh {
            var rowHasText = false
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                if color.redComponent + color.greenComponent + color.blueComponent > 1.5 {
                    rowHasText = true
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                }
            }
            if rowHasText, !isInsideCluster {
                clusters += 1
                isInsideCluster = true
            } else if !rowHasText {
                isInsideCluster = false
            }
        }

        return (minX, maxX, clusters)
    }

    private func terminalDisplayColumnCount(_ text: String) -> Int {
        TerminalPreviewTextLayout.columnCount(for: text)
    }
}

private final class FakeSpecialWindowPreviewProvider: SpecialWindowPreviewProviding {
    private let supportedAppID: String
    private let result: WindowPreviewResult
    private let lock = NSLock()
    private var calls: [WindowPreviewRequest] = []

    init(supportedAppID: String, result: WindowPreviewResult) {
        self.supportedAppID = supportedAppID
        self.result = result
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls.count
    }

    func supports(_ request: WindowPreviewRequest) -> Bool {
        request.appID == supportedAppID
    }

    func previews(for requests: [WindowPreviewRequest]) async -> [WindowPreviewResult] {
        lock.lock()
        calls.append(contentsOf: requests)
        lock.unlock()
        return Array(repeating: result, count: requests.count)
    }
}

private final class FakeGenericWindowPreviewProvider: GenericWindowPreviewProviding {
    private let result: WindowPreviewResult
    private let lock = NSLock()
    private var batches: [[WindowPreviewRequest]] = []

    init(result: WindowPreviewResult) {
        self.result = result
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return batches.count
    }

    func previews(
        for requests: [WindowPreviewRequest],
        captureSemaphore: DispatchSemaphore?
    ) async -> [WindowPreviewResult] {
        lock.lock()
        batches.append(requests)
        lock.unlock()
        return Array(repeating: result, count: requests.count)
    }
}

private final class FakeTerminalScriptingAdapter: TerminalScriptingSnapshotProviding {
    private let result: Result<[TerminalTabSnapshot], TerminalScriptingSnapshotError>
    private let lock = NSLock()
    private var calls: [pid_t] = []

    init(result: Result<[TerminalTabSnapshot], TerminalScriptingSnapshotError>) {
        self.result = result
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls.count
    }

    func tabSnapshots(ownerPID: pid_t) -> Result<[TerminalTabSnapshot], TerminalScriptingSnapshotError> {
        lock.lock()
        calls.append(ownerPID)
        lock.unlock()
        return result
    }
}
