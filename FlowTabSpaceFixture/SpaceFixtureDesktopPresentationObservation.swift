import AppKit

@MainActor
final class SpaceFixtureDesktopPresentationObservation:
    SpaceFixtureCancellable
{
    private struct Registration {
        let center: NotificationCenter
        let token: NSObjectProtocol
    }

    private var registrations: [Registration] = []
    private var onChange:
        (@MainActor (SpaceFixtureDesktopPresentationEvidenceSource) -> Void)?

    init(
        window: NSWindow,
        onChange:
            @escaping @MainActor (
                SpaceFixtureDesktopPresentationEvidenceSource
            ) -> Void
    ) {
        self.onChange = onChange
        register(
            center: .default,
            name: NSWindow.didBecomeKeyNotification,
            object: window,
            source: .windowDidBecomeKey
        )
        register(
            center: .default,
            name: NSWindow.didBecomeMainNotification,
            object: window,
            source: .windowDidBecomeMain
        )
        register(
            center: .default,
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            source: .windowDidChangeOcclusion
        )
        register(
            center: .default,
            name: NSWindow.didDeminiaturizeNotification,
            object: window,
            source: .windowDidDeminiaturize
        )
        register(
            center: .default,
            name: NSApplication.didBecomeActiveNotification,
            object: NSApplication.shared,
            source: .applicationDidBecomeActive
        )
        register(
            center: NSWorkspace.shared.notificationCenter,
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            source: .activeSpaceDidChange
        )
    }

    func cancel() {
        removeObservers()
        onChange = nil
    }

    private func register(
        center: NotificationCenter,
        name: Notification.Name,
        object: Any?,
        source: SpaceFixtureDesktopPresentationEvidenceSource
    ) {
        let token = center.addObserver(
            forName: name,
            object: object,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onChange?(source)
            }
        }
        registrations.append(
            Registration(center: center, token: token)
        )
    }

    private func removeObservers() {
        for registration in registrations {
            registration.center.removeObserver(
                registration.token
            )
        }
        registrations.removeAll()
    }

    deinit {
        for registration in registrations {
            registration.center.removeObserver(
                registration.token
            )
        }
    }
}
