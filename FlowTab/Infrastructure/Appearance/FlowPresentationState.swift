import AppKit
import SwiftUI
import FlowTabCore

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

extension ColorScheme {
    var flowTabNSAppearanceName: NSAppearance.Name {
        self == .dark ? .darkAqua : .aqua
    }
}

final class FlowPresentationThemeObservation {
    private var cancellation: (() -> Void)?

    init(_ cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        guard let cancellation else { return }
        self.cancellation = nil
        cancellation()
    }

    deinit {
        cancel()
    }
}

@MainActor
protocol FlowPresentationSystemThemeProviding: AnyObject {
    var currentColorScheme: ColorScheme { get }

    func observeColorSchemeChanges(
        _ handler: @escaping @MainActor (ColorScheme) -> Void
    ) -> FlowPresentationThemeObservation
}

@MainActor
final class FlowPresentationSystemThemeProvider: FlowPresentationSystemThemeProviding {
    static let shared = FlowPresentationSystemThemeProvider(systemThemeState: .shared)

    private let systemThemeState: SystemThemeState

    private init(systemThemeState: SystemThemeState) {
        self.systemThemeState = systemThemeState
    }

    var currentColorScheme: ColorScheme {
        systemThemeState.refreshColorScheme()
        return systemThemeState.colorScheme
    }

    func observeColorSchemeChanges(
        _ handler: @escaping @MainActor (ColorScheme) -> Void
    ) -> FlowPresentationThemeObservation {
        systemThemeState.observeColorSchemeChanges(handler)
    }
}

struct FlowPresentationContext: Equatable {
    let themeMode: ThemeMode
    let appLanguage: AppLanguage
    let systemColorScheme: ColorScheme
    let resolvedColorScheme: ColorScheme
    let targetNSAppearanceName: NSAppearance.Name

    var appearanceRebuildIdentity: String {
        [
            themeMode.rawValue,
            appLanguage.rawValue,
            targetNSAppearanceName.rawValue
        ].joined(separator: "|")
    }

    var targetNSAppearance: NSAppearance {
        return NSAppearance(named: targetNSAppearanceName) ?? NSApp.effectiveAppearance
    }
}

struct FlowPresentationResolution: Equatable {
    let context: FlowPresentationContext
    let normalizedThemeRaw: String
    let normalizedLanguageRaw: String
}

enum FlowPresentationResolver {
    static func resolve(
        themeRaw: String,
        languageRaw: String,
        systemColorScheme: ColorScheme
    ) -> FlowPresentationResolution {
        let themeMode = ThemePreferencesStore.resolve(rawValue: themeRaw)
        let appLanguage = AppLanguagePreferencesStore.resolve(rawValue: languageRaw)
        let resolvedColorScheme = themeMode.resolvedColorScheme(systemColorScheme: systemColorScheme)
        return FlowPresentationResolution(
            context: FlowPresentationContext(
                themeMode: themeMode,
                appLanguage: appLanguage,
                systemColorScheme: systemColorScheme,
                resolvedColorScheme: resolvedColorScheme,
                targetNSAppearanceName: resolvedColorScheme.flowTabNSAppearanceName
            ),
            normalizedThemeRaw: themeMode.rawValue,
            normalizedLanguageRaw: appLanguage.rawValue
        )
    }
}

@MainActor
final class FlowPresentationState: ObservableObject {
    static let shared = FlowPresentationState()

    @Published private(set) var context: FlowPresentationContext

    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let systemThemeProvider: FlowPresentationSystemThemeProviding
    private let preferredLanguageIdentifiers: [String]
    private var themeObservation: FlowPresentationThemeObservation?

    convenience init(
        userDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        preferredLanguageIdentifiers: [String] = Locale.preferredLanguages
    ) {
        self.init(
            userDefaults: userDefaults,
            notificationCenter: notificationCenter,
            systemThemeProvider: FlowPresentationSystemThemeProvider.shared,
            preferredLanguageIdentifiers: preferredLanguageIdentifiers
        )
    }

    init(
        userDefaults: UserDefaults,
        notificationCenter: NotificationCenter,
        systemThemeProvider: FlowPresentationSystemThemeProviding,
        preferredLanguageIdentifiers: [String] = Locale.preferredLanguages
    ) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
        self.systemThemeProvider = systemThemeProvider
        self.preferredLanguageIdentifiers = preferredLanguageIdentifiers

        let resolution = FlowPresentationResolver.resolve(
            themeRaw: userDefaults.string(forKey: AppPreferenceKeys.themeMode)
                ?? ThemePreferencesStore.defaultMode.rawValue,
            languageRaw: AppLanguagePreferencesStore.load(
                userDefaults: userDefaults,
                preferredLanguageIdentifiers: preferredLanguageIdentifiers
            ).rawValue,
            systemColorScheme: systemThemeProvider.currentColorScheme
        )
        context = resolution.context
        persistNormalizedRawValues(resolution)

        themeObservation = systemThemeProvider.observeColorSchemeChanges { [weak self] _ in
            self?.reloadFromStoredPreferences(postLanguageNotification: false)
        }
    }

    deinit {
        themeObservation?.cancel()
    }

    func setThemeMode(rawValue: String) {
        let resolution = FlowPresentationResolver.resolve(
            themeRaw: rawValue,
            languageRaw: context.appLanguage.rawValue,
            systemColorScheme: systemThemeProvider.currentColorScheme
        )
        apply(resolution, postLanguageNotification: false)
    }

    func setAppLanguage(rawValue: String) {
        let resolution = FlowPresentationResolver.resolve(
            themeRaw: context.themeMode.rawValue,
            languageRaw: rawValue,
            systemColorScheme: systemThemeProvider.currentColorScheme
        )
        apply(resolution, postLanguageNotification: true)
    }

    func refreshFromStoredPreferences(postLanguageNotification: Bool = false) {
        reloadFromStoredPreferences(postLanguageNotification: postLanguageNotification)
    }

    private func reloadFromStoredPreferences(postLanguageNotification: Bool) {
        let resolution = FlowPresentationResolver.resolve(
            themeRaw: userDefaults.string(forKey: AppPreferenceKeys.themeMode)
                ?? ThemePreferencesStore.defaultMode.rawValue,
            languageRaw: AppLanguagePreferencesStore.load(
                userDefaults: userDefaults,
                preferredLanguageIdentifiers: preferredLanguageIdentifiers
            ).rawValue,
            systemColorScheme: systemThemeProvider.currentColorScheme
        )
        apply(resolution, postLanguageNotification: postLanguageNotification)
    }

    private func apply(
        _ resolution: FlowPresentationResolution,
        postLanguageNotification: Bool
    ) {
        let previousLanguage = context.appLanguage
        persistNormalizedRawValues(resolution)
        if context != resolution.context {
            context = resolution.context
        }
        if postLanguageNotification, previousLanguage != resolution.context.appLanguage {
            notificationCenter.post(name: .flowTabLanguagePreferenceChanged, object: self)
        }
    }

    private func persistNormalizedRawValues(_ resolution: FlowPresentationResolution) {
        persistIfNeeded(
            resolution.normalizedThemeRaw,
            forKey: AppPreferenceKeys.themeMode
        )
        persistIfNeeded(
            resolution.normalizedLanguageRaw,
            forKey: AppPreferenceKeys.appLanguage
        )
    }

    private func persistIfNeeded(_ value: String, forKey key: String) {
        guard userDefaults.string(forKey: key) != value else { return }
        userDefaults.set(value, forKey: key)
    }
}
