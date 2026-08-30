import CoreGraphics

struct AppKitSettingsPageIntrinsicHeightCache {
    private struct Entry {
        let width: CGFloat
        let height: CGFloat
    }

    private let widthTolerance: CGFloat = 0.5
    private var entry: Entry?

    func height(forWidth width: CGFloat) -> CGFloat? {
        guard let entry,
              abs(entry.width - width) <= widthTolerance
        else {
            return nil
        }
        return entry.height
    }

    mutating func store(height: CGFloat, forWidth width: CGFloat) {
        entry = Entry(width: width, height: height)
    }

    mutating func invalidate() {
        entry = nil
    }
}

struct AppKitSettingsPageLayoutSignature: Equatable {
    let viewportSize: CGSize
    let safeAreaTop: CGFloat
    let contentRevision: UInt64
}

struct AppKitSettingsPageLayoutMeasurementCache {
    private struct Entry {
        let signature: AppKitSettingsPageLayoutSignature
        let fittedSize: CGSize
    }

    private var entry: Entry?

    func fittedSize(
        for signature: AppKitSettingsPageLayoutSignature
    ) -> CGSize? {
        guard entry?.signature == signature else { return nil }
        return entry?.fittedSize
    }

    mutating func store(
        fittedSize: CGSize,
        for signature: AppKitSettingsPageLayoutSignature
    ) {
        entry = Entry(signature: signature, fittedSize: fittedSize)
    }

    mutating func invalidate() {
        entry = nil
    }
}
