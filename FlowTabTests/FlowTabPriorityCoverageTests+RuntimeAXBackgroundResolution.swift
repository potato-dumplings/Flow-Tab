import AppKit
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testAXWindowInspectorResolvesRemoteWindowsWithoutWaitingForMainThreadWhenRequestedFromBackground() {
        XCTAssertTrue(Thread.isMainThread)
        let previousTrustedOverride =
            AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousRemoteOverride =
            AXWindowInspector.remoteWindowsResolverOverrideForTesting
        let previousRemoteScanOverride =
            AXWindowInspector.remoteWindowScanResultOverrideForTesting
        let evidence = RuntimeAXBackgroundResolutionEvidence()
        let workerStarted = DispatchSemaphore(value: 0)
        let resolverInvoked = DispatchSemaphore(value: 0)
        let fetchCompleted = expectation(
            description: "Background remote AX window fetch completed"
        )

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AXWindowInspector.remoteWindowScanResultOverrideForTesting = nil
        AXWindowInspector.remoteWindowsResolverOverrideForTesting = { _ in
            evidence.recordResolverInvocation(threadIsMain: Thread.isMainThread)
            resolverInvoked.signal()
            return []
        }
        defer {
            AccessibilityPermissionChecker.isTrustedOverrideForTesting =
                previousTrustedOverride
            AXWindowInspector.remoteWindowScanResultOverrideForTesting =
                previousRemoteScanOverride
            AXWindowInspector.remoteWindowsResolverOverrideForTesting =
                previousRemoteOverride
        }

        DispatchQueue(label: "FlowTabTests.AXBackgroundRemoteResolution").async {
            evidence.recordWorkerStarted()
            workerStarted.signal()
            defer {
                evidence.recordFetchCompleted()
                fetchCompleted.fulfill()
            }
            _ = AXWindowInspector.windowsFetchResult(
                for: NSRunningApplication.current,
                includeRemoteWindows: true
            )
        }

        XCTAssertEqual(
            workerStarted.wait(
                timeout: .now()
                    + RuntimeAXBackgroundResolutionTestPolicy.workerStartWatchdog
            ),
            .success,
            "Background AX worker did not start. \(evidence.diagnosticSummary)"
        )

        let resolverResult = resolverInvoked.wait(
            timeout: .now()
                + RuntimeAXBackgroundResolutionTestPolicy
                    .resolverInvocationWatchdog
        )
        XCTAssertEqual(
            resolverResult,
            .success,
            """
            Remote AX scanning must reach its resolver without synchronously waiting for \
            the busy main thread. \(evidence.diagnosticSummary)
            """
        )

        wait(
            for: [fetchCompleted],
            timeout: RuntimeAXBackgroundResolutionTestPolicy
                .fetchCompletionWatchdog
        )
        XCTAssertTrue(evidence.didComplete, evidence.diagnosticSummary)
        XCTAssertEqual(
            evidence.resolverThreadIsMain,
            false,
            evidence.diagnosticSummary
        )
    }
}

private enum RuntimeAXBackgroundResolutionTestPolicy {
    static let workerStartWatchdog: DispatchTimeInterval = .seconds(2)
    static let resolverInvocationWatchdog: DispatchTimeInterval = .seconds(2)
    static let fetchCompletionWatchdog: TimeInterval = 2
}

private final class RuntimeAXBackgroundResolutionEvidence: @unchecked Sendable {
    private let lock = NSLock()
    private var workerStarted = false
    private var recordedResolverThreadIsMain: Bool?
    private var fetchCompleted = false

    var resolverThreadIsMain: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return recordedResolverThreadIsMain
    }

    var didComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fetchCompleted
    }

    var diagnosticSummary: String {
        lock.lock()
        defer { lock.unlock() }
        return """
        workerStarted=\(workerStarted) \
        resolverThreadIsMain=\(String(describing: recordedResolverThreadIsMain)) \
        fetchCompleted=\(fetchCompleted)
        """
    }

    func recordWorkerStarted() {
        lock.lock()
        workerStarted = true
        lock.unlock()
    }

    func recordResolverInvocation(threadIsMain: Bool) {
        lock.lock()
        recordedResolverThreadIsMain = threadIsMain
        lock.unlock()
    }

    func recordFetchCompleted() {
        lock.lock()
        fetchCompleted = true
        lock.unlock()
    }
}
