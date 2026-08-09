#if FLOWTAB_TESTING
import AppKit
import Combine
import Foundation

enum FlowTabUITestSearchTriggerPresentationEvidenceSource:
    String,
    Equatable
{
    case initialReadback
    case triggerReadback
    case searchStateDidChange
    case panelDidBecomeKey
    case panelDidExpose
}

struct FlowTabUITestSearchTriggerPresentationSnapshot:
    Equatable
{
    let panelIsPresented: Bool
    let panelIsKey: Bool
    let searchIsActive: Bool
    let searchActivationIsPending: Bool

    var isSatisfied: Bool {
        panelIsPresented
            && panelIsKey
            && searchIsActive
            && !searchActivationIsPending
    }

    var logFields: String {
        "panelPresented=\(panelIsPresented ? 1 : 0) "
            + "panelKey=\(panelIsKey ? 1 : 0) "
            + "searchActive=\(searchIsActive ? 1 : 0) "
            + "searchPending="
            + "\(searchActivationIsPending ? 1 : 0)"
    }
}

struct FlowTabUITestSearchTriggerPresentationEvidence:
    Equatable
{
    let observationGeneration: UInt64
    let evidenceGeneration: UInt64
    let source:
        FlowTabUITestSearchTriggerPresentationEvidenceSource
    let snapshot:
        FlowTabUITestSearchTriggerPresentationSnapshot

    var isSatisfied: Bool {
        snapshot.isSatisfied
    }

    var logFields: String {
        "generation=\(observationGeneration) "
            + "evidenceGeneration=\(evidenceGeneration) "
            + "source=\(source.rawValue) "
            + "snapshot{\(snapshot.logFields)}"
    }
}

typealias FlowTabUITestSearchTriggerPresentationObservationRegistration =
    @MainActor (
        @escaping @MainActor (
            FlowTabUITestSearchTriggerPresentationEvidenceSource
        ) -> Void
    ) -> any FlowTabUITestInitialPresentationCancellable

@MainActor
final class FlowTabUITestSearchTriggerPresentationObservationOwner {
    private struct ActiveObservation {
        let generation: UInt64
        var nextEvidenceGeneration: UInt64
        var cancellation:
            (any FlowTabUITestInitialPresentationCancellable)?
        let onResolved:
            (FlowTabUITestSearchTriggerPresentationEvidence) -> Void
    }

    private let observationRegistration:
        FlowTabUITestSearchTriggerPresentationObservationRegistration
    private let readback:
        @MainActor () ->
            FlowTabUITestSearchTriggerPresentationSnapshot

    private var active: ActiveObservation?

    private(set) var observationGeneration: UInt64 = 0
    private(set) var lastEvidence:
        FlowTabUITestSearchTriggerPresentationEvidence?
    private(set) var lastResolution:
        FlowTabUITestSearchTriggerPresentationEvidence?

    init(
        observationRegistration:
            @escaping FlowTabUITestSearchTriggerPresentationObservationRegistration,
        readback:
            @escaping @MainActor () ->
                FlowTabUITestSearchTriggerPresentationSnapshot
    ) {
        self.observationRegistration =
            observationRegistration
        self.readback = readback
    }

    var isObserving: Bool {
        active != nil
    }

    @discardableResult
    func start(
        onResolved:
            @escaping (
                FlowTabUITestSearchTriggerPresentationEvidence
            ) -> Void
    ) -> UInt64 {
        cancel(invalidate: false)
        observationGeneration &+= 1
        let generation = observationGeneration
        lastEvidence = nil
        lastResolution = nil
        active = ActiveObservation(
            generation: generation,
            nextEvidenceGeneration: 0,
            cancellation: nil,
            onResolved: onResolved
        )

        let cancellation = observationRegistration {
            [weak self] source in
            _ = self?.observe(
                source,
                generation: generation
            )
        }
        guard var current = active,
              current.generation == generation
        else {
            cancellation.cancel()
            return generation
        }
        current.cancellation = cancellation
        active = current
        _ = evaluate(
            source: .initialReadback,
            generation: generation
        )
        return generation
    }

    @discardableResult
    func observe(
        _ source:
            FlowTabUITestSearchTriggerPresentationEvidenceSource,
        generation: UInt64
    ) -> Bool {
        evaluate(
            source: source,
            generation: generation
        )
    }

    func cancel() {
        cancel(invalidate: true)
    }

    deinit {
        let cancellation = active?.cancellation
        Task { @MainActor [cancellation] in
            cancellation?.cancel()
        }
    }

    @discardableResult
    private func evaluate(
        source:
            FlowTabUITestSearchTriggerPresentationEvidenceSource,
        generation: UInt64
    ) -> Bool {
        guard var current = active,
              current.generation == generation
        else {
            return false
        }
        let evidence =
            FlowTabUITestSearchTriggerPresentationEvidence(
                observationGeneration: generation,
                evidenceGeneration:
                    current.nextEvidenceGeneration,
                source: source,
                snapshot: readback()
            )
        current.nextEvidenceGeneration &+= 1
        active = current
        lastEvidence = evidence
        guard evidence.isSatisfied else { return false }
        guard let completed = takeActive() else {
            return false
        }
        lastResolution = evidence
        completed.onResolved(evidence)
        return true
    }

    private func cancel(invalidate: Bool) {
        let hadActive = active != nil
        _ = takeActive()
        if invalidate && hadActive {
            observationGeneration &+= 1
        }
    }

    private func takeActive() -> ActiveObservation? {
        guard let active else { return nil }
        self.active = nil
        active.cancellation?.cancel()
        return active
    }
}

@MainActor
private final class FlowTabUITestSearchTriggerPresentationCancellation:
    FlowTabUITestInitialPresentationCancellable
{
    private let center: NotificationCenter
    private var notificationTokens: [NSObjectProtocol] = []
    private var searchStateCancellable: AnyCancellable?

    init(center: NotificationCenter) {
        self.center = center
    }

    func retainSearchStateCancellable(
        _ cancellable: AnyCancellable
    ) {
        searchStateCancellable = cancellable
    }

    func retainNotificationToken(_ token: NSObjectProtocol) {
        notificationTokens.append(token)
    }

    func cancel() {
        searchStateCancellable?.cancel()
        searchStateCancellable = nil
        notificationTokens.forEach(center.removeObserver)
        notificationTokens.removeAll()
    }

    deinit {
        searchStateCancellable?.cancel()
        notificationTokens.forEach(center.removeObserver)
    }
}

final class SwitcherTriggerNotificationObserver: NSObject {
    enum Trigger: Sendable {
        case global
        case inApp
        case search
    }

    private let name: Notification.Name
    private weak var panelController: SwitcherPanelController?
    private let trigger: Trigger
    private var searchPresentationOwner:
        FlowTabUITestSearchTriggerPresentationObservationOwner?

    init(
        name: Notification.Name,
        panelController: SwitcherPanelController,
        trigger: Trigger
    ) {
        self.name = name
        self.panelController = panelController
        self.trigger = trigger
        super.init()
    }

    @MainActor
    func install(in center: CFNotificationCenter?) {
        CFNotificationCenterAddObserver(
            center,
            UnsafeRawPointer(
                Unmanaged.passUnretained(self).toOpaque()
            ),
            Self.handleDarwinNotification,
            name.rawValue as CFString,
            nil,
            .deliverImmediately
        )
    }

    @MainActor
    func uninstall(from center: CFNotificationCenter?) {
        let notificationName =
            CFNotificationName(name.rawValue as CFString)
        CFNotificationCenterRemoveObserver(
            center,
            UnsafeRawPointer(
                Unmanaged.passUnretained(self).toOpaque()
            ),
            notificationName,
            nil
        )
        searchPresentationOwner?.cancel()
        searchPresentationOwner = nil
        if trigger == .search,
           let panelController
        {
            Self.releasePrimaryModifierForTesting(
                panelController: panelController
            )
        }
    }

    deinit {
        let searchPresentationOwner = searchPresentationOwner
        Task { @MainActor in
            searchPresentationOwner?.cancel()
        }
    }

    private static let handleDarwinNotification:
        CFNotificationCallback =
    { _, observer, name, _, _ in
        guard let observer else { return }
        let notificationObserver =
            Unmanaged<SwitcherTriggerNotificationObserver>
                .fromOpaque(observer)
                .takeUnretainedValue()
        notificationObserver.handleDarwinNotification(
            name: name.map { $0.rawValue as String }
        )
    }

    private func handleDarwinNotification(
        name receivedName: String?
    ) {
        let notificationName = receivedName ?? name.rawValue
        Task { @MainActor [weak self] in
            self?.handleDarwinNotificationOnMainActor(
                notificationName: notificationName
            )
        }
    }

    @MainActor
    private func handleDarwinNotificationOnMainActor(
        notificationName: String
    ) {
        guard let panelController else { return }
        panelController
            .setModifierReleaseConfirmationSuppressedForTesting(
                true
            )
        Self.holdPrimaryModifierForTesting(
            trigger,
            panelController: panelController
        )
        RuntimeLog.info(
            "UITest",
            "received switcher trigger notification "
                + "name=\(notificationName)"
        )

        if trigger == .search {
            handleSearchTrigger(
                notificationName: notificationName,
                panelController: panelController
            )
            return
        }

        let presented = Self.presentSwitcher(
            trigger,
            panelController: panelController
        )
        if !presented {
            Self.releasePrimaryModifierForTesting(
                panelController: panelController
            )
        }
        RuntimeLog.info(
            "UITest",
            "completed switcher trigger notification "
                + "name=\(notificationName) "
                + "presented=\(presented ? 1 : 0) "
                + "syntheticModifierHeld="
                + "\(presented ? 1 : 0)"
        )
    }

    @MainActor
    private func handleSearchTrigger(
        notificationName: String,
        panelController: SwitcherPanelController
    ) {
        let owner = searchPresentationOwner
            ?? Self.makeSearchPresentationOwner(
                panelController: panelController
            )
        searchPresentationOwner = owner
        let generation = owner.start {
            [weak self] evidence in
            guard let self,
                  self.searchPresentationOwner?
                    .observationGeneration
                    == evidence.observationGeneration
            else {
                return
            }
            RuntimeLog.info(
                "UITest",
                "completed switcher trigger notification "
                    + "name=\(notificationName) "
                    + "presented=1 syntheticModifierHeld=1 "
                    + "evidence{\(evidence.logFields)}"
            )
        }
        guard owner.isObserving else { return }

        _ = Self.presentSwitcher(
            .search,
            panelController: panelController
        )
        _ = owner.observe(
            .triggerReadback,
            generation: generation
        )
        guard owner.isObserving,
              let evidence = owner.lastEvidence
        else {
            return
        }
        if evidence.snapshot.searchIsActive
            || evidence.snapshot.searchActivationIsPending
        {
            RuntimeLog.info(
                "UITest",
                "awaiting switcher trigger presentation "
                    + "name=\(notificationName) "
                    + evidence.logFields
            )
            return
        }

        owner.cancel()
        Self.releasePrimaryModifierForTesting(
            panelController: panelController
        )
        RuntimeLog.info(
            "UITest",
            "completed switcher trigger notification "
                + "name=\(notificationName) "
                + "presented=0 syntheticModifierHeld=0 "
                + "evidence{\(evidence.logFields)}"
        )
    }

    @MainActor
    private static func makeSearchPresentationOwner(
        panelController: SwitcherPanelController
    ) -> FlowTabUITestSearchTriggerPresentationObservationOwner {
        let center = NotificationCenter.default
        return FlowTabUITestSearchTriggerPresentationObservationOwner(
            observationRegistration: {
                [weak panelController] observe in
                let cancellation =
                    FlowTabUITestSearchTriggerPresentationCancellation(
                        center: center
                    )
                guard let panelController else {
                    return cancellation
                }
                let model = panelController.modelForTesting
                let searchStateCancellable =
                    model.$searchViewState
                        .dropFirst()
                        .sink { _ in
                            Task { @MainActor in
                                observe(.searchStateDidChange)
                            }
                        }
                cancellation.retainSearchStateCancellable(
                    searchStateCancellable
                )
                let panel = panelController.panel
                let panelDidBecomeKey = center.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: panel,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        observe(.panelDidBecomeKey)
                    }
                }
                cancellation.retainNotificationToken(
                    panelDidBecomeKey
                )
                let panelDidExpose = center.addObserver(
                    forName: NSWindow.didExposeNotification,
                    object: panel,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        observe(.panelDidExpose)
                    }
                }
                cancellation.retainNotificationToken(
                    panelDidExpose
                )
                return cancellation
            },
            readback: { [weak panelController] in
                guard let panelController else {
                    return FlowTabUITestSearchTriggerPresentationSnapshot(
                        panelIsPresented: false,
                        panelIsKey: false,
                        searchIsActive: false,
                        searchActivationIsPending: false
                    )
                }
                let model = panelController.modelForTesting
                return FlowTabUITestSearchTriggerPresentationSnapshot(
                    panelIsPresented:
                        panelController.isPanelPresented,
                    panelIsKey:
                        panelController.panel.isKeyWindow,
                    searchIsActive: model.isSearchActive,
                    searchActivationIsPending:
                        model.pendingSearchActivationAfterFreshnessBarrier
                )
            }
        )
    }

    @MainActor
    private static func holdPrimaryModifierForTesting(
        _ trigger: Trigger,
        panelController: SwitcherPanelController
    ) {
        // Darwin test triggers have no hardware key state. The launched test
        // process owns this hold until its exact termination, matching a
        // user's held shortcut while visibility recovery publishes an
        // interactable panel.
        releasePrimaryModifierForTesting(
            panelController: panelController
        )
        switch trigger {
        case .global, .search:
            panelController.globalPrimaryModifierPressedOverride =
                true
        case .inApp:
            panelController.inAppPrimaryModifierPressedOverride =
                true
        }
    }

    @MainActor
    private static func releasePrimaryModifierForTesting(
        panelController: SwitcherPanelController
    ) {
        panelController.globalPrimaryModifierPressedOverride = nil
        panelController.inAppPrimaryModifierPressedOverride = nil
    }

    @MainActor
    private static func presentSwitcher(
        _ trigger: Trigger,
        panelController: SwitcherPanelController
    ) -> Bool {
        FlowTabUITestBootstrapper
            .installInitialPanelOcclusionStaleOverrideIfNeeded(
                panelController: panelController
            )
        switch trigger {
        case .global:
            return panelController
                .presentGlobalHotkeySessionForTesting()
        case .inApp:
            FlowTabUITestBootstrapper
                .synchronizeFrontmostAppOverrideIfNeeded()
            return panelController
                .presentInAppWindowHotkeySessionForTesting()
        case .search:
            return panelController
                .presentSearchHotkeySessionForTesting()
        }
    }
}
#endif
