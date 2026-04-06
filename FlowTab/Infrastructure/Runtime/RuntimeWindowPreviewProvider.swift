import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit

enum RuntimeWindowPreviewProvider {
    private struct LiveCGWindowEntry {
        let id: CGWindowID
        let title: String?
    }

    struct LiveWindowCandidateForTesting {
        let id: CGWindowID
        let title: String?
    }

    private struct StripStats {
        let meanLuminance: Double
        let stdLuminance: Double
        let meanSaturation: Double
        let sampleCount: Int

        var uniformityScore: Double {
            stdLuminance + meanSaturation * 0.6
        }
    }

    private static var hasLoggedScreenCapturePermissionWarning = false
    private static let shareableContentLookupTimeout: TimeInterval = 1.0
    private static let screenshotCaptureTimeout: TimeInterval = 1.0
    private static let maxPreviewCaptureDimension: CGFloat = 1_200

    static func captureWindowPreview(
        preferredWindowID: CGWindowID?,
        ownerPID: pid_t,
        preferredTitle: String?,
        inferTitleBarStyle: Bool
    ) -> (image: NSImage, resolvedWindowID: CGWindowID, titleBarStyle: WindowTitleBarStyleGuess?)? {
        guard ScreenCapturePermissionChecker.hasScreenCapturePermission else {
            if !hasLoggedScreenCapturePermissionWarning {
                RuntimeLog.info("Preview", "screen recording permission missing; window preview unavailable")
                hasLoggedScreenCapturePermissionWarning = true
            }
            return nil
        }

        let candidateIDs = candidateWindowIDs(
            preferredWindowID: preferredWindowID,
            ownerPID: ownerPID,
            preferredTitle: preferredTitle
        )
        guard !candidateIDs.isEmpty else {
            RuntimeLog.info(
                "Preview",
                "no candidate windows pid=\(ownerPID) preferredID=\(preferredWindowID.map(String.init) ?? "nil") title=\(preferredTitle ?? "<empty>")"
            )
            return nil
        }

        let shareableWindowsByID = fetchShareableWindowsByID()
        for candidateID in candidateIDs {
            guard let shareableWindow = shareableWindowsByID[candidateID] else { continue }
            guard let cgImage = captureWindow(shareableWindow: shareableWindow) else { continue }
            let titleBarStyle = inferTitleBarStyle ? estimateTitleBarStyle(from: cgImage) : nil
            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            RuntimeLog.info(
                "Preview",
                "capture success pid=\(ownerPID) windowID=\(candidateID) candidates=\(candidateIDs.count) titleBarStyle=\(titleBarStyle?.rawValue ?? "nil")"
            )
            return (image: image, resolvedWindowID: candidateID, titleBarStyle: titleBarStyle)
        }

        RuntimeLog.info(
            "Preview",
            "capture failed pid=\(ownerPID) preferredID=\(preferredWindowID.map(String.init) ?? "nil") title=\(preferredTitle ?? "<empty>") candidates=\(candidateIDs.map(String.init).joined(separator: ","))"
        )
        return nil
    }

    private static func candidateWindowIDs(
        preferredWindowID: CGWindowID?,
        ownerPID: pid_t,
        preferredTitle: String?
    ) -> [CGWindowID] {
        let liveWindows = collectLiveCGWindows(ownerPID: ownerPID)
        return candidateWindowIDs(
            preferredWindowID: preferredWindowID,
            preferredTitle: preferredTitle,
            liveWindows: liveWindows
        )
    }

    private static func candidateWindowIDs(
        preferredWindowID: CGWindowID?,
        preferredTitle: String?,
        liveWindows: [LiveCGWindowEntry]
    ) -> [CGWindowID] {
        var candidateIDs: [CGWindowID] = []
        var seen: Set<CGWindowID> = []

        func appendCandidate(_ id: CGWindowID) {
            guard !seen.contains(id) else { return }
            seen.insert(id)
            candidateIDs.append(id)
        }

        if let preferredWindowID {
            appendCandidate(preferredWindowID)
        }

        let trimmedTitle = preferredTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedTitle, !trimmedTitle.isEmpty {
            for window in liveWindows {
                guard let title = window.title else { continue }
                if title == trimmedTitle {
                    appendCandidate(window.id)
                }
            }
            for window in liveWindows {
                guard let title = window.title else { continue }
                if title.caseInsensitiveCompare(trimmedTitle) == .orderedSame {
                    appendCandidate(window.id)
                }
            }
        }

        for window in liveWindows {
            appendCandidate(window.id)
        }
        return candidateIDs
    }

    private static func collectLiveCGWindows(ownerPID: pid_t) -> [LiveCGWindowEntry] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        var windows: [LiveCGWindowEntry] = []
        windows.reserveCapacity(rawList.count)
        for item in rawList {
            guard let pid = item[kCGWindowOwnerPID as String] as? pid_t, pid == ownerPID else { continue }
            guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let windowNumber = item[kCGWindowNumber as String] as? NSNumber else { continue }
            let title = (item[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            windows.append(
                LiveCGWindowEntry(
                    id: CGWindowID(windowNumber.uint32Value),
                    title: title
                )
            )
        }
        return windows
    }

    private static func fetchShareableWindowsByID() -> [CGWindowID: SCWindow] {
        var shareableContent: SCShareableContent?
        var capturedError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
            shareableContent = content
            capturedError = error
            semaphore.signal()
        }

        let timeoutDate = DispatchTime.now() + shareableContentLookupTimeout
        guard semaphore.wait(timeout: timeoutDate) == .success else {
            RuntimeLog.info("Preview", "shareable-content lookup timed out")
            return [:]
        }
        if let capturedError {
            RuntimeLog.info("Preview", "shareable-content lookup failed error=\(capturedError.localizedDescription)")
            return [:]
        }
        guard let shareableContent else { return [:] }

        var windowsByID: [CGWindowID: SCWindow] = [:]
        windowsByID.reserveCapacity(shareableContent.windows.count)
        for window in shareableContent.windows {
            windowsByID[window.windowID] = window
        }
        return windowsByID
    }

    private static func captureWindow(shareableWindow: SCWindow) -> CGImage? {
        if #available(macOS 14.0, *) {
            return captureWindowUsingScreenshotManager(shareableWindow: shareableWindow)
        }
        return captureWindowUsingCoreGraphics(windowID: shareableWindow.windowID)
    }

    @available(macOS 14.0, *)
    private static func captureWindowUsingScreenshotManager(shareableWindow: SCWindow) -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: shareableWindow)
        let configuration = SCStreamConfiguration()
        let sourceWidth = max(1, shareableWindow.frame.width)
        let sourceHeight = max(1, shareableWindow.frame.height)
        let scaledSize = scaledPreviewSize(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        let width = scaledSize.width
        let height = scaledSize.height
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        var capturedImage: CGImage?
        var capturedError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
            capturedImage = image
            capturedError = error
            semaphore.signal()
        }

        let timeoutDate = DispatchTime.now() + screenshotCaptureTimeout
        guard semaphore.wait(timeout: timeoutDate) == .success else {
            RuntimeLog.info("Preview", "screenshot capture timed out windowID=\(shareableWindow.windowID)")
            return nil
        }
        if let capturedError {
            RuntimeLog.info(
                "Preview",
                "screenshot capture failed windowID=\(shareableWindow.windowID) error=\(capturedError.localizedDescription)"
            )
        }
        return capturedImage
    }

    private static func captureWindowUsingCoreGraphics(windowID: CGWindowID) -> CGImage? {
        guard
            let image = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            )
        else {
            RuntimeLog.info("Preview", "legacy capture failed windowID=\(windowID)")
            return nil
        }
        return scaledPreviewImageIfNeeded(image)
    }

    private static func scaledPreviewSize(
        sourceWidth: CGFloat,
        sourceHeight: CGFloat
    ) -> (width: Int, height: Int) {
        let scale = min(1, maxPreviewCaptureDimension / max(sourceWidth, sourceHeight))
        return (
            width: max(1, Int(ceil(sourceWidth * scale))),
            height: max(1, Int(ceil(sourceHeight * scale)))
        )
    }

    private static func scaledPreviewImageIfNeeded(_ image: CGImage) -> CGImage? {
        let sourceWidth = CGFloat(image.width)
        let sourceHeight = CGFloat(image.height)
        let scaledSize = scaledPreviewSize(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        guard scaledSize.width != image.width || scaledSize.height != image.height else {
            return image
        }
        guard
            let context = CGContext(
                data: nil,
                width: scaledSize.width,
                height: scaledSize.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return image
        }
        context.interpolationQuality = .medium
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: scaledSize.width,
                height: scaledSize.height
            )
        )
        return context.makeImage() ?? image
    }

    private static func estimateTitleBarStyle(from image: CGImage) -> WindowTitleBarStyleGuess? {
        let sourceWidth = image.width
        let sourceHeight = image.height
        guard sourceWidth >= 24, sourceHeight >= 24 else { return nil }

        let targetWidth = min(sourceWidth, 720)
        let scale = Double(targetWidth) / Double(sourceWidth)
        let targetHeight = max(
            1,
            Int((Double(sourceHeight) * scale).rounded(.toNearestOrAwayFromZero))
        )
        let bytesPerPixel = 4
        let bytesPerRow = targetWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: targetHeight * bytesPerRow)

        let didRender = pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            guard
                let context = CGContext(
                    data: baseAddress,
                    width: targetWidth,
                    height: targetHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else {
                return false
            }
            context.interpolationQuality = .low
            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: targetWidth,
                    height: targetHeight
                )
            )
            return true
        }
        guard didRender else { return nil }

        let bandHeight = max(8, min(48, Int(Double(targetHeight) * 0.11)))
        let horizontalInset = min(
            max(4, Int(Double(targetWidth) * 0.10)),
            max(0, targetWidth / 2 - 1)
        )
        let xStart = horizontalInset
        let xEnd = targetWidth - horizontalInset
        guard xEnd > xStart else { return nil }

        let topStrip = analyzeStrip(
            pixels: pixels,
            bytesPerRow: bytesPerRow,
            yRange: (targetHeight - bandHeight)..<targetHeight,
            xRange: xStart..<xEnd
        )
        let bottomStrip = analyzeStrip(
            pixels: pixels,
            bytesPerRow: bytesPerRow,
            yRange: 0..<bandHeight,
            xRange: xStart..<xEnd
        )
        guard
            let strip = preferredStrip(top: topStrip, bottom: bottomStrip),
            strip.sampleCount >= 160
        else {
            return nil
        }
        guard strip.uniformityScore <= 0.30 else { return nil }

        if strip.meanLuminance <= 0.47 {
            return .dark
        }
        if strip.meanLuminance >= 0.60 {
            return .light
        }
        if strip.stdLuminance <= 0.10, strip.meanSaturation <= 0.17 {
            return strip.meanLuminance < 0.53 ? .dark : .light
        }
        return nil
    }

    private static func preferredStrip(
        top: StripStats?,
        bottom: StripStats?
    ) -> StripStats? {
        switch (top, bottom) {
        case (nil, nil):
            return nil
        case let (top?, nil):
            return top
        case let (nil, bottom?):
            return bottom
        case let (top?, bottom?):
            return top.uniformityScore <= bottom.uniformityScore ? top : bottom
        }
    }

    private static func analyzeStrip(
        pixels: [UInt8],
        bytesPerRow: Int,
        yRange: Range<Int>,
        xRange: Range<Int>
    ) -> StripStats? {
        var luminanceSum = 0.0
        var luminanceSquareSum = 0.0
        var saturationSum = 0.0
        var sampleCount = 0

        for y in yRange {
            let rowOffset = y * bytesPerRow
            for x in xRange {
                let base = rowOffset + x * 4
                let alpha = Double(pixels[base + 3]) / 255.0
                guard alpha >= 0.90 else { continue }

                let normalizer = max(alpha, 0.0001)
                let red = min(1.0, Double(pixels[base]) / 255.0 / normalizer)
                let green = min(1.0, Double(pixels[base + 1]) / 255.0 / normalizer)
                let blue = min(1.0, Double(pixels[base + 2]) / 255.0 / normalizer)
                let maxChannel = max(red, max(green, blue))
                let minChannel = min(red, min(green, blue))
                let saturation = maxChannel > 0 ? (maxChannel - minChannel) / maxChannel : 0
                let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

                luminanceSum += luminance
                luminanceSquareSum += luminance * luminance
                saturationSum += saturation
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return nil }
        let meanLuminance = luminanceSum / Double(sampleCount)
        let variance = max(
            0,
            luminanceSquareSum / Double(sampleCount) - meanLuminance * meanLuminance
        )
        return StripStats(
            meanLuminance: meanLuminance,
            stdLuminance: sqrt(variance),
            meanSaturation: saturationSum / Double(sampleCount),
            sampleCount: sampleCount
        )
    }

    static func guessTitleBarStyleForTesting(from image: CGImage) -> WindowTitleBarStyleGuess? {
        estimateTitleBarStyle(from: image)
    }

    static func candidateWindowIDsForTesting(
        preferredWindowID: CGWindowID?,
        ownerPID: pid_t,
        preferredTitle: String?
    ) -> [CGWindowID] {
        candidateWindowIDs(
            preferredWindowID: preferredWindowID,
            ownerPID: ownerPID,
            preferredTitle: preferredTitle
        )
    }

    static func candidateWindowIDsForTesting(
        preferredWindowID: CGWindowID?,
        preferredTitle: String?,
        liveWindows: [LiveWindowCandidateForTesting]
    ) -> [CGWindowID] {
        candidateWindowIDs(
            preferredWindowID: preferredWindowID,
            preferredTitle: preferredTitle,
            liveWindows: liveWindows.map { LiveCGWindowEntry(id: $0.id, title: $0.title) }
        )
    }

    static func scaledPreviewSizeForTesting(
        sourceWidth: CGFloat,
        sourceHeight: CGFloat
    ) -> (width: Int, height: Int) {
        scaledPreviewSize(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
    }

    static func scaledPreviewImageIfNeededForTesting(_ image: CGImage) -> CGImage? {
        scaledPreviewImageIfNeeded(image)
    }
}

enum ScreenCapturePermissionChecker {
    static var hasPermissionOverrideForTesting: (() -> Bool)?
    static var requestPermissionOverrideForTesting: (() -> Bool)?

    private static var supportsScreenCapturePermissionAPI: Bool {
        if #available(macOS 10.15, *) {
            return true
        }
        return false
    }

    static var hasScreenCapturePermission: Bool {
        resolvePermission(
            testingOverride: hasPermissionOverrideForTesting,
            launchOverride: FlowTabTestLaunchOptions.screenCaptureTrustedOverride,
            supportsPermissionAPI: supportsScreenCapturePermissionAPI,
            systemPermissionProvider: { CGPreflightScreenCaptureAccess() }
        )
    }

    @discardableResult
    static func requestScreenCapturePermission() -> Bool {
        resolvePermission(
            testingOverride: requestPermissionOverrideForTesting,
            launchOverride: FlowTabTestLaunchOptions.screenCaptureTrustedOverride,
            supportsPermissionAPI: supportsScreenCapturePermissionAPI,
            systemPermissionProvider: { CGRequestScreenCaptureAccess() }
        )
    }

    private static func resolvePermission(
        testingOverride: (() -> Bool)?,
        launchOverride: Bool?,
        supportsPermissionAPI: Bool,
        systemPermissionProvider: () -> Bool
    ) -> Bool {
        if let testingOverride {
            return testingOverride()
        }
        if let launchOverride {
            return launchOverride
        }
        guard supportsPermissionAPI else {
            return true
        }
        return systemPermissionProvider()
    }

    static func resolvePermissionForTesting(
        testingOverride: (() -> Bool)?,
        launchOverride: Bool?,
        supportsPermissionAPI: Bool,
        systemPermissionProvider: () -> Bool
    ) -> Bool {
        resolvePermission(
            testingOverride: testingOverride,
            launchOverride: launchOverride,
            supportsPermissionAPI: supportsPermissionAPI,
            systemPermissionProvider: systemPermissionProvider
        )
    }
}
