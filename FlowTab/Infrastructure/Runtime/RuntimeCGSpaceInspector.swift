import CoreGraphics
import Darwin
import Foundation

struct RuntimeSpaceTopologySpace: Equatable {
    let id: Int
    let displayID: CGDirectDisplayID?
    let isCurrent: Bool
}

struct RuntimeSpaceTopologySnapshot: Equatable {
    var currentSpaceIDByDisplay: [CGDirectDisplayID: Int]
    var spacesByID: [Int: RuntimeSpaceTopologySpace]
    var windowIDsBySpaceID: [Int: Set<CGWindowID>]
    var spaceIDsByCGWindowID: [CGWindowID: Set<Int>]
    var fullscreenWindowIDBySpaceID: [Int: CGWindowID]

    init(
        currentSpaceIDByDisplay: [CGDirectDisplayID: Int] = [:],
        spacesByID: [Int: RuntimeSpaceTopologySpace] = [:],
        windowIDsBySpaceID: [Int: Set<CGWindowID>] = [:],
        spaceIDsByCGWindowID: [CGWindowID: Set<Int>] = [:],
        fullscreenWindowIDBySpaceID: [Int: CGWindowID] = [:]
    ) {
        self.currentSpaceIDByDisplay = currentSpaceIDByDisplay
        self.spacesByID = spacesByID
        self.windowIDsBySpaceID = Dictionary(
            uniqueKeysWithValues: windowIDsBySpaceID.map { spaceID, windowIDs in
                (spaceID, Set(windowIDs))
            }
        )
        self.spaceIDsByCGWindowID = Dictionary(
            uniqueKeysWithValues: spaceIDsByCGWindowID.map { windowID, spaceIDs in
                (windowID, Set(spaceIDs.filter { $0 > 0 }))
            }
        )
        self.fullscreenWindowIDBySpaceID = fullscreenWindowIDBySpaceID
        for (windowID, spaceIDs) in self.spaceIDsByCGWindowID {
            for spaceID in spaceIDs {
                self.windowIDsBySpaceID[spaceID, default: []].insert(windowID)
            }
        }
        for (spaceID, windowIDs) in self.windowIDsBySpaceID where self.spacesByID[spaceID] == nil {
            self.spacesByID[spaceID] = RuntimeSpaceTopologySpace(
                id: spaceID,
                displayID: nil,
                isCurrent: currentSpaceIDByDisplay.values.contains(spaceID)
            )
            for windowID in windowIDs {
                self.spaceIDsByCGWindowID[windowID, default: []].insert(spaceID)
            }
        }
    }

    func diff(from previous: RuntimeSpaceTopologySnapshot?) -> RuntimeSpaceTopologyDiff {
        guard let previous else {
            let allSpaceIDs = Set(spacesByID.keys)
            return RuntimeSpaceTopologyDiff(
                addedSpaceIDs: allSpaceIDs,
                removedSpaceIDs: [],
                changedSpaceIDs: allSpaceIDs,
                affectedCGWindowIDs: Set(spaceIDsByCGWindowID.keys)
            )
        }

        let previousSpaceIDs = Set(previous.spacesByID.keys)
        let currentSpaceIDs = Set(spacesByID.keys)
        let addedSpaceIDs = currentSpaceIDs.subtracting(previousSpaceIDs)
        let removedSpaceIDs = previousSpaceIDs.subtracting(currentSpaceIDs)
        var changedSpaceIDs = addedSpaceIDs.union(removedSpaceIDs)

        for spaceID in currentSpaceIDs.intersection(previousSpaceIDs) {
            if spacesByID[spaceID] != previous.spacesByID[spaceID]
                || windowIDsBySpaceID[spaceID, default: []] != previous.windowIDsBySpaceID[spaceID, default: []]
                || fullscreenWindowIDBySpaceID[spaceID] != previous.fullscreenWindowIDBySpaceID[spaceID] {
                changedSpaceIDs.insert(spaceID)
            }
        }

        if currentSpaceIDByDisplay != previous.currentSpaceIDByDisplay {
            changedSpaceIDs.formUnion(currentSpaceIDByDisplay.values)
            changedSpaceIDs.formUnion(previous.currentSpaceIDByDisplay.values)
        }

        var affectedWindowIDs: Set<CGWindowID> = []
        for spaceID in changedSpaceIDs {
            affectedWindowIDs.formUnion(windowIDsBySpaceID[spaceID, default: []])
            affectedWindowIDs.formUnion(previous.windowIDsBySpaceID[spaceID, default: []])
            if let windowID = fullscreenWindowIDBySpaceID[spaceID] {
                affectedWindowIDs.insert(windowID)
            }
            if let windowID = previous.fullscreenWindowIDBySpaceID[spaceID] {
                affectedWindowIDs.insert(windowID)
            }
        }

        return RuntimeSpaceTopologyDiff(
            addedSpaceIDs: addedSpaceIDs,
            removedSpaceIDs: removedSpaceIDs,
            changedSpaceIDs: changedSpaceIDs,
            affectedCGWindowIDs: affectedWindowIDs
        )
    }
}

struct RuntimeSpaceTopologyDiff: Equatable {
    let addedSpaceIDs: Set<Int>
    let removedSpaceIDs: Set<Int>
    let changedSpaceIDs: Set<Int>
    let affectedCGWindowIDs: Set<CGWindowID>
}

protocol RuntimeSpaceTopologyProviding {
    func snapshot(for windowIDs: [CGWindowID]) -> RuntimeSpaceTopologySnapshot
}

protocol RuntimeCGWindowListProviding {
    func windowInfo(
        options: CGWindowListOption,
        relativeToWindow windowID: CGWindowID
    ) -> [[String: Any]]?
}

struct RuntimeSystemCGWindowListProvider: RuntimeCGWindowListProviding {
    func windowInfo(
        options: CGWindowListOption,
        relativeToWindow windowID: CGWindowID
    ) -> [[String: Any]]? {
        CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]]
    }
}

struct RuntimeSystemSpaceTopologyProvider: RuntimeSpaceTopologyProviding {
    func snapshot(for windowIDs: [CGWindowID]) -> RuntimeSpaceTopologySnapshot {
        RuntimeCGSpaceInspector.topologySnapshot(for: windowIDs)
    }
}

enum RuntimeCGSpaceInspector {
    private typealias MainConnectionIDFn = @convention(c) () -> UInt32
    private typealias CopySpacesForWindowsFn = @convention(c) (
        UInt32,
        Int32,
        CFArray
    ) -> Unmanaged<CFArray>?
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (UInt32) -> Unmanaged<CFArray>?

    private struct API {
        let mainConnectionID: MainConnectionIDFn
        let copySpacesForWindows: CopySpacesForWindowsFn
        let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn?
    }

    private static let allSpacesSelector: Int32 = 7

    static func spaceIDsByWindowID(_ windowIDs: [CGWindowID]) -> [CGWindowID: [Int]] {
        let snapshot = topologySnapshot(for: windowIDs)
        return Dictionary(uniqueKeysWithValues: snapshot.spaceIDsByCGWindowID.map { windowID, spaceIDs in
            (windowID, Array(spaceIDs).sorted())
        })
    }

    static func topologySnapshot(for windowIDs: [CGWindowID]) -> RuntimeSpaceTopologySnapshot {
        guard !windowIDs.isEmpty else { return RuntimeSpaceTopologySnapshot() }
        guard let api = runtimeAPI else { return RuntimeSpaceTopologySnapshot() }

        let connectionID = api.mainConnectionID()
        let uniqueWindowIDs = Array(Set(windowIDs)).sorted()
        var spaceIDsByWindowID: [CGWindowID: Set<Int>] = [:]
        spaceIDsByWindowID.reserveCapacity(uniqueWindowIDs.count)

        for windowID in uniqueWindowIDs {
            let queryWindowIDs = [NSNumber(value: windowID)] as CFArray
            let rawSpaceIDs = (
                api.copySpacesForWindows(connectionID, allSpacesSelector, queryWindowIDs)?
                    .takeRetainedValue() as? [NSNumber]
            ) ?? []
            guard !rawSpaceIDs.isEmpty else { continue }
            let normalizedSpaceIDs = Set(rawSpaceIDs.map(\.intValue).filter { $0 > 0 })
            guard !normalizedSpaceIDs.isEmpty else { continue }
            spaceIDsByWindowID[windowID] = normalizedSpaceIDs
        }

        let displayTopology = api.copyManagedDisplaySpaces?(connectionID)
            .map { parseManagedDisplaySpaces($0.takeRetainedValue()) } ?? DisplaySpaceTopology()

        return RuntimeSpaceTopologySnapshot(
            currentSpaceIDByDisplay: displayTopology.currentSpaceIDByDisplay,
            spacesByID: displayTopology.spacesByID,
            spaceIDsByCGWindowID: spaceIDsByWindowID
        )
    }

    private struct DisplaySpaceTopology {
        var currentSpaceIDByDisplay: [CGDirectDisplayID: Int] = [:]
        var spacesByID: [Int: RuntimeSpaceTopologySpace] = [:]
    }

    private static func parseManagedDisplaySpaces(_ rawDisplays: CFArray) -> DisplaySpaceTopology {
        guard let displayDictionaries = rawDisplays as? [[String: Any]] else {
            return DisplaySpaceTopology()
        }

        var topology = DisplaySpaceTopology()
        for display in displayDictionaries {
            guard let displayID = parseDisplayID(display["Display Identifier"]) else { continue }
            let currentSpaceID = parseSpaceID(display["Current Space"])
            if let currentSpaceID {
                topology.currentSpaceIDByDisplay[displayID] = currentSpaceID
            }
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for space in spaces {
                guard let spaceID = parseSpaceID(space["id64"] ?? space["ManagedSpaceID"]) else {
                    continue
                }
                topology.spacesByID[spaceID] = RuntimeSpaceTopologySpace(
                    id: spaceID,
                    displayID: displayID,
                    isCurrent: spaceID == currentSpaceID
                )
            }
        }
        return topology
    }

    private static func parseDisplayID(_ rawValue: Any?) -> CGDirectDisplayID? {
        if let number = rawValue as? NSNumber {
            return CGDirectDisplayID(number.uint32Value)
        }
        if let string = rawValue as? String, let value = UInt32(string) {
            return CGDirectDisplayID(value)
        }
        return nil
    }

    private static func parseSpaceID(_ rawValue: Any?) -> Int? {
        if let number = rawValue as? NSNumber {
            return number.intValue
        }
        if let dictionary = rawValue as? [String: Any] {
            return parseSpaceID(dictionary["id64"] ?? dictionary["ManagedSpaceID"])
        }
        if let string = rawValue as? String {
            return Int(string)
        }
        return nil
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
            copySpacesForWindows: copySpacesForWindows,
            copyManagedDisplaySpaces: loadSymbol(
                handles: handles,
                names: ["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"],
                as: CopyManagedDisplaySpacesFn.self
            )
        )
    }()
}
