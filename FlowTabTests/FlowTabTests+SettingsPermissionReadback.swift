import AppKit
import SwiftUI
import XCTest
@testable import FlowTab

private enum SettingsPermissionReadbackPolicy {
    static let watchdogTimeout: TimeInterval = 1
}

private struct SettingsPermissionReadbackEvidence: Equatable {
    let generation: UInt64
    let isGranted: Bool

    var diagnosticSummary: String {
        "generation=\(generation) granted=\(isGranted)"
    }
}

@MainActor
private final class SettingsPermissionReadbackObservation {
    private var cancellation: (@MainActor () -> Void)?

    init(cancellation: @escaping @MainActor () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        guard let cancellation else { return }
        self.cancellation = nil
        cancellation()
    }
}

@MainActor
private final class SettingsPermissionReadbackRecorder {
    typealias Handler = @MainActor (SettingsPermissionReadbackEvidence) -> Void

    private var nextGeneration: UInt64 = 1
    private var observers: [UUID: (UInt64, Handler)] = [:]
    private(set) var latestEvidence: SettingsPermissionReadbackEvidence?

    @discardableResult
    func record(_ isGranted: Bool) -> Bool {
        let evidence = SettingsPermissionReadbackEvidence(
            generation: nextGeneration,
            isGranted: isGranted
        )
        nextGeneration &+= 1
        latestEvidence = evidence
        for (baselineGeneration, handler) in Array(observers.values)
        where evidence.generation > baselineGeneration {
            handler(evidence)
        }
        return isGranted
    }

    func observe(
        after baselineGeneration: UInt64,
        handler: @escaping Handler
    ) -> SettingsPermissionReadbackObservation {
        let id = UUID()
        observers[id] = (baselineGeneration, handler)
        return SettingsPermissionReadbackObservation { [weak self] in
            self?.observers[id] = nil
        }
    }
}

@MainActor
private final class SettingsPermissionScenarioState {
    var isGranted = false
    var requestCount = 0
}

@MainActor
private final class SettingsPermissionTitleRecorder {
    private let expectedTitle: String
    private var matchingHandler: (() -> Void)?
    private(set) var latestTitle: String

    init(
        initialTitle: String,
        expectedTitle: String,
        matchingHandler: @escaping () -> Void
    ) {
        latestTitle = initialTitle
        self.expectedTitle = expectedTitle
        self.matchingHandler = matchingHandler
    }

    func record(_ title: String) {
        latestTitle = title
        guard title == expectedTitle, let matchingHandler else { return }
        self.matchingHandler = nil
        matchingHandler()
    }

    func cancel() {
        matchingHandler = nil
    }
}

extension FlowTabTests {
    @MainActor
    func testSettingsPermissionRequestAppliesIndependentPostRequestReadback() async throws {
        let previousAXTrusted =
            AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest =
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let previousScreenTrusted =
            ScreenCapturePermissionChecker.hasPermissionOverrideForTesting
        let previousLanguageRaw = UserDefaults.standard.string(
            forKey: AppPreferenceKeys.appLanguage
        )
        let previousContext = FlowPresentationState.shared.context
        let recorder = SettingsPermissionReadbackRecorder()
        let scenario = SettingsPermissionScenarioState()
        defer {
            AccessibilityPermissionChecker.isTrustedOverrideForTesting =
                previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting =
                previousAXRequest
            ScreenCapturePermissionChecker.hasPermissionOverrideForTesting =
                previousScreenTrusted
            FlowPresentationState.shared.setAppLanguage(
                rawValue: previousContext.appLanguage.rawValue
            )
            restoreSettingsPermissionDefault(
                previousLanguageRaw,
                forKey: AppPreferenceKeys.appLanguage
            )
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = {
            recorder.record(scenario.isGranted)
        }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = {
            scenario.requestCount += 1
            scenario.isGranted = true
            return false
        }
        ScreenCapturePermissionChecker.hasPermissionOverrideForTesting = {
            true
        }
        FlowPresentationState.shared.setAppLanguage(
            rawValue: AppLanguage.simplifiedChinese.rawValue
        )

        let hostedView = NSHostingView(
            rootView: AppSettingsView(isActive: true)
                .frame(width: 1_200, height: 760)
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 1_200, height: 760)
        hostedView.layoutSubtreeIfNeeded()
        let baseline = try XCTUnwrap(recorder.latestEvidence)
        XCTAssertFalse(baseline.isGranted)
        let actionButton = try XCTUnwrap(
            settingsPermissionActionButton(in: hostedView)
        )
        let requestTitle = AppStrings.text(
            .permissionAccessibilityRequest,
            language: .simplifiedChinese
        )
        let manageTitle = AppStrings.text(
            .permissionAccessibilityManage,
            language: .simplifiedChinese
        )
        XCTAssertEqual(actionButton.title, requestTitle)

        let grantedReadback = expectation(
            description: "accessibility post-request granted readback"
        )
        let titleUpdated = expectation(
            description: "accessibility action title changed to manage"
        )
        var matchingEvidence: SettingsPermissionReadbackEvidence?
        let titleRecorder = SettingsPermissionTitleRecorder(
            initialTitle: actionButton.title,
            expectedTitle: manageTitle
        ) {
            titleUpdated.fulfill()
        }
        let readbackObservation = recorder.observe(
            after: baseline.generation
        ) { evidence in
            guard matchingEvidence == nil, evidence.isGranted else { return }
            matchingEvidence = evidence
            grantedReadback.fulfill()
        }
        defer { readbackObservation.cancel() }
        let titleObservation = actionButton.observe(
            \.title,
            options: [.new]
        ) { _, change in
            guard let title = change.newValue else { return }
            MainActor.assumeIsolated {
                titleRecorder.record(title)
            }
        }
        defer {
            titleObservation.invalidate()
            titleRecorder.cancel()
        }

        actionButton.performClick(nil)

        XCTAssertEqual(scenario.requestCount, 1)
        await fulfillment(
            of: [grantedReadback, titleUpdated],
            timeout: SettingsPermissionReadbackPolicy.watchdogTimeout
        )
        hostedView.layoutSubtreeIfNeeded()

        let finalEvidence = try XCTUnwrap(
            matchingEvidence,
            "Permission readback watchdog expired: baseline=\(baseline.diagnosticSummary) last=\(recorder.latestEvidence?.diagnosticSummary ?? "none") title=\(titleRecorder.latestTitle)"
        )
        XCTAssertGreaterThan(finalEvidence.generation, baseline.generation)
        XCTAssertTrue(finalEvidence.isGranted)
        XCTAssertEqual(actionButton.title, manageTitle)
    }

    @MainActor
    func testSettingsPermissionReadbackRecorderUsesGenerationAndCancellation() {
        let recorder = SettingsPermissionReadbackRecorder()
        recorder.record(false)
        let baselineGeneration = recorder.latestEvidence?.generation ?? 0
        var deliveredGenerations: [UInt64] = []
        let observation = recorder.observe(after: baselineGeneration) {
            evidence in
            guard evidence.isGranted else { return }
            deliveredGenerations.append(evidence.generation)
        }

        recorder.record(false)
        recorder.record(true)
        observation.cancel()
        recorder.record(true)

        XCTAssertEqual(deliveredGenerations, [baselineGeneration + 2])
        XCTAssertEqual(
            recorder.latestEvidence?.generation,
            baselineGeneration + 3
        )
    }

    private func settingsPermissionActionButton(
        in view: NSView
    ) -> NSButton? {
        if (view.identifier?.rawValue
            == "flowtab.settings.permission.accessibility-action"
            || view.accessibilityIdentifier()
                == "flowtab.settings.permission.accessibility-action"),
           let button = view as? NSButton {
            return button
        }
        for subview in view.subviews {
            if let button = settingsPermissionActionButton(in: subview) {
                return button
            }
        }
        return nil
    }

    private func restoreSettingsPermissionDefault(
        _ value: String?,
        forKey key: String
    ) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
