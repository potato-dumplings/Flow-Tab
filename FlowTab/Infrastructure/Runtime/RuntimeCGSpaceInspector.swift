import CoreGraphics
import Darwin
import Foundation

enum RuntimeCGSpaceInspector {
    private typealias MainConnectionIDFn = @convention(c) () -> UInt32
    private typealias CopySpacesForWindowsFn = @convention(c) (
        UInt32,
        Int32,
        CFArray
    ) -> Unmanaged<CFArray>?

    private struct API {
        let mainConnectionID: MainConnectionIDFn
        let copySpacesForWindows: CopySpacesForWindowsFn
    }

    private static let allSpacesSelector: Int32 = 7

    static func spaceIDsByWindowID(_ windowIDs: [CGWindowID]) -> [CGWindowID: [Int]] {
        guard !windowIDs.isEmpty else { return [:] }
        guard let api = runtimeAPI else { return [:] }

        let connectionID = api.mainConnectionID()
        let uniqueWindowIDs = Array(Set(windowIDs)).sorted()
        var result: [CGWindowID: [Int]] = [:]
        result.reserveCapacity(uniqueWindowIDs.count)

        for windowID in uniqueWindowIDs {
            let queryWindowIDs = [NSNumber(value: windowID)] as CFArray
            let rawSpaceIDs = (
                api.copySpacesForWindows(connectionID, allSpacesSelector, queryWindowIDs)?
                    .takeRetainedValue() as? [NSNumber]
            ) ?? []
            guard !rawSpaceIDs.isEmpty else { continue }
            let normalizedSpaceIDs = Array(Set(rawSpaceIDs.map(\.intValue))).sorted()
            guard !normalizedSpaceIDs.isEmpty else { continue }
            result[windowID] = normalizedSpaceIDs
        }

        return result
    }

    private static func loadSymbol<T>(
        handles: [UnsafeMutableRawPointer?],
        names: [String],
        as type: T.Type
    ) -> T? {
        for handle in handles {
            guard let handle else { continue }
            for name in names {
                guard let symbol = dlsym(handle, name) else { continue }
                return unsafeBitCast(symbol, to: T.self)
            }
        }
        return nil
    }

    private static let runtimeAPI: API? = {
        let handles: [UnsafeMutableRawPointer?] = [
            UnsafeMutableRawPointer(bitPattern: -2),
            dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        ]

        guard
            let mainConnectionID = loadSymbol(
                handles: handles,
                names: ["SLSMainConnectionID", "CGSMainConnectionID"],
                as: MainConnectionIDFn.self
            ),
            let copySpacesForWindows = loadSymbol(
                handles: handles,
                names: ["SLSCopySpacesForWindows", "CGSCopySpacesForWindows"],
                as: CopySpacesForWindowsFn.self
            )
        else {
            return nil
        }

        return API(
            mainConnectionID: mainConnectionID,
            copySpacesForWindows: copySpacesForWindows
        )
    }()
}
