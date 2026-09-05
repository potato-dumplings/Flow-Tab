#if FLOWTAB_TESTING
import Foundation

@MainActor
enum ControlTabPressureBootstrap {
    private(set) static var run: ControlTabPressureRun?
    private static var preparedRoute: ControlTabPressureRoute?

    static func stop() {
        run?.cancel()
        run = nil
        preparedRoute = nil
    }

    static func prepareIfNeeded(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let route = ControlTabPressureRoute(environment: environment)
        // App initialization and applicationDidFinishLaunching prepare the same run.
        // Its projection observers must retain one shared service across both calls.
        if route == preparedRoute, route == nil || run != nil { return }
        stop()
        preparedRoute = route
        if route != nil { run = ControlTabPressureRun() }
    }

    static var systemProjectionService: any RuntimeProjectionServing {
        run?.systemProjectionService ?? sharedRuntimeProjectionService
    }

    static func configureIfNeeded(panelController: SwitcherPanelController,
                                  environment: [String: String] = ProcessInfo.processInfo.environment) {
        if run == nil { prepareIfNeeded(environment: environment) }
        run?.configureIfNeeded(panelController: panelController, environment: environment)
    }
}
#endif
