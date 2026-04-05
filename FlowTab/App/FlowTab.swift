import SwiftUI

@main
struct FlowTabApp: App {
    static var mruTracker: any MRUTracking = SystemAppMRUTracker.shared

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let appWindowWidth: CGFloat = 1120
    private let appWindowHeight: CGFloat = 780
    @AppStorage(AppPreferenceKeys.appLanguage)
    private var appLanguageRaw = AppLanguagePreferencesStore.defaultLanguage.rawValue

    private var appLanguage: AppLanguage {
        AppLanguagePreferencesStore.resolve(rawValue: appLanguageRaw)
    }

    init() {
        FlowTabUITestBootstrapper.prepareIfNeeded()
        Self.mruTracker.startIfNeeded()
    }

    var body: some Scene {
        WindowGroup("FlowTab") {
            HomeRootView()
                .frame(minWidth: appWindowWidth, minHeight: appWindowHeight)
                .id(appLanguageRaw)
        }
        .defaultSize(width: appWindowWidth, height: appWindowHeight)
        .windowStyle(.hiddenTitleBar)

        Settings {
            HomeRootView()
                .frame(minWidth: appWindowWidth, minHeight: appWindowHeight)
                .id(appLanguageRaw)
        }
        .windowStyle(.hiddenTitleBar)

        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(AppStrings.text(.menuSettings, language: appLanguage)) {
                    AppWindowCoordinator.openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
