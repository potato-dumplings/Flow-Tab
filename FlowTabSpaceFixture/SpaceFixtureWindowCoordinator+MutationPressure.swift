import Foundation

extension SpaceFixtureWindowCoordinator {
    func startWindowMutationPressureIfNeeded(
        applicationIdentity: SpaceFixtureApplicationIdentity
    ) {
        guard let route =
                SpaceFixtureWindowMutationPressureRoute.configured(
                    arguments: ProcessInfo.processInfo.arguments
                )
        else {
            return
        }
        let owner = SpaceFixtureWindowMutationPressureOwner(
            route: route,
            identity: SpaceFixtureWindowMutationPressureIdentity(
                bundleIdentifier:
                    applicationIdentity.bundleIdentifier,
                processIdentifier:
                    applicationIdentity.processIdentifier
            ),
            snapshotProvider: { [weak self] in
                let windows = self?.windows ?? []
                return SpaceFixtureWindowMutationPressureSnapshot(
                    activeWindowPlanIndices:
                        windows.map(\.plan.index).sorted(),
                    activeWindowTitlesByPlanIndex: Dictionary(
                        uniqueKeysWithValues: windows.map {
                            ($0.plan.index, $0.plan.title)
                        }
                    ),
                    activeCGWindowIDsByPlanIndex: Dictionary(
                        uniqueKeysWithValues: windows.compactMap {
                            let windowID = $0.currentCGWindowID
                            guard windowID > 0 else { return nil }
                            return ($0.plan.index, windowID)
                        }
                    )
                )
            },
            mutate: { [weak self] action, targetIndex in
                self?.applyWindowMutationPressure(
                    action,
                    targetIndex: targetIndex
                )
            }
        )
        owner.start()
        windowMutationPressureOwner = owner
    }

    private func applyWindowMutationPressure(
        _ action: SpaceFixtureWindowMutationPressureAction,
        targetIndex: Int
    ) {
        switch action {
        case .open:
            guard !windows.contains(where: {
                $0.plan.index == targetIndex
            }),
            let plan = windowMutationPressurePlans[targetIndex]
            else { return }
            let window = windowFactory(plan)
            windows.append(window)
            windows.sort { $0.plan.index < $1.plan.index }
            activateApplication()
            window.show(isKey: true)
            window.postCreatedAccessibilityNotification()
        case .close:
            guard let index = windows.firstIndex(where: {
                $0.plan.index == targetIndex
            }) else { return }
            let window = windows.remove(at: index)
            window.close()
            window.postDestroyedAccessibilityNotification()
            activateApplication()
            windows.first?.show(isKey: true)
        }
        publishApplicationAccessibilityElements()
    }
}
