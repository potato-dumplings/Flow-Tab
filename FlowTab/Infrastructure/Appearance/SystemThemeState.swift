import AppKit
import SwiftUI

@MainActor
final class SystemThemeState: ObservableObject {
    static let shared = SystemThemeState()

    @Published private(set) var colorScheme: ColorScheme = .light

    private var effectiveAppearanceObservation: NSKeyValueObservation?
    private var appearanceObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?
    private var colorSchemeObservers: [UUID: @MainActor (ColorScheme) -> Void] = [:]

    private init() {
        refreshColorScheme()

        installEffectiveAppearanceObservationIfPossible()

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

    private func installEffectiveAppearanceObservationIfPossible() {
        guard effectiveAppearanceObservation == nil else { return }
        if let app = NSApp {
            effectiveAppearanceObservation = app.observe(
                \.effectiveAppearance,
                options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.refreshColorScheme()
                }
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

    func refreshColorScheme() {
        installEffectiveAppearanceObservationIfPossible()
        let nextColorScheme = Self.colorScheme(for: Self.currentEffectiveAppearance())
        if colorScheme != nextColorScheme {
            colorScheme = nextColorScheme
            notifyColorSchemeObservers(nextColorScheme)
        }
    }

    private static func currentEffectiveAppearance() -> NSAppearance {
        NSApp?.effectiveAppearance
            ?? NSAppearance(named: .aqua)!
    }

    static func colorScheme(for appearance: NSAppearance) -> ColorScheme {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .dark
            : .light
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
