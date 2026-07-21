import AppKit
import Darwin
import Foundation

enum RuntimeSystemAppOrderProvider {
    private typealias CopyApplicationOrderFn = @convention(c) (
        Int32,
        Int32
    ) -> Unmanaged<CFArray>?
    private typealias CopyApplicationInformationItemFn = @convention(c) (
        Int32,
        CFTypeRef,
        CFString
    ) -> Unmanaged<CFTypeRef>?

    private struct API {
        let copyApplicationOrder: CopyApplicationOrderFn
        let copyApplicationInformationItem: CopyApplicationInformationItemFn
        let pidKey: CFString
    }

    // Dock uses the current LaunchServices session and includes hidden apps in its switch order.
    private static let currentSessionID: Int32 = -2
    private static let includeHiddenApplications: Int32 = 1

    static func collectOrderedPIDs(
        for runningApps: [NSRunningApplication]
    ) -> [pid_t]? {
        guard !runningApps.isEmpty else { return [] }
        guard
            let api = runtimeAPI,
            let applicationOrder = api.copyApplicationOrder(
                currentSessionID,
                includeHiddenApplications
            )?.takeRetainedValue()
        else {
            return nil
        }

        let runningPIDs = Set(runningApps.map(\.processIdentifier))
        var seenPIDs: Set<pid_t> = []
        var orderedPIDs: [pid_t] = []
        orderedPIDs.reserveCapacity(runningApps.count)

        for index in 0..<CFArrayGetCount(applicationOrder) {
            guard let pointer = CFArrayGetValueAtIndex(applicationOrder, index) else { continue }
            let applicationASN = Unmanaged<CFTypeRef>
                .fromOpaque(pointer)
                .takeUnretainedValue()
            guard
                let rawPID = api.copyApplicationInformationItem(
                    currentSessionID,
                    applicationASN,
                    api.pidKey
                )?.takeRetainedValue() as? NSNumber
            else {
                continue
            }
            let pid = pid_t(rawPID.int32Value)
            guard runningPIDs.contains(pid), seenPIDs.insert(pid).inserted else { continue }
            orderedPIDs.append(pid)
        }

        return orderedPIDs.isEmpty ? nil : orderedPIDs
    }

    // Runtime lookup lets an OS without these symbols use the current session's bootstrap order.
    private static let runtimeAPI: API? = {
        guard let handle = dlopen(
            "/System/Library/Frameworks/CoreServices.framework/Versions/A/CoreServices",
            RTLD_LAZY | RTLD_LOCAL
        ) else {
            return nil
        }
        guard
            let orderSymbol = dlsym(handle, "_LSCopyApplicationArrayInFrontToBackOrder"),
            let informationSymbol = dlsym(handle, "_LSCopyApplicationInformationItem"),
            let pidKeySymbol = dlsym(handle, "_kLSPIDKey"),
            let pidKey = pidKeySymbol.assumingMemoryBound(to: CFString?.self).pointee
        else {
            return nil
        }

        return API(
            copyApplicationOrder: unsafeBitCast(
                orderSymbol,
                to: CopyApplicationOrderFn.self
            ),
            copyApplicationInformationItem: unsafeBitCast(
                informationSymbol,
                to: CopyApplicationInformationItemFn.self
            ),
            pidKey: pidKey
        )
    }()
}
