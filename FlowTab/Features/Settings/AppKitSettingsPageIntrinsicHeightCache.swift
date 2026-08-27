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
