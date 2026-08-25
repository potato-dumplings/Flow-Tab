import XCTest
@testable import FlowTab

@MainActor
private final class RecordingStandardUpdaterController:
    FlowTabStandardUpdaterControlling
{
    private(set) var startCount = 0
    private(set) var foregroundCheckCount = 0

    func startUpdater() {
        startCount += 1
    }

    func checkForUpdates(_ sender: Any?) {
        foregroundCheckCount += 1
    }
}

extension FlowTabTests {
    func testUpdateChannelPolicyIncludesPrereleasesForPrereleaseBuilds() {
        for version in [
            "0.1.0-alpha.05",
            "0.1.0-BETA.1",
            "1.0.0-rc.2"
        ] {
            XCTAssertEqual(
                FlowTabUpdateChannelPolicy.allowedChannels(
                    for: version
                ),
                [FlowTabUpdateChannelPolicy.prereleaseChannel]
            )
        }
        XCTAssertEqual(
            FlowTabUpdateChannelPolicy.allowedChannels(for: "1.0.0"),
            []
        )
    }

    func testReleaseBuildPolicyRequiresStrictlyIncreasingPositiveIntegers() {
        XCTAssertTrue(FlowTabReleaseVersionPolicy.isValidBuild("5"))
        XCTAssertFalse(FlowTabReleaseVersionPolicy.isValidBuild("0"))
        XCTAssertFalse(FlowTabReleaseVersionPolicy.isValidBuild("-1"))
        XCTAssertFalse(FlowTabReleaseVersionPolicy.isValidBuild("5.1"))
        XCTAssertTrue(
            FlowTabReleaseVersionPolicy.isCandidateBuild(
                "6",
                newerThan: "5"
            )
        )
        XCTAssertFalse(
            FlowTabReleaseVersionPolicy.isCandidateBuild(
                "5",
                newerThan: "5"
            )
        )
        XCTAssertFalse(
            FlowTabReleaseVersionPolicy.isCandidateBuild(
                "4",
                newerThan: "5"
            )
        )
    }

    func testUpdatePresentationReducerPreservesAndClearsKnownUpdate() {
        let update = FlowTabAvailableUpdate(
            displayVersion: "0.1.0-alpha.06",
            buildVersion: "6"
        )
        let available = FlowTabUpdateAvailability.available(update)

        XCTAssertEqual(
            FlowTabUpdatePresentationReducer.reduce(
                .idle,
                event: .updateFound(update)
            ),
            available
        )
        for event in [
            FlowTabUpdatePresentationEvent.userDismissed,
            .transientFailure
        ] {
            XCTAssertEqual(
                FlowTabUpdatePresentationReducer.reduce(
                    available,
                    event: event
                ),
                available
            )
        }
        for event in [
            FlowTabUpdatePresentationEvent.userSkipped,
            .installConfirmed,
            .currentVersionIsLatest
        ] {
            XCTAssertEqual(
                FlowTabUpdatePresentationReducer.reduce(
                    available,
                    event: event
                ),
                .idle
            )
        }
    }

    func testUpdateStringsIncludeTheTargetVersionInBothLanguages() {
        let version = "0.1.0-alpha.06"
        XCTAssertEqual(
            AppStrings.text(
                .updateDownloadVersion,
                replacements: ["version": version],
                language: .simplifiedChinese
            ),
            "下载 \(version) 更新"
        )
        XCTAssertEqual(
            AppStrings.text(
                .updateDownloadHelp,
                replacements: ["version": version],
                language: .english
            ),
            "Open update \(version) details and download"
        )
        XCTAssertEqual(
            AppStrings.text(
                .menuCheckForUpdates,
                language: .simplifiedChinese
            ),
            "检查更新…"
        )
        XCTAssertEqual(
            AppStrings.text(.menuCheckForUpdates, language: .english),
            "Check for Updates…"
        )
    }

    func testUpdateButtonTitleIsLocalizedInBothLanguages() {
        XCTAssertEqual(
            AppStrings.text(
                .updateButtonTitle,
                language: .simplifiedChinese
            ),
            "更新"
        )
        XCTAssertEqual(
            AppStrings.text(.updateButtonTitle, language: .english),
            "Update"
        )
    }

    @MainActor
    func testUpdateCoordinatorStartsOnceAndPresentsOneForegroundCheck() {
        let controller = RecordingStandardUpdaterController()
        let store = FlowTabUpdatePresentationStore()
        let coordinator = SparkleUpdateCoordinator(
            presentationStore: store,
            displayVersionProvider: { "0.1.0-alpha.05" },
            controllerFactory: { _, _ in controller }
        )

        coordinator.startIfNeeded()
        coordinator.startIfNeeded()
        store.showAvailableUpdate()

        XCTAssertEqual(controller.startCount, 1)
        XCTAssertEqual(controller.foregroundCheckCount, 1)
    }

    @MainActor
    func testAllPresentationEntryPointsResolveLifecycleSingletons() {
        XCTAssertTrue(
            FlowTabUpdatePresentationStore.shared
                === FlowTabUpdatePresentationStore.shared
        )
        XCTAssertTrue(
            SparkleUpdateCoordinator.shared
                === SparkleUpdateCoordinator.shared
        )
    }
}
