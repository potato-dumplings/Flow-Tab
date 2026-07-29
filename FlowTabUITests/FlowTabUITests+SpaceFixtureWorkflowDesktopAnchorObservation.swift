import AppKit
import Foundation
import XCTest

enum SpaceFixtureWorkflowDesktopAnchorUITestPolicy {
    static let conditionPollInterval: TimeInterval =
        0.1
    static let watchdog: TimeInterval = 15
}

final class SpaceFixtureWorkflowDesktopAnchorObservationOwner {
    private let expectation:
        SpaceFixtureWorkflowDesktopAnchorExpectation
    private let watchdogSeconds: TimeInterval
    private let readback:
        () -> SpaceFixtureWorkflowDesktopAnchorSnapshot
    private let workspaceNotificationCenter:
        NotificationCenter
    private let stateOwner =
        SpaceFixtureWorkflowDesktopAnchorOwner()

    private var workspaceObservationTokens:
        [NSObjectProtocol] = []
    private var conditionPollTimer: Timer?
    private var resolvedExpectation: XCTestExpectation?
    private var currentGeneration: Int?
    private var resolvedEvidence:
        SpaceFixtureWorkflowDesktopAnchorEvidence?
    private var watchdogFailure:
        SpaceFixtureWorkflowDesktopAnchorWatchdogFailure?

    init(
        expectation:
            SpaceFixtureWorkflowDesktopAnchorExpectation,
        watchdogSeconds: TimeInterval,
        workspaceNotificationCenter:
            NotificationCenter =
                NSWorkspace.shared.notificationCenter,
        readback:
            @escaping () ->
                SpaceFixtureWorkflowDesktopAnchorSnapshot
    ) {
        self.expectation = expectation
        self.watchdogSeconds = watchdogSeconds
        self.workspaceNotificationCenter =
            workspaceNotificationCenter
        self.readback = readback
    }

    func start() {
        cancel()
        resolvedEvidence = nil
        watchdogFailure = nil
        let resolvedExpectation = XCTestExpectation(
            description:
                "exact fixture workflow desktop anchor"
        )
        resolvedExpectation.assertForOverFulfill = true
        self.resolvedExpectation = resolvedExpectation
        let generation = stateOwner.start(
            expectation: expectation,
            watchdogSeconds: watchdogSeconds
        ) { [weak self] evidence in
            self?.finishResolved(evidence)
        } onWatchdog: { [weak self] failure in
            self?.finishWatchdog(failure)
        }
        currentGeneration = generation
        installWorkspaceObservers()
        observe(source: .initialReadback)
        if stateOwner.isObserving {
            startConditionPolling()
        }
    }

    func triggerDidReturn() {
        observe(source: .triggerReturnReadback)
    }

    func waitForResolution()
        -> SpaceFixtureWorkflowDesktopAnchorEvidence?
    {
        if let resolvedEvidence {
            return resolvedEvidence
        }
        guard let resolvedExpectation,
              let currentGeneration
        else {
            return nil
        }
        let waitResult = XCTWaiter.wait(
            for: [resolvedExpectation],
            timeout: watchdogSeconds
        )
        if waitResult == .completed {
            return resolvedEvidence
        }
        _ = stateOwner.expireWatchdog(
            finalSnapshot: readback(),
            observationGeneration:
                currentGeneration
        )
        conditionPollTimer?.invalidate()
        conditionPollTimer = nil
        return resolvedEvidence
    }

    var diagnosticSummary: String {
        if let watchdogFailure {
            return watchdogFailure.logFields
        }
        guard let evidence = stateOwner.lastEvidence else {
            return "unobserved"
        }
        let unmet = evidence.snapshot.unmetConditions(
            expectation: expectation
        ).joined(separator: ",")
        return "unmet=[\(unmet)] "
            + "lastSource=\(evidence.source.rawValue) "
            + "last{\(evidence.snapshot.logFields)}"
    }

    func cancel() {
        for token in workspaceObservationTokens {
            workspaceNotificationCenter
                .removeObserver(token)
        }
        workspaceObservationTokens.removeAll()
        conditionPollTimer?.invalidate()
        conditionPollTimer = nil
        stateOwner.cancel()
        resolvedExpectation = nil
        currentGeneration = nil
    }

    deinit {
        for token in workspaceObservationTokens {
            workspaceNotificationCenter
                .removeObserver(token)
        }
        conditionPollTimer?.invalidate()
    }

    private func installWorkspaceObservers() {
        workspaceObservationTokens = [
            workspaceNotificationCenter.addObserver(
                forName:
                    NSWorkspace
                        .didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.observe(
                    source: .applicationDidActivate
                )
            },
            workspaceNotificationCenter.addObserver(
                forName:
                    NSWorkspace
                        .activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.observe(
                    source: .activeSpaceDidChange
                )
            }
        ]
    }

    private func startConditionPolling() {
        let timer = Timer(
            timeInterval:
                SpaceFixtureWorkflowDesktopAnchorUITestPolicy
                    .conditionPollInterval,
            repeats: true
        ) { [weak self] _ in
            self?.observe(
                source: .conditionPollReadback
            )
        }
        conditionPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func observe(
        source:
            SpaceFixtureWorkflowDesktopAnchorEvidenceSource
    ) {
        guard let currentGeneration else { return }
        _ = stateOwner.observe(
            snapshot: readback(),
            source: source,
            observationGeneration:
                currentGeneration
        )
    }

    private func finishResolved(
        _ evidence:
            SpaceFixtureWorkflowDesktopAnchorEvidence
    ) {
        conditionPollTimer?.invalidate()
        conditionPollTimer = nil
        resolvedEvidence = evidence
        resolvedExpectation?.fulfill()
    }

    private func finishWatchdog(
        _ failure:
            SpaceFixtureWorkflowDesktopAnchorWatchdogFailure
    ) {
        conditionPollTimer?.invalidate()
        conditionPollTimer = nil
        watchdogFailure = failure
    }
}

extension FlowTabUITests {
    @discardableResult
    func activateSpaceFixtureWorkflowDesktopAnchor(
        workflowApp: SpaceFixtureResolvedWorkflow.App,
        application: XCUIApplication,
        readinessEvidence:
            SpaceFixtureWorkflowReadinessEvidence,
        watchdog:
            TimeInterval =
                SpaceFixtureWorkflowDesktopAnchorUITestPolicy
                    .watchdog
    ) -> SpaceFixtureWorkflowDesktopAnchorEvidence? {
        let expectation =
            SpaceFixtureWorkflowDesktopAnchorExpectation(
                bundleIdentifier:
                    workflowApp.identity.bundleIdentifier,
                processIdentifier:
                    readinessEvidence.identity
                        .processIdentifier,
                windows:
                    workflowApp.expectedWindowTitles
                        .enumerated()
                        .map { index, title in
                            let planIndex = index + 1
                            return SpaceFixtureWorkflowDesktopAnchorWindowExpectation(
                                planIndex: planIndex,
                                title: title,
                                accessibilityIdentifier:
                                    "flowtab.spacefixture.window.title."
                                    + String(planIndex)
                            )
                        }
            )
        XCTAssertEqual(
            readinessEvidence.identity.bundleIdentifier,
            expectation.bundleIdentifier
        )
        let observationOwner =
            SpaceFixtureWorkflowDesktopAnchorObservationOwner(
                expectation: expectation,
                watchdogSeconds: watchdog
            ) {
                self.workflowDesktopAnchorSnapshot(
                    expectation: expectation,
                    application: application
                )
            }
        observationOwner.start()
        defer { observationOwner.cancel() }

        application.activate()
        observationOwner.triggerDidReturn()
        guard let evidence =
                observationOwner.waitForResolution()
        else {
            XCTFail(
                "Fixture workflow desktop-anchor watchdog expired: "
                    + observationOwner.diagnosticSummary
            )
            return nil
        }
        XCTAssertTrue(
            evidence.snapshot.isResolved(
                expectation: expectation
            )
        )
        XCTAssertTrue(
            SpaceFixtureWorkflowDesktopAnchorSnapshot
                .windowFramesMatch(
                    evidence.snapshot
                        .identifiedXCUIWindowFrame,
                    evidence.snapshot.topmostCGWindowFrame
                )
        )
        XCTAssertFalse(
            evidence.snapshot
                .topmostCGWindowIsFullscreenSpaceSized
        )
        return evidence
    }

    private func workflowDesktopAnchorSnapshot(
        expectation:
            SpaceFixtureWorkflowDesktopAnchorExpectation,
        application: XCUIApplication
    ) -> SpaceFixtureWorkflowDesktopAnchorSnapshot {
        let runningApplication = NSRunningApplication(
            processIdentifier:
                expectation.processIdentifier
        )
        let topmostCGWindow =
            topmostOnScreenCGWindow(
                forPID: expectation.processIdentifier
            )
        let xcuiWindows =
            application.windows.allElementsBoundByIndex
        let identifiedWindow = xcuiWindows.lazy
            .filter {
                SpaceFixtureWorkflowDesktopAnchorSnapshot
                    .windowFramesMatch(
                        $0.frame,
                        topmostCGWindow?.frame
                    )
            }
            .compactMap { window in
                for windowExpectation in expectation.windows {
                    let titleElement =
                        window.descendants(matching: .any)
                        .matching(
                            identifier:
                                windowExpectation
                                    .accessibilityIdentifier
                        )
                        .firstMatch
                    if titleElement.exists {
                        return (
                            expectation:
                                windowExpectation,
                            observedTitle:
                                titleElement.label,
                            frame: window.frame
                        )
                    }
                }
                return nil
            }
            .first
        let frontmostApplication =
            NSWorkspace.shared.frontmostApplication

        return SpaceFixtureWorkflowDesktopAnchorSnapshot(
            runningBundleIdentifier:
                runningApplication?.bundleIdentifier,
            runningProcessIdentifier:
                runningApplication?.processIdentifier,
            applicationIsActive:
                runningApplication?.isActive == true,
            applicationIsTerminated:
                runningApplication?.isTerminated ?? true,
            xcuiRunningForeground:
                application.state == .runningForeground,
            frontmostBundleIdentifier:
                frontmostApplication?.bundleIdentifier,
            frontmostProcessIdentifier:
                frontmostApplication?.processIdentifier,
            identifiedXCUIWindowFrame:
                identifiedWindow?.frame,
            identifiedWindowPlanIndex:
                identifiedWindow?
                    .expectation.planIndex,
            identifiedWindowTitle:
                identifiedWindow?.observedTitle,
            identifiedAccessibilityIdentifier:
                identifiedWindow?.expectation
                    .accessibilityIdentifier,
            observedXCUIWindowFrames:
                xcuiWindows.map(\.frame),
            topmostCGWindowNumber:
                topmostCGWindow?.number,
            topmostCGWindowTitle:
                topmostCGWindow?.title,
            topmostCGWindowFrame:
                topmostCGWindow?.frame,
            topmostCGWindowIsFullscreenSpaceSized:
                topmostCGWindow?
                    .isFullscreenSpaceSized
                ?? false
        )
    }
}
