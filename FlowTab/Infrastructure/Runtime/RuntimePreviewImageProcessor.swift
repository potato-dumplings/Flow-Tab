import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit

protocol RuntimePreviewImageProcessing {
    func trim(_ image: CGImage) -> CGImage
    func scale(_ image: CGImage) -> CGImage?
    func materialize(_ image: CGImage) -> NSImage
    func titleBarStyle(from image: CGImage, requested: Bool) -> WindowTitleBarStyleGuess?
}

struct RuntimePreviewImageProcessor: RuntimePreviewImageProcessing {
    static let maxPreviewCaptureDimension: CGFloat = 1_200
    static let previewTrimAlphaThreshold: UInt8 = 12

    func trim(_ image: CGImage) -> CGImage { Self.trimmedTransparentPaddingIfNeeded(image) }
    func scale(_ image: CGImage) -> CGImage? { Self.scaledPreviewImageIfNeeded(image) }
    func materialize(_ image: CGImage) -> NSImage {
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
    func titleBarStyle(from image: CGImage, requested: Bool) -> WindowTitleBarStyleGuess? {
        requested ? Self.estimateTitleBarStyle(from: image) : nil
    }
    static func trimmedTransparentPaddingIfNeeded(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 1, height > 1 else { return image }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        let rendered = pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            guard
                let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else {
                return false
            }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard rendered else { return image }

        func rowHasOpaquePixel(_ y: Int) -> Bool {
            let rowOffset = y * bytesPerRow
            for x in 0..<width {
                let alpha = pixels[rowOffset + x * bytesPerPixel + 3]
                if alpha >= previewTrimAlphaThreshold {
                    return true
                }
            }
            return false
        }

        func columnHasOpaquePixel(_ x: Int) -> Bool {
            for y in 0..<height {
                let alpha = pixels[y * bytesPerRow + x * bytesPerPixel + 3]
                if alpha >= previewTrimAlphaThreshold {
                    return true
                }
            }
            return false
        }

        var left = 0
        while left < width, !columnHasOpaquePixel(left) {
            left += 1
        }
        guard left < width else { return image }

        var right = width - 1
        while right > left, !columnHasOpaquePixel(right) {
            right -= 1
        }

        var bottom = 0
        while bottom < height, !rowHasOpaquePixel(bottom) {
            bottom += 1
        }

        var top = height - 1
        while top > bottom, !rowHasOpaquePixel(top) {
            top -= 1
        }

        guard left > 0 || right < width - 1 || bottom > 0 || top < height - 1 else {
            return image
        }

        let cropRect = CGRect(
            x: left,
            y: bottom,
            width: right - left + 1,
            height: top - bottom + 1
        )
        return image.cropping(to: cropRect) ?? image
    }
    static func scaledPreviewSize(
        sourceWidth: CGFloat,
        sourceHeight: CGFloat
    ) -> (width: Int, height: Int) {
        let scale = min(1, maxPreviewCaptureDimension / max(sourceWidth, sourceHeight))
        return (
            width: max(1, Int(ceil(sourceWidth * scale))),
            height: max(1, Int(ceil(sourceHeight * scale)))
        )
    }
    static func scaledPreviewImageIfNeeded(_ image: CGImage) -> CGImage? {
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
}
