import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

enum RuntimeAXRemoteWindowResolver {
    private typealias AXUIElementID = UInt64
    private typealias CreateWithRemoteTokenFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    private static let maximumElementID: AXUIElementID = 1_000
    private static let scanTimeoutSeconds: TimeInterval = 0.100
    private static let remoteTokenByteCount = 20
    private static let remoteTokenMarker = Int32(0x636f636f)
    private static let switchableSubroles: Set<String> = [
        "AXStandardWindow",
        "AXDialog"
    ]

    static func windows(forPID pid: pid_t) -> [AXUIElement] {
        guard let createWithRemoteToken else { return [] }

        var token = makeRemoteToken(pid: pid, elementID: 0)
        var windows: [AXUIElement] = []
        let startedAt = Date.timeIntervalSinceReferenceDate
        for elementID in AXUIElementID(0)..<maximumElementID {
            token.replaceSubrange(
                12..<20,
                with: withUnsafeBytes(of: elementID) { Data($0) }
            )
            guard
                let element = createWithRemoteToken(token as CFData)?.takeRetainedValue(),
                isSwitchableWindow(element)
            else {
                if Date.timeIntervalSinceReferenceDate - startedAt >= scanTimeoutSeconds {
                    return windows
                }
                continue
            }
            windows.append(element)
            if Date.timeIntervalSinceReferenceDate - startedAt >= scanTimeoutSeconds {
                return windows
            }
        }
        return windows
    }

    static func mergedWindows(
        publicWindows: [AXUIElement],
        remoteWindows: [AXUIElement]
    ) -> [AXUIElement] {
        guard !remoteWindows.isEmpty else { return publicWindows }

        var seenKeys: Set<String> = []
        var merged: [AXUIElement] = []
        for window in publicWindows + remoteWindows {
            let key = deduplicationKey(for: window)
            guard seenKeys.insert(key).inserted else { continue }
            merged.append(window)
        }
        return merged
    }

    private static func makeRemoteToken(pid: pid_t, elementID: AXUIElementID) -> Data {
        var token = Data(count: remoteTokenByteCount)
        let zero = Int32(0)
        let marker = remoteTokenMarker
        let remoteElementID = elementID
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(4..<8, with: withUnsafeBytes(of: zero) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: marker) { Data($0) })
        token.replaceSubrange(12..<20, with: withUnsafeBytes(of: remoteElementID) { Data($0) })
        return token
    }

    private static func isSwitchableWindow(_ element: AXUIElement) -> Bool {
        guard let subrole = AXWindowInspector.subrole(for: element) else { return false }
        return switchableSubroles.contains(subrole)
    }

    private static func deduplicationKey(for window: AXUIElement) -> String {
        if let cgWindowID = AXWindowInspector.cgWindowID(for: window) {
            return "cg:\(cgWindowID)"
        }
        return "ax:\(Unmanaged.passUnretained(window).toOpaque())"
    }

    private static let createWithRemoteToken: CreateWithRemoteTokenFn? = {
        let candidateHandles = [
            UnsafeMutableRawPointer(bitPattern: -2),
            dlopen(
                "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
                RTLD_LAZY
            ),
            dlopen(
                "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
                RTLD_LAZY
            )
        ]
        for handle in candidateHandles {
            guard let handle else { continue }
            guard let symbol = dlsym(handle, "_AXUIElementCreateWithRemoteToken") else { continue }
            return unsafeBitCast(symbol, to: CreateWithRemoteTokenFn.self)
        }
        return nil
    }()
}

enum RuntimeAXRemoteWindowResolverForTesting {
    static func mergedWindows(
        publicWindows: [AXUIElement],
        remoteWindows: [AXUIElement]
    ) -> [AXUIElement] {
        RuntimeAXRemoteWindowResolver.mergedWindows(
            publicWindows: publicWindows,
            remoteWindows: remoteWindows
        )
    }
}
