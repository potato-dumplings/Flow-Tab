import Foundation
import XCTest

private enum FlowTabUITestRuntimeLogObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let fileEventWatchdog: TimeInterval = 2
    static let applicationReadinessWatchdog: TimeInterval = 10
    static let pressureIterations = 100
    static let triggerNotificationName =
        "io.github.potato-dumplings.flowtab.ui-test."
        + "open-in-app-window-switcher"

    static var triggerReceiptMarker: String {
        "received switcher trigger notification name="
            + triggerNotificationName
    }

    static var triggerCompletionMarker: String {
        "completed switcher trigger notification name="
            + triggerNotificationName
            + " presented=1 syntheticModifierHeld=1"
    }
}

extension FlowTabUITests {
    func testRuntimeLogOpenMutationReconciliationRequiresPostTriggerEvidence() {
        XCTAssertEqual(
            FlowTabUITestRuntimeLogObservationPolicy
                .openWindowMutationReconciliationWatchdog,
            8
        )
        var acceptsResolution = false
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let matchingSnapshot = FlowTabUITestRuntimeLogSnapshot(
            baselineFileEventGeneration: 7,
            fileEventGeneration: 8,
            contents: "runtimeAXDestroyed exact"
        )
        let owner = FlowTabUITestRuntimeLogObservationOwner(
            expectation: .allMarkers(["runtimeAXDestroyed exact"]),
            observationRegistration: { registered in
                callback = registered
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            acceptsResolution: { acceptsResolution },
            readback: { matchingSnapshot }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        callback?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)
        acceptsResolution = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value,
            matchingSnapshot
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testRuntimeLogSelectedMutationReconciliationPolicyPreservesCompatibleBound() {
        XCTAssertEqual(
            FlowTabUITestRuntimeLogObservationPolicy
                .selectedWindowMutationReconciliationWatchdog,
            8
        )
        XCTAssertTrue(
            FlowTabUITestRuntimeLogObservationPolicy
                .selectedWindowMutationReconciliationWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestRuntimeLogObservationPolicy
                .selectedWindowMutationReconciliationWatchdog,
            0
        )
    }

    func testRuntimeLogObservationPolicyPreservesCompatibleDefaults() {
        XCTAssertEqual(
            FlowTabUITestRuntimeLogObservationPolicy.defaultWatchdog,
            8
        )
        XCTAssertTrue(
            FlowTabUITestRuntimeLogObservationPolicy
                .defaultWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestRuntimeLogObservationPolicy.defaultWatchdog,
            0
        )
        XCTAssertEqual(
            FlowTabUITestRuntimeLogObservationPolicy.readbackCadence,
            0.2
        )
    }

    func testRuntimeLogRegexObservationReadsMockRuntimeTriggerDelivery()
        throws
    {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-suppress-home-on-launch",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "-showPermissionReminder",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(app)
        defer { app.terminate() }
        guard
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout:
                    FlowTabUITestRuntimeLogObservationTestPolicy
                        .applicationReadinessWatchdog
            )
        else {
            XCTFail(
                "unmetCondition=applicationState.runningForeground "
                    + "finalState=\(app.state)"
            )
            return
        }
        XCTAssertEqual(app.state, .runningForeground)

        let baseline = makeRuntimeLogFileSnapshot()
        postFlowTabUITestSwitcherTrigger(
            .global,
            traceLabel: "runtime-log-regex-observation"
        )
        let notificationNamePattern =
            NSRegularExpression.escapedPattern(
                for:
                    FlowTabUITestSwitcherTrigger.global
                    .notificationName.rawValue
            )
        waitForRuntimeLogFiles(
            matching:
                "completed switcher trigger notification name="
                + "\(notificationNamePattern) presented=1 "
                + "syntheticModifierHeld=1",
            since: baseline,
            description:
                "the mock runtime reports exact switcher-trigger delivery "
                + "with its primary modifier held"
        )
    }

    func testRuntimeLogFileObservationPublishesPostBaselineAppend()
        throws
    {
        let temporaryRoot = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "FlowTabRuntimeLogObservation-"
                    + UUID().uuidString,
                isDirectory: true
            )
        let logsDirectoryURL = temporaryRoot
            .appendingPathComponent(
                "FlowTab/logs",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: logsDirectoryURL,
            withIntermediateDirectories: true
        )
        let logURL = logsDirectoryURL
            .appendingPathComponent("FlowTab_test.log")
        let baselineLine = "before-baseline\n"
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: logURL.path,
                contents: Data(baselineLine.utf8)
            )
        )

        let baseline =
            FlowTabUITestRuntimeLogObservationBaseline(
                logsDirectoryURL: logsDirectoryURL
            )
        defer {
            baseline.cancel()
            try? FileManager.default.removeItem(
                at: temporaryRoot
            )
        }
        let marker = "post-baseline-marker"
        let expectation =
            FlowTabUITestRuntimeLogExpectation
                .allMarkers([marker])
        let owner =
            FlowTabUITestRuntimeLogObservationOwner(
                expectation: expectation,
                observationRegistration:
                    baseline
                        .fileEventObservationRegistration(),
                readback: baseline.makeReadback
            )
        owner.start()
        defer { owner.cancel() }
        XCTAssertNil(owner.resolvedEvidence)

        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        try handle.write(
            contentsOf: Data("\(marker)\n".utf8)
        )
        try handle.close()

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestRuntimeLogObservationTestPolicy
                    .fileEventWatchdog
        )

        XCTAssertEqual(
            evidence?.source,
            .notificationReadback
        )
        XCTAssertEqual(evidence?.value.contents, "\(marker)\n")
        XCTAssertGreaterThan(
            evidence?.value.fileEventGeneration ?? 0,
            evidence?.value
                .baselineFileEventGeneration ?? 0
        )
    }

    func testRuntimeLogFileObservationResetsOffsetAfterFileChange()
        throws
    {
        let temporaryRoot = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "FlowTabRuntimeLogFileChange-"
                    + UUID().uuidString,
                isDirectory: true
            )
        let logsDirectoryURL = temporaryRoot
            .appendingPathComponent("FlowTab/logs")
        try FileManager.default.createDirectory(
            at: logsDirectoryURL,
            withIntermediateDirectories: true
        )
        let logURL = logsDirectoryURL
            .appendingPathComponent("FlowTab_test.log")
        try Data(
            String(repeating: "baseline-", count: 16).utf8
        )
        .write(to: logURL)
        let truncationBaseline =
            FlowTabUITestRuntimeLogObservationBaseline(
                logsDirectoryURL: logsDirectoryURL
            )
        defer {
            truncationBaseline.cancel()
            try? FileManager.default.removeItem(
                at: temporaryRoot
            )
        }

        let handle = try FileHandle(forWritingTo: logURL)
        try handle.truncate(atOffset: 0)
        try handle.write(
            contentsOf: Data("after-truncation\n".utf8)
        )
        try handle.close()
        XCTAssertEqual(
            truncationBaseline.readContents(),
            "after-truncation\n"
        )

        try Data("replacement-baseline\n".utf8)
            .write(to: logURL)
        let replacementBaseline =
            FlowTabUITestRuntimeLogObservationBaseline(
                logsDirectoryURL: logsDirectoryURL
            )
        defer { replacementBaseline.cancel() }
        try Data("after-replacement\n".utf8)
            .write(to: logURL, options: .atomic)
        XCTAssertEqual(
            replacementBaseline.readContents(),
            "after-replacement\n"
        )
    }

    func testRuntimeLogObservationContractsAndEventResolution()
        throws
    {
        XCTAssertEqual(
            FlowTabUITestRuntimeLogObservationTestPolicy
                .applicationReadinessWatchdog,
            10
        )
        XCTAssertTrue(
            FlowTabUITestRuntimeLogObservationTestPolicy
                .applicationReadinessWatchdog.isFinite
        )
        XCTAssertGreaterThanOrEqual(
            FlowTabUITestRuntimeLogObservationTestPolicy
                .applicationReadinessWatchdog,
            FlowTabUITestRuntimeLogObservationTestPolicy
                .fileEventWatchdog
        )

        let regex = try NSRegularExpression(
            pattern: #"route=(event|readback)"#
        )
        let snapshot = FlowTabUITestRuntimeLogSnapshot(
            baselineFileEventGeneration: 7,
            fileEventGeneration: 8,
            contents:
                "required alternative route=event"
        )
        XCTAssertTrue(
            FlowTabUITestRuntimeLogExpectation
                .allMarkers(["required", "alternative"])
                .isSatisfied(by: snapshot)
        )
        XCTAssertTrue(
            FlowTabUITestRuntimeLogExpectation
                .regularExpression(
                    regex,
                    pattern: regex.pattern,
                    description: "event route"
                )
                .isSatisfied(by: snapshot)
        )
        var contents = "required"
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestRuntimeLogObservationOwner(
                expectation:
                    .allMarkers(["required", "event"]),
                observationRegistration: { registered in
                    callback = registered
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    FlowTabUITestRuntimeLogSnapshot(
                        baselineFileEventGeneration: 1,
                        fileEventGeneration: 1,
                        contents: contents
                    )
                }
            )
        owner.start()
        XCTAssertNil(owner.resolvedEvidence)

        callback?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)
        contents = "required event"
        callback?(.notificationReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestRuntimeLogObservationTestPolicy
                    .watchdog
        )

        XCTAssertEqual(
            evidence?.source,
            .notificationReadback
        )
        XCTAssertEqual(evidence?.value.contents, contents)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testRuntimeLogObservationLifecycleUnderPressure() {
        let matchingSnapshot =
            FlowTabUITestRuntimeLogSnapshot(
                baselineFileEventGeneration: 3,
                fileEventGeneration: 4,
                contents: "complete"
            )

        for iteration in
            0..<FlowTabUITestRuntimeLogObservationTestPolicy
                .pressureIterations
        {
            let resolvesInitially =
                iteration.isMultiple(of: 2)
            var snapshot = resolvesInitially
                ? matchingSnapshot
                : FlowTabUITestRuntimeLogSnapshot(
                    baselineFileEventGeneration: 3,
                    fileEventGeneration: 3,
                    contents: "pending"
                )
            var callback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var cancellationCount = 0
            var readbackCount = 0
            let owner =
                FlowTabUITestRuntimeLogObservationOwner(
                    expectation: .allMarkers(["complete"]),
                    observationRegistration: { registered in
                        callback = registered
                        return FlowTabUITestObservationCancellation {
                            cancellationCount += 1
                        }
                    },
                    readback: {
                        readbackCount += 1
                        return snapshot
                    }
                )
            owner.start()

            if !resolvesInitially {
                snapshot = matchingSnapshot
                callback?(.scheduledReadback)
            }
            let evidence = owner.waitForResolution(
                timeout:
                    FlowTabUITestRuntimeLogObservationTestPolicy
                        .watchdog
            )
            let resolvedReadbackCount = readbackCount
            callback?(.notificationReadback)

            XCTAssertEqual(
                evidence?.value,
                matchingSnapshot,
                "iteration=\(iteration)"
            )
            XCTAssertEqual(
                readbackCount,
                resolvedReadbackCount
            )
            XCTAssertEqual(cancellationCount, 1)
            owner.cancel()
        }

        var cancelledCallback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancelledReadbackCount = 0
        let cancelledOwner =
            FlowTabUITestRuntimeLogObservationOwner(
                expectation: .allMarkers(["complete"]),
                observationRegistration: { callback in
                    cancelledCallback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    cancelledReadbackCount += 1
                    return FlowTabUITestRuntimeLogSnapshot(
                        baselineFileEventGeneration: 1,
                        fileEventGeneration: 1,
                        contents: "pending"
                    )
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledCallback?(.notificationReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)

        let watchdogOwner =
            FlowTabUITestRuntimeLogObservationOwner(
                expectation: .allMarkers(["complete"]),
                observationRegistration: nil,
                readback: {
                    FlowTabUITestRuntimeLogSnapshot(
                        baselineFileEventGeneration: 10,
                        fileEventGeneration: 12,
                        contents: "last-observed"
                    )
                }
            )
        watchdogOwner.start()
        XCTAssertNil(
            watchdogOwner.waitForResolution(
                timeout:
                    FlowTabUITestRuntimeLogObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "missingMarkers=[\"complete\"]"
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "last-observed"
            )
        )
        watchdogOwner.cancel()
    }

    func testSwitcherTriggerDeliveryObservationSeparatesReceiptAndCompletion() {
        var contents = ""
        var callbacks: [
            (FlowTabUITestConditionObservationSource) -> Void
        ] = []
        var cancellationCount = 0
        let owner =
            FlowTabUITestSwitcherTriggerDeliveryObservationOwner(
                notificationName:
                    FlowTabUITestRuntimeLogObservationTestPolicy
                        .triggerNotificationName,
                observationRegistration: { callback in
                    callbacks.append(callback)
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    FlowTabUITestRuntimeLogSnapshot(
                        baselineFileEventGeneration: 1,
                        fileEventGeneration: 2,
                        contents: contents
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(callbacks.count, 2)
        for _ in 0..<5 {
            callbacks[1](.scheduledReadback)
            XCTAssertNil(
                owner.completionResolvedEvidence
            )
        }

        contents =
            FlowTabUITestRuntimeLogObservationTestPolicy
                .triggerCompletionMarker
        callbacks[1](.notificationReadback)
        XCTAssertNil(owner.receiptResolvedEvidence)
        XCTAssertEqual(
            owner.completionResolvedEvidence?.source,
            .notificationReadback
        )

        contents =
            FlowTabUITestRuntimeLogObservationTestPolicy
                .triggerReceiptMarker
            + "\n"
            + FlowTabUITestRuntimeLogObservationTestPolicy
                .triggerCompletionMarker
        callbacks[0](.notificationReadback)
        XCTAssertTrue(
            owner.waitForReceipt(
                timeout:
                    FlowTabUITestRuntimeLogObservationTestPolicy
                        .watchdog
            )
        )

        XCTAssertTrue(
            owner.waitForCompletion(
                timeout:
                    FlowTabUITestRuntimeLogObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertEqual(
            owner.receiptResolvedEvidence?.source,
            .notificationReadback
        )
        XCTAssertEqual(
            owner.completionResolvedEvidence?.source,
            .notificationReadback
        )
        XCTAssertEqual(cancellationCount, 2)
    }

    func testSwitcherTriggerDeliveryObservationAcceptsInitialCompletedProjection() {
        var cancellationCount = 0
        let contents =
            FlowTabUITestRuntimeLogObservationTestPolicy
                .triggerReceiptMarker
            + "\n"
            + FlowTabUITestRuntimeLogObservationTestPolicy
                .triggerCompletionMarker
        let owner =
            FlowTabUITestSwitcherTriggerDeliveryObservationOwner(
                notificationName:
                    FlowTabUITestRuntimeLogObservationTestPolicy
                        .triggerNotificationName,
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    FlowTabUITestRuntimeLogSnapshot(
                        baselineFileEventGeneration: 4,
                        fileEventGeneration: 5,
                        contents: contents
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.receiptResolvedEvidence?.source,
            .initialReadback
        )
        XCTAssertEqual(
            owner.completionResolvedEvidence?.source,
            .initialReadback
        )
        XCTAssertEqual(cancellationCount, 2)
    }

    func testSwitcherTriggerDeliveryObservationRejectsStaleCallbacksUnderPressure() {
        for iteration in
            0..<FlowTabUITestRuntimeLogObservationTestPolicy
                .pressureIterations
        {
            var contents = ""
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var cancellationCount = 0
            var readbackCount = 0
            let owner =
                FlowTabUITestSwitcherTriggerDeliveryObservationOwner(
                    notificationName:
                        FlowTabUITestRuntimeLogObservationTestPolicy
                            .triggerNotificationName,
                    observationRegistration: { callback in
                        callbacks.append(callback)
                        return FlowTabUITestObservationCancellation {
                            cancellationCount += 1
                        }
                    },
                    readback: {
                        readbackCount += 1
                        return FlowTabUITestRuntimeLogSnapshot(
                            baselineFileEventGeneration: 7,
                            fileEventGeneration: 8,
                            contents: contents
                        )
                    }
                )
            owner.start()
            let staleCallbacks = callbacks
            owner.cancel()
            owner.start()
            XCTAssertEqual(callbacks.count, 4)

            contents =
                FlowTabUITestRuntimeLogObservationTestPolicy
                    .triggerReceiptMarker
                + "\n"
                + FlowTabUITestRuntimeLogObservationTestPolicy
                    .triggerCompletionMarker
            let readbackCountBeforeStaleCallbacks =
                readbackCount
            staleCallbacks.forEach {
                $0(.notificationReadback)
            }
            XCTAssertEqual(
                readbackCount,
                readbackCountBeforeStaleCallbacks,
                "iteration=\(iteration)"
            )
            XCTAssertNil(owner.receiptResolvedEvidence)
            XCTAssertNil(
                owner.completionResolvedEvidence
            )

            callbacks[2](.notificationReadback)
            callbacks[3](.notificationReadback)
            XCTAssertTrue(
                owner.waitForReceipt(
                    timeout:
                        FlowTabUITestRuntimeLogObservationTestPolicy
                            .watchdog
                )
            )
            XCTAssertTrue(
                owner.waitForCompletion(
                    timeout:
                        FlowTabUITestRuntimeLogObservationTestPolicy
                            .watchdog
                )
            )
            let resolvedReadbackCount = readbackCount
            callbacks[2](.notificationReadback)
            callbacks[3](.notificationReadback)
            XCTAssertEqual(
                readbackCount,
                resolvedReadbackCount,
                "iteration=\(iteration)"
            )
            XCTAssertEqual(
                cancellationCount,
                4,
                "iteration=\(iteration)"
            )
            owner.cancel()
        }
    }

    func testSwitcherTriggerDeliveryObservationWatchdogReportsMissingCompletion() {
        let owner =
            FlowTabUITestSwitcherTriggerDeliveryObservationOwner(
                notificationName:
                    FlowTabUITestRuntimeLogObservationTestPolicy
                        .triggerNotificationName,
                observationRegistration: nil,
                readback: {
                    FlowTabUITestRuntimeLogSnapshot(
                        baselineFileEventGeneration: 10,
                        fileEventGeneration: 12,
                        contents:
                            FlowTabUITestRuntimeLogObservationTestPolicy
                                .triggerReceiptMarker
                            + "\nawaiting switcher trigger presentation "
                            + "generation=4 evidenceGeneration=1 "
                            + "source=triggerReadback "
                            + "snapshot{panelPresented=0 panelKey=0 "
                            + "searchActive=0 searchPending=1}"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertTrue(
            owner.waitForReceipt(
                timeout:
                    FlowTabUITestRuntimeLogObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertFalse(
            owner.waitForCompletion(
                timeout:
                    FlowTabUITestRuntimeLogObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.completionDiagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.completionDiagnosticSummary.contains(
                "presented=1 syntheticModifierHeld=1"
            )
        )
        XCTAssertTrue(
            owner.completionDiagnosticSummary.contains(
                FlowTabUITestRuntimeLogObservationTestPolicy
                    .triggerReceiptMarker
            )
        )
        XCTAssertTrue(
            owner.completionDiagnosticSummary.contains(
                "generation=4 evidenceGeneration=1"
            )
        )
        XCTAssertTrue(
            owner.completionDiagnosticSummary.contains(
                "searchPending=1"
            )
        )
    }
}
