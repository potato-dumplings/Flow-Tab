import AppKit
import SwiftUI
import XCTest
@testable import FlowTab
import FlowTabCore
import Carbon

private final class TestTemporaryRegularActivationToken:
    TemporaryRegularActivationCancellable
{
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

@MainActor
final class TestAppWindow:
    AppWindowOpeningWindow,
    AppWindowPresentationEvidenceObserving
{
    let isPanelWindow: Bool
    var isMiniaturized: Bool
    var isVisible: Bool
    let canBecomeKeyWindow: Bool
    let isAppContentWindow: Bool
    let flowTabWindowLevel: NSWindow.Level
    let flowTabWindowIdentifier: String?

    private(set) var deminiaturizeCallCount = 0
    private(set) var makeKeyAndOrderFrontCallCount = 0
    private(set) var orderFrontRegardlessCallCount = 0
    private var presentationEvidenceObservers: [
        (
            token: TestTemporaryRegularActivationToken,
            action: @MainActor @Sendable (
                TemporaryRegularActivationEvidenceSource
            ) -> Void
        )
    ] = []

    var activePresentationEvidenceObserverCount: Int {
        presentationEvidenceObservers.filter {
            !$0.token.isCancelled
        }.count
    }

    init(
        isPanelWindow: Bool,
        isMiniaturized: Bool,
        isVisible: Bool = true,
        canBecomeKeyWindow: Bool = true,
        isAppContentWindow: Bool = true,
        flowTabWindowLevel: NSWindow.Level = .normal,
        flowTabWindowIdentifier: String? = nil
    ) {
        self.isPanelWindow = isPanelWindow
        self.isMiniaturized = isMiniaturized
        self.isVisible = isVisible
        self.canBecomeKeyWindow = canBecomeKeyWindow
        self.isAppContentWindow = isAppContentWindow
        self.flowTabWindowLevel = flowTabWindowLevel
        self.flowTabWindowIdentifier = flowTabWindowIdentifier
    }

    func deminiaturize(_ sender: Any?) {
        deminiaturizeCallCount += 1
        let wasMiniaturized = isMiniaturized
        isMiniaturized = false
        if wasMiniaturized {
            emitPresentationEvidence(.windowDidDeminiaturize)
        }
    }

    func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyAndOrderFrontCallCount += 1
        emitPresentationEvidence(.windowDidBecomeKey)
    }

    func orderFrontRegardless() {
        orderFrontRegardlessCallCount += 1
    }

    func observeFlowTabWindowPresentationEvidence(
        _ action: @escaping @MainActor @Sendable (
            TemporaryRegularActivationEvidenceSource
        ) -> Void
    ) -> any TemporaryRegularActivationCancellable {
        let token = TestTemporaryRegularActivationToken()
        presentationEvidenceObservers.append((token, action))
        return token
    }

    @MainActor
    func emitPresentationEvidence(
        _ source: TemporaryRegularActivationEvidenceSource
    ) {
        for observer in presentationEvidenceObservers
        where !observer.token.isCancelled {
            observer.action(source)
        }
    }
}

@MainActor
final class TestAppWindowApplication:
    AppWindowOpeningApplication,
    AppActivationEvidenceObserving
{
    var isHidden: Bool
    var flowTabIsActive: Bool
    let appWindows: [any AppWindowOpeningWindow]

    private(set) var activateCallCount = 0
    private(set) var lastActivateIgnoringOtherApps: Bool?
    private(set) var unhideCallCount = 0
    private(set) var showSettingsWindowActionCount = 0
    private var activationEvidenceObservers: [
        (
            token: TestTemporaryRegularActivationToken,
            action: @MainActor @Sendable (
                TemporaryRegularActivationEvidenceSource
            ) -> Void
        )
    ] = []

    var activeActivationEvidenceObserverCount: Int {
        activationEvidenceObservers.filter {
            !$0.token.isCancelled
        }.count
    }

    init(
        isHidden: Bool,
        isActive: Bool = false,
        appWindows: [any AppWindowOpeningWindow]
    ) {
        self.isHidden = isHidden
        flowTabIsActive = isActive
        self.appWindows = appWindows
    }

    func activate(ignoringOtherApps flag: Bool) {
        activateCallCount += 1
        lastActivateIgnoringOtherApps = flag
        guard !flowTabIsActive else { return }
        flowTabIsActive = true
        emitActivationEvidence(.applicationDidBecomeActive)
    }

    func unhide(_ sender: Any?) {
        unhideCallCount += 1
        let wasHidden = isHidden
        isHidden = false
        if wasHidden {
            emitActivationEvidence(.applicationDidUnhide)
        }
    }

    func sendShowSettingsWindowAction() -> Bool {
        showSettingsWindowActionCount += 1
        return true
    }

    func observeFlowTabActivationEvidence(
        _ action: @escaping @MainActor @Sendable (
            TemporaryRegularActivationEvidenceSource
        ) -> Void
    ) -> any TemporaryRegularActivationCancellable {
        let token = TestTemporaryRegularActivationToken()
        activationEvidenceObservers.append((token, action))
        return token
    }

    @MainActor
    func emitActivationEvidence(
        _ source: TemporaryRegularActivationEvidenceSource
    ) {
        for observer in activationEvidenceObservers
        where !observer.token.isCancelled {
            observer.action(source)
        }
    }
}

final class TestActivationPolicyApplication: AppActivationPolicyApplying {
    private(set) var appliedPolicies: [NSApplication.ActivationPolicy] = []
    var flowTabActivationPolicy: NSApplication.ActivationPolicy

    init(initialPolicy: NSApplication.ActivationPolicy = .regular) {
        flowTabActivationPolicy = initialPolicy
    }

    func setFlowTabActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
        appliedPolicies.append(policy)
        flowTabActivationPolicy = policy
    }
}

final class TestTerminationApplication: AppTerminationRequesting {
    private(set) var terminateCallCount = 0

    func terminate(_ sender: Any?) {
        terminateCallCount += 1
    }
}
