#if FLOWTAB_TESTING
import ApplicationServices
import Foundation

enum RuntimeAXRemoteWindowResolverForTesting {
    typealias ScanPolicy = RuntimeAXRemoteWindowResolver.RuntimeAXRemoteScanPolicy
    typealias ScanUseCase = RuntimeAXRemoteWindowResolver.RuntimeAXRemoteScanUseCase
    typealias ResolveFailureReason = RuntimeAXRemoteWindowResolver.RemoteAXResolveFailureReason
    typealias ResolveResult = RuntimeAXRemoteWindowResolver.RemoteAXResolveResult

    static func remoteToken(pid: pid_t, elementID: UInt64) -> Data {
        RuntimeAXRemoteWindowResolver.remoteToken(
            pid: pid,
            elementID: elementID
        )
    }

    static func scanCompleteness(
        scannedCount: Int,
        timedOut: Bool
    ) -> RuntimeAXRemoteWindowResolver.RemoteScanCompleteness {
        RuntimeAXRemoteWindowResolver.scanCompleteness(
            scannedCount: scannedCount,
            timedOut: timedOut
        )
    }

    static func scanCompleteness(
        scannedCount: Int,
        timedOut: Bool,
        policy: ScanPolicy
    ) -> RuntimeAXRemoteWindowResolver.RemoteScanCompleteness {
        RuntimeAXRemoteWindowResolver.scanCompleteness(
            scannedCount: scannedCount,
            timedOut: timedOut,
            policy: policy
        )
    }

    static func scanPolicy(for useCase: ScanUseCase) -> ScanPolicy {
        RuntimeAXRemoteWindowResolver.scanPolicy(for: useCase)
    }

    static func shouldIncludeRemoteWindows(
        allCGWindows: [RuntimeCGWindowEntry],
        publicSwitchableWindowCount: Int,
        publicFetchSucceeded: Bool = true
    ) -> Bool {
        RuntimeAXRemoteWindowResolver.shouldIncludeRemoteWindows(
            allCGWindows: allCGWindows,
            publicSwitchableWindowCount: publicSwitchableWindowCount,
            publicFetchSucceeded: publicFetchSucceeded
        )
    }

    static func remoteAXResolveResult(
        element: AXUIElement?,
        elementID: UInt64,
        expectedPID: pid_t? = nil
    ) -> ResolveResult {
        RuntimeAXRemoteWindowResolver.remoteAXResolveResult(
            element: element,
            elementID: elementID,
            expectedPID: expectedPID
        )
    }

    static func resolveFailureReason(
        forSubrole subrole: String?
    ) -> ResolveFailureReason? {
        RuntimeAXRemoteWindowResolver.resolveFailureReason(forSubrole: subrole)
    }

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
#endif
