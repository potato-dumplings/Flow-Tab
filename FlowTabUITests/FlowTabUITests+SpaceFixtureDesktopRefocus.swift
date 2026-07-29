import AppKit
import XCTest

private enum SpaceFixtureDesktopRefocusUITestPolicy {
    static let launchCallbackFailureBound: TimeInterval = 10
    static let presentationFailureBound: TimeInterval = 25
    static let processTerminationFailureBound: TimeInterval = 5
    static let processTerminationPollInterval: TimeInterval = 0.05
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
        var terminatedProcessIdentifiers: Set<pid_t> = []
        let notificationCenter =
            NSWorkspace.shared.notificationCenter
        let token = notificationCenter.addObserver(
            forName:
                NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let application =
                    notification.userInfo?[
                        NSWorkspace.applicationUserInfoKey
                    ] as? NSRunningApplication,
                  processIdentifiers.contains(
                    application.processIdentifier
                  )
            else {
                return
            }
            terminatedProcessIdentifiers.insert(
                application.processIdentifier
            )
        }
        defer {
            notificationCenter.removeObserver(token)
        }

        applications.forEach {
            _ = $0.forceTerminate()
        }
        let deadline = Date().addingTimeInterval(
            SpaceFixtureDesktopRefocusUITestPolicy
                .processTerminationFailureBound
        )
        repeat {
            terminatedProcessIdentifiers.formUnion(
                applications
                    .filter(\.isTerminated)
                    .map(\.processIdentifier)
            )
            if terminatedProcessIdentifiers
                == processIdentifiers
            {
                return
            }
            RunLoop.current.run(
                until: Date().addingTimeInterval(
                    SpaceFixtureDesktopRefocusUITestPolicy
                        .processTerminationPollInterval
                )
            )
        } while Date() < deadline

        XCTFail(
            "Fixture processes did not terminate: "
                + processIdentifiers
                    .subtracting(
                        terminatedProcessIdentifiers
                    )
                    .sorted()
                    .map(String.init)
                    .joined(separator: ",")
        )
    }
}
