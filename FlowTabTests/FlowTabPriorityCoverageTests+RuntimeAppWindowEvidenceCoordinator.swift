import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testRuntimeAXWindowObservationBindingsNormalizeExactIdentityAndCount() {
        let collection = RuntimeAXWindowObservationBindingCollection(
            [
                RuntimeAXWindowObservationBinding(
                    appID: "com.example.normalized",
                    pid: 18_500,
                    expectedWindowCount: -1
                ),
                RuntimeAXWindowObservationBinding(
                    appID: "com.example.normalized",
                    pid: 18_500,
                    expectedWindowCount: 4
                ),
                RuntimeAXWindowObservationBinding(
                    appID: "com.example.current",
                    pid: 99_999,
                    expectedWindowCount: 2
                )
            ],
            currentPID: 99_999
        )

        XCTAssertEqual(
            collection.bindings,
            [
                RuntimeAXWindowObservationBinding(
                    appID: "com.example.normalized",
                    pid: 18_500,
                    expectedWindowCount: 4
                )
            ]
        )
    }

    @MainActor
    func testRuntimeAppWindowEvidenceCoordinatorSeedsOnceAndIgnoresIdenticalReconciliation() {
        let binding = RuntimeAXWindowObservationBinding(
            appID: "com.example.seeded",
            pid: 18_501,
            expectedWindowCount: 2
        )
        let monitor = RecordingRuntimeAXWindowBindingMonitor()
        let coordinator = RuntimeAppWindowEvidenceCoordinator(
            monitor: monitor,
            currentPID: 99_999,
            readAccessibilityPermission: { true },
            bindingProvider: { [binding] },
            onAppWindowEvidence: { _ in }
        )
        defer { coordinator.stop() }

        coordinator.start()
        coordinator.reconcileNow()

        XCTAssertEqual(monitor.rebinds, [[binding]])
    }

    @MainActor
    func testRuntimeAppWindowEvidenceCoordinatorDiffsLaunchTerminationAndPIDReuse() {
        let first = RuntimeAXWindowObservationBinding(
            appID: "com.example.first",
            pid: 18_502,
            expectedWindowCount: 1
        )
        let second = RuntimeAXWindowObservationBinding(
            appID: "com.example.second",
            pid: 18_503,
            expectedWindowCount: 0
        )
        let replacement = RuntimeAXWindowObservationBinding(
            appID: "com.example.replacement",
            pid: first.pid,
            expectedWindowCount: 0
        )
        let monitor = RecordingRuntimeAXWindowBindingMonitor()
        let coordinator = RuntimeAppWindowEvidenceCoordinator(
            monitor: monitor,
            currentPID: 99_999,
            readAccessibilityPermission: { true },
            bindingProvider: { [first] },
            onAppWindowEvidence: { _ in }
        )
        defer { coordinator.stop() }

        coordinator.start()
        coordinator.applicationDidLaunch(
            appID: second.appID,
            pid: second.pid
        )
        coordinator.applicationDidLaunch(
            appID: replacement.appID,
            pid: replacement.pid
        )
        coordinator.applicationDidTerminate(
            appID: first.appID,
            pid: first.pid
        )
        coordinator.applicationDidTerminate(
            appID: replacement.appID,
            pid: replacement.pid
        )

        XCTAssertEqual(monitor.rebinds, [
            [first],
            [first, second],
            [replacement, second],
            [second],
        ])
    }

    @MainActor
    func testRuntimeAppWindowEvidenceCoordinatorStopsAndReseedsAcrossPermissionChanges() {
        let initial = RuntimeAXWindowObservationBinding(
            appID: "com.example.initial",
            pid: 18_504,
            expectedWindowCount: 1
        )
        let restored = RuntimeAXWindowObservationBinding(
            appID: "com.example.restored",
            pid: 18_505,
            expectedWindowCount: 3
        )
        var isTrusted = true
        var providedBindings = [initial]
        let monitor = RecordingRuntimeAXWindowBindingMonitor()
        let coordinator = RuntimeAppWindowEvidenceCoordinator(
            monitor: monitor,
            currentPID: 99_999,
            readAccessibilityPermission: { isTrusted },
            bindingProvider: { providedBindings },
            onAppWindowEvidence: { _ in }
        )
        defer { coordinator.stop() }

        coordinator.start()
        isTrusted = false
        coordinator.reconcileNow()
        providedBindings = [restored]
        isTrusted = true
        coordinator.reconcileNow()

        XCTAssertEqual(monitor.stopCallCount, 1)
        XCTAssertEqual(monitor.rebinds, [[initial], [restored]])
    }

    @MainActor
    func testRuntimeAppWindowEvidenceCoordinatorUpdatesCountsFromSharedProjectionCommits() async {
        let notificationCenter = NotificationCenter()
        var binding = RuntimeAXWindowObservationBinding(
            appID: "com.example.count-feedback",
            pid: 18_507,
            expectedWindowCount: 1
        )
        let monitor = RecordingRuntimeAXWindowBindingMonitor()
        let coordinator = RuntimeAppWindowEvidenceCoordinator(
            monitor: monitor,
            notificationCenter: notificationCenter,
            currentPID: 99_999,
            readAccessibilityPermission: { true },
            bindingProvider: { [binding] },
            onAppWindowEvidence: { _ in }
        )
        defer { coordinator.stop() }

        coordinator.start()
        binding = RuntimeAXWindowObservationBinding(
            appID: binding.appID,
            pid: binding.pid,
            expectedWindowCount: 3
        )
        let publication = DispatchGroup()
        publication.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            notificationCenter.post(
                name: .runtimeAppSwitcherProjectionDidUpdate,
                object: nil
            )
            publication.leave()
        }
        XCTAssertEqual(
            publication.wait(timeout: .now() + .milliseconds(500)),
            .success
        )
        for _ in 0..<3 { await Task.yield() }

        XCTAssertEqual(monitor.rebinds, [
            [
                RuntimeAXWindowObservationBinding(
                    appID: binding.appID,
                    pid: binding.pid,
                    expectedWindowCount: 1
                )
            ],
            [binding],
        ])
    }

    func testRuntimeProjectionServingRoutesAXEvidenceBySourceAndReadbackState() {
        let service = RecordingRuntimeProjectionService()
        let observed = makeRuntimeAXWindowEvidence(
            source: .observedTransition,
            initialReadback: nil
        )
        let matchingReadback = makeRuntimeAXWindowEvidence(
            source: .initialReadback,
            initialReadback: RuntimeAXWindowInitialReadbackEvidence.evaluate(
                expectedWindowCount: 1,
                knownSwitchableWindowCount: 1,
                observedSwitchableWindowCount: 1,
                exactKnownWindowCount: 1,
                fetchErrorRawValue: 0,
                rawValueTypeDescription: "CFArray"
            )
        )
        let changedReadback = makeRuntimeAXWindowEvidence(
            source: .trailingReadback,
            initialReadback: RuntimeAXWindowInitialReadbackEvidence.evaluate(
                expectedWindowCount: 1,
                knownSwitchableWindowCount: 2,
                observedSwitchableWindowCount: 2,
                exactKnownWindowCount: 2,
                fetchErrorRawValue: 0,
                rawValueTypeDescription: "CFArray"
            )
        )

        service.consumeAXWindowChangeEvidence(observed)
        service.consumeAXWindowChangeEvidence(matchingReadback)
        service.consumeAXWindowChangeEvidence(changedReadback)

        XCTAssertEqual(service.appWindowDirtyEvidenceRecorded(), [observed])
        XCTAssertEqual(
            service.appWindowChangeEvidenceRecorded(),
            [changedReadback]
        )
    }

    private func makeRuntimeAXWindowEvidence(
        source: RuntimeAXWindowChangeEvidence.Source,
        initialReadback: RuntimeAXWindowInitialReadbackEvidence?
    ) -> RuntimeAXWindowChangeEvidence {
        RuntimeAXWindowChangeEvidence(
            appID: "com.example.evidence",
            pid: 18_506,
            generation: 1,
            source: source,
            observedTransitionCount: source == .observedTransition ? 1 : 0,
            changeKinds: source == .observedTransition ? [.created] : [],
            initialReadback: initialReadback
        )
    }
}

@MainActor
private final class RecordingRuntimeAXWindowBindingMonitor:
    RuntimeAXWindowChangeMonitoring
{
    var onAppWindowChanged: ((RuntimeAXWindowChangeEvidence) -> Void)?
    private(set) var rebinds: [[RuntimeAXWindowObservationBinding]] = []
    private(set) var stopCallCount = 0

    func rebind(_ bindings: [RuntimeAXWindowObservationBinding]) {
        rebinds.append(bindings)
    }

    func stop() {
        stopCallCount += 1
    }
}
