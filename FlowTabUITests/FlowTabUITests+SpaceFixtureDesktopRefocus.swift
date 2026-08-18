import AppKit
import XCTest

private enum SpaceFixtureDesktopRefocusUITestPolicy {
    static let launchCallbackFailureBound: TimeInterval = 10
    static let presentationFailureBound: TimeInterval = 25
    static let processTerminationFailureBound: TimeInterval = 5
    static let processTerminationPressureIterations = 100
    static let processTerminationWatchdogTestBound:
        TimeInterval = 0.01
}

struct FlowTabUITestProcessTerminationSnapshot: Equatable {
    let targetProcessIdentifiers: Set<pid_t>
    let terminatedProcessIdentifiers: Set<pid_t>

    var missingProcessIdentifiers: Set<pid_t> {
        targetProcessIdentifiers.subtracting(
            terminatedProcessIdentifiers
        )
    }

    var diagnosticSummary: String {
        "targetPIDs=\(sortedDescription(targetProcessIdentifiers)) "
            + "terminatedPIDs=\(sortedDescription(terminatedProcessIdentifiers)) "
            + "missingPIDs=\(sortedDescription(missingProcessIdentifiers))"
    }

    private func sortedDescription(
        _ processIdentifiers: Set<pid_t>
    ) -> String {
        processIdentifiers
            .sorted()
            .map(String.init)
            .joined(separator: ",")
    }
}

final class FlowTabUITestProcessTerminationObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestProcessTerminationSnapshot
        >

    init(
        targetProcessIdentifiers: Set<pid_t>,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        terminatedProcessIdentifiers:
            @escaping () -> Set<pid_t>
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: {
                FlowTabUITestProcessTerminationSnapshot(
                    targetProcessIdentifiers:
                        targetProcessIdentifiers,
                    terminatedProcessIdentifiers:
                        terminatedProcessIdentifiers()
                )
            },
            isSatisfied: {
                $0.terminatedProcessIdentifiers
                    == targetProcessIdentifiers
            },
            describe: \.diagnosticSummary
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestProcessTerminationSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestProcessTerminationSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    func testSpaceFixtureRefocusesExactDesktopAnchorAfterFullscreenCompletion() throws {
        let identity = spaceFixtureAppIdentity
        terminateAllSpaceFixtureProcesses(
            bundleIdentifier: identity.bundleIdentifier
        )
        let desktopAnchorTitle = "Desktop Refocus 1"
        let runningApplication =
            try openSpaceFixtureForDesktopRefocus(
            identity: identity,
            arguments: [
                "--window-count", "2",
                "--window-title-prefix", "Desktop Refocus",
                "--fullscreen-window-index", "2",
                "--enter-fullscreen-delay-ms", "0",
                "--staggered-layout",
                "--preserve-desktop-after-fullscreen"
            ]
        )
        defer {
            runningApplication.terminate()
        }

        let observation =
            waitForExactFrontmostSpaceFixtureWindow(
                title: desktopAnchorTitle,
                titleAccessibilityIdentifier:
                    "flowtab.spacefixture.window.title.1",
                processIdentifier:
                    runningApplication.processIdentifier,
                bundleIdentifier: identity.bundleIdentifier,
                timeout:
                    SpaceFixtureDesktopRefocusUITestPolicy
                        .presentationFailureBound
            )

        XCTAssertNotNil(observation)
        XCTAssertFalse(
            observation?.isFullscreenSpaceSized ?? true
        )
    }

    private func openSpaceFixtureForDesktopRefocus(
        identity: SpaceFixtureAppIdentity,
        arguments: [String]
    ) throws -> NSRunningApplication {
        let appURL = try XCTUnwrap(
            currentSpaceFixtureBuildProductURL(
                identity: identity
            )
        )
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        let launchCompleted = expectation(
            description: "Space fixture launch callback"
        )
        var launchedApplication: NSRunningApplication?
        var launchError: Error?

        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration
        ) { runningApplication, error in
            launchedApplication = runningApplication
            launchError = error
            launchCompleted.fulfill()
        }
        wait(
            for: [launchCompleted],
            timeout:
                SpaceFixtureDesktopRefocusUITestPolicy
                    .launchCallbackFailureBound
        )

        if let launchError {
            throw launchError
        }
        return try XCTUnwrap(launchedApplication)
    }

    private func currentSpaceFixtureBuildProductURL(
        identity: SpaceFixtureAppIdentity
    ) -> URL? {
        let runnerProductDirectory =
            Bundle.main.bundleURL
                .deletingLastPathComponent()
        let testBundleProductDirectory =
            Bundle(for: FlowTabUITests.self).bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        let candidates = [
            runnerProductDirectory.appendingPathComponent(
                "FlowTabSpaceFixture.app",
                isDirectory: true
            ),
            testBundleProductDirectory.appendingPathComponent(
                "FlowTabSpaceFixture.app",
                isDirectory: true
            ),
            identity.appURL
        ].compactMap { $0 }
        return candidates.first {
            Bundle(url: $0)?.bundleIdentifier
                == identity.bundleIdentifier
        }
    }

    private func terminateAllSpaceFixtureProcesses(
        bundleIdentifier: String
    ) {
        let applications =
            NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            )
            .filter { !$0.isTerminated }
        guard !applications.isEmpty else { return }

        let processIdentifiers = Set(
            applications.map(\.processIdentifier)
        )
        let notificationCenter =
            NSWorkspace.shared.notificationCenter
        let owner =
            FlowTabUITestProcessTerminationObservationOwner(
                targetProcessIdentifiers:
                    processIdentifiers,
                observationRegistration: { callback in
                    let token = notificationCenter.addObserver(
                        forName:
                            NSWorkspace
                                .didTerminateApplicationNotification,
                        object: nil,
                        queue: .main
                    ) { notification in
                        guard let application =
                                notification.userInfo?[
                                    NSWorkspace
                                        .applicationUserInfoKey
                                ] as? NSRunningApplication,
                              processIdentifiers.contains(
                                application.processIdentifier
                              )
                        else {
                            return
                        }
                        callback(.notificationReadback)
                    }
                    return FlowTabUITestObservationCancellation {
                        notificationCenter.removeObserver(token)
                    }
                },
                terminatedProcessIdentifiers: {
                    Set(
                        applications
                            .filter(\.isTerminated)
                            .map(\.processIdentifier)
                    )
                }
            )
        owner.start()
        defer {
            owner.cancel()
        }

        applications.forEach {
            _ = $0.forceTerminate()
        }

        guard
            owner.waitForResolution(
                timeout:
                    SpaceFixtureDesktopRefocusUITestPolicy
                        .processTerminationFailureBound
            ) != nil
        else {
            XCTFail(
                "Fixture process termination watchdog expired. "
                    + owner.diagnosticSummary
            )
            return
        }
    }
}

extension FlowTabUITests {
    func testProcessTerminationObserverAcceptsMatchingInitialReadback() {
        var cancellationCount = 0
        let owner =
            FlowTabUITestProcessTerminationObservationOwner(
                targetProcessIdentifiers: [101, 102],
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                terminatedProcessIdentifiers: {
                    [101, 102]
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testProcessTerminationObserverRequiresEveryExactPID() {
        var terminatedProcessIdentifiers: Set<pid_t> = []
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestProcessTerminationObservationOwner(
                targetProcessIdentifiers: [201, 202],
                observationRegistration: {
                    callback = $0
                    return FlowTabUITestObservationCancellation {}
                },
                terminatedProcessIdentifiers: {
                    terminatedProcessIdentifiers
                }
            )
        owner.start()
        defer { owner.cancel() }

        terminatedProcessIdentifiers.insert(202)
        callback?(.notificationReadback)
        callback?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)

        terminatedProcessIdentifiers.insert(201)
        callback?(.notificationReadback)
        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .notificationReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value
                .terminatedProcessIdentifiers,
            [201, 202]
        )
    }

    func testProcessTerminationObserverRejectsStaleNotificationsUnderPressure() {
        for _ in 0..<SpaceFixtureDesktopRefocusUITestPolicy
            .processTerminationPressureIterations
        {
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var terminatedProcessIdentifiers: Set<pid_t> = []
            let owner =
                FlowTabUITestProcessTerminationObservationOwner(
                    targetProcessIdentifiers: [301],
                    observationRegistration: {
                        callbacks.append($0)
                        return FlowTabUITestObservationCancellation {}
                    },
                    terminatedProcessIdentifiers: {
                        terminatedProcessIdentifiers
                    }
                )
            owner.start()
            let staleCallback = callbacks[0]
            owner.cancel()
            owner.start()
            terminatedProcessIdentifiers = [301]

            staleCallback(.notificationReadback)
            XCTAssertNil(owner.resolvedEvidence)
            callbacks[1](.notificationReadback)
            callbacks[1](.notificationReadback)
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
    }

    func testProcessTerminationObserverWatchdogReportsMissingPIDs() {
        let owner =
            FlowTabUITestProcessTerminationObservationOwner(
                targetProcessIdentifiers: [401, 402],
                observationRegistration: nil,
                terminatedProcessIdentifiers: {
                    [401]
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    SpaceFixtureDesktopRefocusUITestPolicy
                        .processTerminationWatchdogTestBound
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "missingPIDs=402"
            )
        )
    }
}
