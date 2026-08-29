import SwiftUI

@main
struct FlowTabApp: App {
    static var mruTracker: any MRUTracking = SystemAppMRUTracker.shared

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var presentation = FlowPresentationState.shared

    init() {
#if FLOWTAB_TESTING
        FlowTabUITestBootstrapper.prepareIfNeeded()
#endif
        Self.mruTracker.startIfNeeded()
    }

    private static var runtimeProjectionService: any RuntimeProjectionServing {
#if FLOWTAB_TESTING
        FlowTabUITestBootstrapper.resolvedRuntimeProjectionService
#else
        sharedRuntimeProjectionService
#endif
    }

    var body: some Scene {
#if !FLOWTAB_TESTING
        homeWindowScene
#endif
        settingsScene
    }

    private var homeWindowScene: some Scene {
        WindowGroup("FlowTab") {
            HomeRootView(
                runtimeProjectionService: Self.runtimeProjectionService
            )
                .frame(minWidth: AppWindowLayout.width, minHeight: AppWindowLayout.height)
        }
        .defaultSize(width: AppWindowLayout.width, height: AppWindowLayout.height)
        .windowStyle(.hiddenTitleBar)
    }

    private var settingsScene: some Scene {
        Settings {
            HomeRootView(
                runtimeProjectionService: Self.runtimeProjectionService
            )
                .frame(minWidth: AppWindowLayout.width, minHeight: AppWindowLayout.height)
        }
        .windowStyle(.hiddenTitleBar)

        .commands {
            CommandGroup(after: .appInfo) {
                Button(
                    AppStrings.text(
                        .menuCheckForUpdates,
                        language: presentation.context.appLanguage
                    )
                ) {
                    FlowTabUpdatePresentationStore.shared
                        .showAvailableUpdate()
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button(AppStrings.text(.menuSettings, language: presentation.context.appLanguage)) {
                    AppWindowCoordinator.openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
