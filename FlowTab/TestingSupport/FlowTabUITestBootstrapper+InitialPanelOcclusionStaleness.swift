#if FLOWTAB_TESTING
import AppKit

@MainActor
extension FlowTabUITestBootstrapper {
    static func installInitialPanelOcclusionStaleOverrideIfNeeded(
        panelController: SwitcherPanelController
    ) {
        guard let rawMilliseconds =
                FlowTabTestLaunchOptions
                    .initialPanelOcclusionStaleMilliseconds
        else {
            stopInitialPanelOcclusionStalenessInjection()
            return
        }
        let policy =
            FlowTabUITestInitialPanelOcclusionStalenessPolicy(
                rawMilliseconds: rawMilliseconds
            )
        let owner =
            initialPanelOcclusionStalenessOwner
            ?? FlowTabUITestInitialPanelOcclusionStalenessOwner()
        initialPanelOcclusionStalenessOwner = owner

        owner.start(
            policy: policy,
            install: {
                [weak panelController] in
                guard let panelController else {
                    return .unavailable
                }
                panelController
                    .panelOcclusionStateOverride = []
                return initialPanelOcclusionReadback(
                    panelController: panelController
                )
            },
            release: {
                [weak panelController] in
                guard let panelController else {
                    return .unavailable
                }
                panelController
                    .panelOcclusionStateOverride =
                        .visible
                panelController
                    .handlePanelOcclusionStateDidChangeForTesting()
                return initialPanelOcclusionReadback(
                    panelController: panelController
                )
            },
            cancelInjection: {
                [weak panelController] in
                guard let panelController else {
                    return .unavailable
                }
                panelController
                    .panelOcclusionStateOverride = nil
                return initialPanelOcclusionReadback(
                    panelController: panelController
                )
            },
            onEvidence: { evidence in
                RuntimeLog.info(
                    "UITest",
                    "initial panel occlusion stale "
                        + evidence.phase.rawValue
                        + " "
                        + evidence.logFields
                )
            }
        )
    }

    static func stopInitialPanelOcclusionStalenessInjection() {
        initialPanelOcclusionStalenessOwner?.cancel()
        initialPanelOcclusionStalenessOwner = nil
    }

    private static func initialPanelOcclusionReadback(
        panelController: SwitcherPanelController
    ) -> FlowTabUITestInitialPanelOcclusionReadback {
        let override =
            panelController.panelOcclusionStateOverride
        return FlowTabUITestInitialPanelOcclusionReadback(
            panelIsAvailable: true,
            overrideIsInstalled: override != nil,
            overrideContainsVisible:
                override?.contains(.visible) == true
        )
    }
}
#endif
