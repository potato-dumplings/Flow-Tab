import Foundation
import XCTest

private enum FlowTabUITestHomeInitialProjectionPolicy {
    static let applicationWatchdog: TimeInterval = 8
    static let readbackCadence: TimeInterval = 0.1
}

private struct
    FlowTabUITestHomeInitialProjectionApplicationRoute
{
    static let notificationArgument =
        "--flowtab-ui-home-initial-projection-application-notification-name"
    static let readbackPathArgument =
        "--flowtab-ui-home-initial-projection-application-readback-path"

    let notificationName: Notification.Name
    let readbackURL: URL

    init(
        temporaryDirectory: URL =
            FileManager.default.temporaryDirectory
    ) {
        let identifier = UUID().uuidString
        notificationName = Notification.Name(
            "io.github.potato-dumplings.flowtab.ui-test."
                + "home-initial-projection.\(identifier)"
        )
        readbackURL = temporaryDirectory.appendingPathComponent(
            "flowtab-home-initial-projection-\(identifier).json",
            isDirectory: false
        )
    }

    var launchArguments: [String] {
        [
            Self.notificationArgument,
            notificationName.rawValue,
            Self.readbackPathArgument,
            readbackURL.path
        ]
    }

    func removeReadback() {
        try? FileManager.default.removeItem(
            at: readbackURL
        )
    }
}

private struct
    FlowTabUITestHomeInitialProjectionApplicationEvidence:
    Decodable
{
    struct AppSummary: Decodable {
        let appID: String
        let windowCount: Int
    }

    let observationGeneration: UInt64
    let readbackCount: Int
    let source: String
    let transition: String
    let requestReason: String
    let appCount: Int
    let appSummaries: [AppSummary]
    let isCompleteForScope: Bool
    let appLifecycleGeneration: UInt64
    let cgGeneration: UInt64
    let spaceGeneration: UInt64
    let axDirtyGeneration: UInt64
    let projectionGeneration: UInt64

    var satisfiesApplicationContract: Bool {
        guard observationGeneration > 0,
              readbackCount > 0,
              source == "appSwitcherProjectionNotification",
              transition == "sourceGenerationAdvanced",
              !requestReason.isEmpty,
              appCount == appSummaries.count,
              projectionGeneration > 0,
              !isCompleteForScope,
              let mailIndex = appSummaries.firstIndex(
                where: {
                    $0.appID == "com.flowtab.mock.mail"
                }
              ),
              let browserIndex = appSummaries.firstIndex(
                where: {
                    $0.appID == "com.flowtab.mock.browser"
                }
              )
        else {
            return false
        }
        return mailIndex < browserIndex
            && appSummaries[mailIndex].windowCount == 0
            && appSummaries[browserIndex].windowCount == 0
    }

    var diagnosticSummary: String {
        "observationGeneration=\(observationGeneration) "
            + "readbacks=\(readbackCount) "
            + "source=\(source) "
            + "transition=\(transition) "
            + "requestReason=\(requestReason) "
            + "apps=\(appCount) "
            + "summaries=\(appSummaries.map { "\($0.appID):\($0.windowCount)" }.joined(separator: ",")) "
            + "complete=\(isCompleteForScope ? 1 : 0) "
            + "sourceGeneration{"
            + "appLifecycle=\(appLifecycleGeneration),"
            + "cg=\(cgGeneration),"
            + "space=\(spaceGeneration),"
            + "axDirty=\(axDirtyGeneration),"
            + "projection=\(projectionGeneration)}"
    }
}

private struct
    FlowTabUITestHomeInitialProjectionApplicationReadback
{
    let readbackPath: String
    let fileExists: Bool
    let evidence:
        FlowTabUITestHomeInitialProjectionApplicationEvidence?
    let errorDescription: String?

    static func read(
        from readbackURL: URL
    ) -> Self {
        let path = readbackURL.path
        guard FileManager.default.fileExists(
            atPath: path
        ) else {
            return Self(
                readbackPath: path,
                fileExists: false,
                evidence: nil,
                errorDescription: nil
            )
        }
        do {
            let data = try Data(contentsOf: readbackURL)
            let evidence = try JSONDecoder().decode(
                FlowTabUITestHomeInitialProjectionApplicationEvidence
                    .self,
                from: data
            )
            return Self(
                readbackPath: path,
                fileExists: true,
                evidence: evidence,
                errorDescription: nil
            )
        } catch {
            return Self(
                readbackPath: path,
                fileExists: true,
                evidence: nil,
                errorDescription:
                    String(describing: error)
            )
        }
    }

    var diagnosticSummary: String {
        if let evidence {
            return "path=\(readbackPath) "
                + evidence.diagnosticSummary
        }
        return "path=\(readbackPath) "
            + "fileExists=\(fileExists) "
            + "error=\(errorDescription ?? "nil")"
    }
}

private final class
    FlowTabUITestHomeInitialProjectionApplicationObservationOwner
{
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestHomeInitialProjectionApplicationReadback
        >

    init(
        route:
            FlowTabUITestHomeInitialProjectionApplicationRoute,
        center: DistributedNotificationCenter = .default()
    ) {
        let scheduledRegistration =
            FlowTabUITestConditionReadbackScheduler
                .mainRunLoopRegistration(
                    cadence:
                        FlowTabUITestHomeInitialProjectionPolicy
                            .readbackCadence
                )
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: { readback in
                let token = center.addObserver(
                    forName: route.notificationName,
                    object: nil,
                    queue: .main
                ) { _ in
                    readback(.notificationReadback)
                }
                let scheduledCancellation =
                    scheduledRegistration(readback)
                return FlowTabUITestObservationCancellation {
                    center.removeObserver(token)
                    scheduledCancellation?.cancel()
                }
            },
            readback: {
                FlowTabUITestHomeInitialProjectionApplicationReadback
                    .read(from: route.readbackURL)
            },
            isSatisfied: {
                $0.evidence?
                    .satisfiesApplicationContract == true
            },
            describe: \.diagnosticSummary
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForApplication(
        timeout: TimeInterval
    ) -> FlowTabUITestHomeInitialProjectionApplicationEvidence? {
        conditionOwner.waitForResolution(
            timeout: timeout
        )?.value.evidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    func testHomeInitialAppLayerUsesRuntimeOrderAndZeroCountsWithoutAccessibilityPermission() throws {
        let route =
            FlowTabUITestHomeInitialProjectionApplicationRoute()
        route.removeReadback()
        let applicationOwner =
            FlowTabUITestHomeInitialProjectionApplicationObservationOwner(
                route: route
            )
        applicationOwner.start()
        addTeardownBlock {
            applicationOwner.cancel()
            route.removeReadback()
        }

        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "-showPermissionReminder",
                "NO",
                "--flowtab-ui-ax-trusted",
                "NO",
                "--flowtab-ui-screen-trusted",
                "YES"
            ] + route.launchArguments
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout: 8
            )
        )
        XCTAssertTrue(
            tapFirstHittable(
                in: app.buttons.matching(
                    identifier: Identifier.homeTabButton
                ),
                timeout: 5
            )
        )
        XCTAssertTrue(
            element(
                in: app,
                identifier: Identifier.homeTabContent
            )
            .waitForExistence(timeout: 5)
        )

        let mailRow = element(
            in: app,
            identifier: Identifier.homeAppMockMail
        )
        let browserRow = element(
            in: app,
            identifier: Identifier.homeAppMockBrowser
        )
        XCTAssertTrue(mailRow.waitForExistence(timeout: 6))
        XCTAssertTrue(browserRow.waitForExistence(timeout: 6))
        XCTAssertLessThan(
            mailRow.frame.minY,
            browserRow.frame.minY,
            "Home initial app rows should use the runtime snapshot order before any precise count refresh."
        )
        assertValue(of: mailRow, equals: "0w", timeout: 2)
        assertValue(
            of: browserRow,
            equals: "0w",
            timeout: 2
        )
        let initialMailY = mailRow.frame.minY
        let initialBrowserY = browserRow.frame.minY

        guard
            let application =
                applicationOwner.waitForApplication(
                    timeout:
                        FlowTabUITestHomeInitialProjectionPolicy
                            .applicationWatchdog
                )
        else {
            XCTFail(
                "Home initial projection application watchdog "
                    + "expired. "
                    + applicationOwner.diagnosticSummary
            )
            return
        }
        XCTAssertEqual(
            application.source,
            "appSwitcherProjectionNotification"
        )
        XCTAssertEqual(
            application.transition,
            "sourceGenerationAdvanced"
        )
        XCTAssertFalse(application.isCompleteForScope)
        XCTAssertTrue(
            application.satisfiesApplicationContract
        )

        let appliedMailRow = element(
            in: app,
            identifier: Identifier.homeAppMockMail
        )
        let appliedBrowserRow = element(
            in: app,
            identifier: Identifier.homeAppMockBrowser
        )
        assertValue(
            of: appliedMailRow,
            equals: "0w",
            timeout: 2
        )
        assertValue(
            of: appliedBrowserRow,
            equals: "0w",
            timeout: 2
        )
        XCTAssertEqual(
            appliedMailRow.frame.minY,
            initialMailY,
            accuracy: 1
        )
        XCTAssertEqual(
            appliedBrowserRow.frame.minY,
            initialBrowserY,
            accuracy: 1
        )
        XCTAssertLessThan(
            appliedMailRow.frame.minY,
            appliedBrowserRow.frame.minY
        )
    }
}
