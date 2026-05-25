import AppKit
import SwiftUI

@MainActor
final class SystemThemeState: ObservableObject {
    static let shared = SystemThemeState()

    @Published private(set) var colorScheme: ColorScheme = .light

    private var appearanceObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?
    private var colorSchemeObservers: [UUID: @MainActor (ColorScheme) -> Void] = [:]

    private init() {
        refreshColorScheme()

        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshColorScheme()
            }
        }

        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshColorScheme()
            }
        }
    }

    deinit {
        if let appearanceObserver {
            DistributedNotificationCenter.default.removeObserver(appearanceObserver)
        }
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
        }
    }

    private func refreshColorScheme() {
        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let nextColorScheme: ColorScheme = isDark ? .dark : .light
        if colorScheme != nextColorScheme {
            colorScheme = nextColorScheme
            notifyColorSchemeObservers(nextColorScheme)
        }
    }

    func observeColorSchemeChanges(
        _ handler: @escaping @MainActor (ColorScheme) -> Void
    ) -> FlowPresentationThemeObservation {
        let id = UUID()
        colorSchemeObservers[id] = handler
        return FlowPresentationThemeObservation { [weak self] in
            Task { @MainActor [weak self] in
                self?.colorSchemeObservers[id] = nil
            }
        }
    }

    private func notifyColorSchemeObservers(_ colorScheme: ColorScheme) {
        for observer in colorSchemeObservers.values {
            observer(colorScheme)
        }
    }
}
