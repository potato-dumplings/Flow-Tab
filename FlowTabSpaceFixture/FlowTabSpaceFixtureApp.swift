import SwiftUI

@main
struct FlowTabSpaceFixtureApp: App {
    @NSApplicationDelegateAdaptor(SpaceFixtureAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
