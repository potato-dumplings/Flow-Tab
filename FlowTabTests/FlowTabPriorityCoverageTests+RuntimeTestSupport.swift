import CoreGraphics
import Foundation
@testable import FlowTab

final class SpyMRUTracker: MRUTracking {
    private(set) var startCallCount = 0

    func startIfNeeded() {
        startCallCount += 1
    }
}

struct FixedRuntimeCGWindowListProvider: RuntimeCGWindowListProviding {
    let rawWindowInfo: [[String: Any]]

    func windowInfo(
        options: CGWindowListOption,
        relativeToWindow windowID: CGWindowID
    ) -> [[String: Any]]? {
        rawWindowInfo
    }
}

struct FixedRuntimeSpaceTopologyProvider: RuntimeSpaceTopologyProviding {
    let snapshot: RuntimeSpaceTopologySnapshot

    func snapshot(for windowIDs: [CGWindowID]) -> RuntimeSpaceTopologySnapshot {
        snapshot
    }
}

func makeRawCGWindowInfo(
    pid: pid_t,
    windowID: CGWindowID,
    title: String,
    bounds: CGRect = CGRect(x: 10, y: 20, width: 640, height: 480),
    isOnscreen: Bool = true,
    layer: Int = 0
) -> [String: Any] {
    [
        kCGWindowOwnerPID as String: pid,
        kCGWindowLayer as String: layer,
        kCGWindowNumber as String: NSNumber(value: windowID),
        kCGWindowName as String: title,
        kCGWindowBounds as String: [
            "X": bounds.origin.x,
            "Y": bounds.origin.y,
            "Width": bounds.width,
            "Height": bounds.height
        ],
        kCGWindowIsOnscreen as String: NSNumber(value: isOnscreen),
        kCGWindowAlpha as String: NSNumber(value: 1.0),
        kCGWindowStoreType as String: NSNumber(value: 1)
    ]
}
