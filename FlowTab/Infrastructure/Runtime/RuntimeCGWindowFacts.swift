import ApplicationServices
import Foundation

struct RuntimeCGWindowEntry {
    let id: CGWindowID
    let title: String?
    let bounds: CGRect?
    let isOnscreen: Bool
    let alpha: Double
    let storeType: Int
    let spaceIDs: [Int]

    init(
        id: CGWindowID,
        title: String?,
        bounds: CGRect?,
        isOnscreen: Bool,
        alpha: Double,
        storeType: Int,
        spaceIDs: [Int] = []
    ) {
        self.id = id
        self.title = title
        self.bounds = bounds
        self.isOnscreen = isOnscreen
        self.alpha = alpha
        self.storeType = storeType
        self.spaceIDs = spaceIDs
    }
}

struct RuntimeCGWindowCollection {
    let windowsByPID: [pid_t: [RuntimeCGWindowEntry]]
    let spaceTopologyDiff: RuntimeSpaceTopologyDiff?
}

enum RuntimeCGWindowFacts {
    private static let minimumValidWindowWidth: CGFloat = 80
    private static let minimumValidWindowHeight: CGFloat = 60
    private static let minimumValidWindowArea: CGFloat = 20_000
    private static let validWindowAlphaThreshold: Double = 0.001
    private static let standardBufferedStoreType: Int = 1

    static func passesValidityConstraints(_ window: RuntimeCGWindowEntry) -> Bool {
        guard window.alpha > validWindowAlphaThreshold else { return false }
        guard window.storeType == standardBufferedStoreType else { return false }
        guard let bounds = window.bounds?.standardized else { return false }
        guard bounds.width >= minimumValidWindowWidth else { return false }
        guard bounds.height >= minimumValidWindowHeight else { return false }
        return bounds.width * bounds.height >= minimumValidWindowArea
    }
}
