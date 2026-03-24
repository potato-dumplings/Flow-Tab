import SwiftUI
import AppKit
import ApplicationServices

@main
struct FlowTabAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: SwitcherPanelController?
    private var hotkeyMonitor: OptionTabHotkeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let panelController = SwitcherPanelController()
        self.panelController = panelController

        let hotkeyMonitor = OptionTabHotkeyMonitor()
        hotkeyMonitor.onHotkeyPressed = { [weak panelController] isBackward in
            panelController?.handleGlobalHotkey(isBackward: isBackward)
        }
        self.hotkeyMonitor = hotkeyMonitor

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyMonitor?.stop()
    }
}
