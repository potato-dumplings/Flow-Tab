import AppKit
import SwiftUI
import FlowTabCore

@MainActor
final class SystemThemeState: ObservableObject {
    static let shared = SystemThemeState()

    @Published private(set) var colorScheme: ColorScheme = .light

    private var appearanceObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?

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
        }
    }
}

extension ThemeMode {
    func resolvedColorScheme(systemColorScheme: ColorScheme) -> ColorScheme {
        switch self {
        case .followSystem:
            return systemColorScheme
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
