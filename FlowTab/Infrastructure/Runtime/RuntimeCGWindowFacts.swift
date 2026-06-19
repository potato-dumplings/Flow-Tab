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
