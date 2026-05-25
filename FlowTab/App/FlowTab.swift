import SwiftUI

@main
struct FlowTabApp: App {
    static var mruTracker: any MRUTracking = SystemAppMRUTracker.shared

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var presentation = FlowPresentationState.shared

    init() {
        FlowTabUITestBootstrapper.prepareIfNeeded()
        Self.mruTracker.startIfNeeded()
    }

    var body: some Scene {
        WindowGroup("FlowTab") {
            HomeRootView()
                .frame(minWidth: AppWindowLayout.width, minHeight: AppWindowLayout.height)
        }
        .defaultSize(width: AppWindowLayout.width, height: AppWindowLayout.height)
        .windowStyle(.hiddenTitleBar)

        Settings {
            HomeRootView()
                .frame(minWidth: AppWindowLayout.width, minHeight: AppWindowLayout.height)
        }
        .windowStyle(.hiddenTitleBar)

        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(AppStrings.text(.menuSettings, language: presentation.context.appLanguage)) {
                    AppWindowCoordinator.openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
