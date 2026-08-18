import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

enum RuntimeAXRemoteWindowResolver {
    private typealias CreateWithRemoteTokenFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    typealias AXUIElementID = UInt64

    private enum RemoteTokenLayout {
        static let byteCount = 20
        static let pidRange = 0..<4
        static let zeroRange = 4..<8
        static let markerRange = 8..<12
        static let elementIDRange = 12..<20
        static let marker = Int32(0x636f636f)
    }

    enum RemoteScanCompleteness: Equatable {
        case unavailable
        case complete(scanned: Int)
    }

    enum RemoteAXResolveFailureReason: Equatable {
        case tokenUnavailable
        case ownerPIDUnavailable
        case ownerPIDMismatch(expected: pid_t, actual: pid_t)
        case missingSubrole
        case unsupportedSubrole(String)
    }

    enum RemoteAXResolveResult {
        case resolved(
            element: AXUIElement,
            elementID: AXUIElementID,
            subrole: String,
            cgWindowID: CGWindowID?
        )
        case rejected(
            elementID: AXUIElementID,
            reason: RemoteAXResolveFailureReason
        )

        var element: AXUIElement? {
            switch self {
            case let .resolved(element, _, _, _):
                return element
            case .rejected:
                return nil
            }
        }
    }

    struct WindowScanResult {
        let windows: [AXUIElement]
        let completeness: RemoteScanCompleteness
    }

    enum RuntimeAXRemoteScanUseCase: Equatable {
        case interactive
        case hotPath
        case background
    }

    struct RuntimeAXRemoteScanPolicy: Equatable {
        let useCase: RuntimeAXRemoteScanUseCase
        let maximumElementID: UInt64

        var elementIDs: Range<AXUIElementID> {
            AXUIElementID(0)..<maximumElementID
        }

        static let interactive = RuntimeAXRemoteScanPolicy(
            useCase: .interactive,
            maximumElementID: 750
        )

        static let hotPath = RuntimeAXRemoteScanPolicy(
            useCase: .hotPath,
            maximumElementID: 1_000
        )

        static let background = RuntimeAXRemoteScanPolicy(
            useCase: .background,
            maximumElementID: 2_000
        )

        static func policy(for useCase: RuntimeAXRemoteScanUseCase) -> RuntimeAXRemoteScanPolicy {
            switch useCase {
            case .interactive:
                return .interactive
            case .hotPath:
                return .hotPath
            case .background:
                return .background
            }
        }
    }

    private static let defaultScanPolicy = RuntimeAXRemoteScanPolicy.hotPath
    private static let switchableSubroles: Set<String> = [
        "AXStandardWindow",
        "AXDialog"
    ]

    static func shouldIncludeRemoteWindows(
        allCGWindows: [RuntimeCGWindowEntry],
        publicSwitchableWindowCount: Int,
        publicFetchSucceeded: Bool
    ) -> Bool {
        let userFacingCGWindows = userFacingCGWindowsForRemoteScanDecision(allCGWindows)
        guard userFacingCGWindows.contains(where: { window in
            RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: window.spaceIDs)
                || !window.isOnscreen
        }) else {
            return false
        }
        guard publicFetchSucceeded else { return true }
        return publicSwitchableWindowCount < userFacingCGWindows.count
    }

    static func windows(forPID pid: pid_t) -> [AXUIElement] {
        windowScanResult(forPID: pid).windows
    }

    static func windowScanResult(forPID pid: pid_t) -> WindowScanResult {
        windowScanResult(forPID: pid, policy: defaultScanPolicy)
    }

    static func windowScanResult(
        forPID pid: pid_t,
        useCase: RuntimeAXRemoteScanUseCase
    ) -> WindowScanResult {
        windowScanResult(
            forPID: pid,
            policy: RuntimeAXRemoteScanPolicy.policy(for: useCase)
        )
    }

    private static func windowScanResult(
        forPID pid: pid_t,
        policy: RuntimeAXRemoteScanPolicy
    ) -> WindowScanResult {
        guard let createWithRemoteToken else {
            return WindowScanResult(windows: [], completeness: .unavailable)
        }

        var token = remoteToken(pid: pid, elementID: 0)
        return scanElementIDs(policy: policy) { elementID in
            token.replaceSubrange(
                RemoteTokenLayout.elementIDRange,
                with: withUnsafeBytes(of: elementID) { Data($0) }
            )
            let element = createWithRemoteToken(token as CFData)?.takeRetainedValue()
            return remoteAXResolveResult(
                element: element,
                elementID: elementID,
                expectedPID: pid
            ).element
        }
    }

    static func scanElementIDs(
        policy: RuntimeAXRemoteScanPolicy,
        resolveElement: (AXUIElementID) -> AXUIElement?
    ) -> WindowScanResult {
        var windows: [AXUIElement] = []
        for elementID in policy.elementIDs {
            guard let resolvedElement = resolveElement(elementID) else { continue }
            windows.append(resolvedElement)
        }
        return WindowScanResult(
            windows: windows,
            completeness: .complete(scanned: policy.elementIDs.count)
        )
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

    static func remoteToken(pid: pid_t, elementID: AXUIElementID) -> Data {
        var token = Data(count: RemoteTokenLayout.byteCount)
        let zero = Int32(0)
        let marker = RemoteTokenLayout.marker
        let remoteElementID = elementID
        token.replaceSubrange(RemoteTokenLayout.pidRange, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(RemoteTokenLayout.zeroRange, with: withUnsafeBytes(of: zero) { Data($0) })
        token.replaceSubrange(RemoteTokenLayout.markerRange, with: withUnsafeBytes(of: marker) { Data($0) })
        token.replaceSubrange(RemoteTokenLayout.elementIDRange, with: withUnsafeBytes(of: remoteElementID) { Data($0) })
        return token
    }

    static func scanPolicy(
        for useCase: RuntimeAXRemoteScanUseCase
    ) -> RuntimeAXRemoteScanPolicy {
        RuntimeAXRemoteScanPolicy.policy(for: useCase)
    }

    static func remoteAXResolveResult(
        element: AXUIElement?,
        elementID: AXUIElementID,
        expectedPID: pid_t? = nil
    ) -> RemoteAXResolveResult {
        guard let element else {
            return .rejected(elementID: elementID, reason: .tokenUnavailable)
        }
        if let expectedPID, let failureReason = resolveFailureReason(
            forElementOwnerPID: element,
            expectedPID: expectedPID
        ) {
            return .rejected(elementID: elementID, reason: failureReason)
        }
        let subrole = AXWindowInspector.subrole(for: element)
        if let failureReason = resolveFailureReason(forSubrole: subrole) {
            return .rejected(elementID: elementID, reason: failureReason)
        }
        let resolvedSubrole = subrole ?? ""
        return .resolved(
            element: element,
            elementID: elementID,
            subrole: resolvedSubrole,
            cgWindowID: AXWindowInspector.cgWindowID(for: element)
        )
    }

    static func resolveFailureReason(
        forSubrole subrole: String?
    ) -> RemoteAXResolveFailureReason? {
        guard let subrole else { return .missingSubrole }
        guard switchableSubroles.contains(subrole) else {
            return .unsupportedSubrole(subrole)
        }
        return nil
    }

    fileprivate static func resolveFailureReason(
        forElementOwnerPID element: AXUIElement,
        expectedPID: pid_t
    ) -> RemoteAXResolveFailureReason? {
        var ownerPID: pid_t = 0
        guard AXUIElementGetPid(element, &ownerPID) == .success else {
            return .ownerPIDUnavailable
        }
        guard ownerPID == expectedPID else {
            return .ownerPIDMismatch(expected: expectedPID, actual: ownerPID)
        }
        return nil
    }

    private static func deduplicationKey(for window: AXUIElement) -> String {
        if let cgWindowID = AXWindowInspector.cgWindowID(for: window) {
            return "cg:\(cgWindowID)"
        }
        return "ax:\(Unmanaged.passUnretained(window).toOpaque())"
    }

    private static func userFacingCGWindowsForRemoteScanDecision(
        _ allCGWindows: [RuntimeCGWindowEntry]
    ) -> [RuntimeCGWindowEntry] {
        let validCGWindows = allCGWindows.filter(RuntimeCGWindowFacts.passesValidityConstraints)
        let fullscreenContentBounds = validCGWindows.compactMap { window -> CGRect? in
            guard RuntimeWindowTopologyClassifier.isLikelyOffDesktopFullscreenContent(
                bounds: window.bounds,
                spaceIDs: window.spaceIDs
            ) else { return nil }
            return window.bounds
        }
        return validCGWindows.filter { window in
            !RuntimeWindowTopologyClassifier.isLikelyDesktopWrapper(
                bounds: window.bounds,
                spaceIDs: window.spaceIDs,
                fullscreenContentBounds: fullscreenContentBounds
            )
        }
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
