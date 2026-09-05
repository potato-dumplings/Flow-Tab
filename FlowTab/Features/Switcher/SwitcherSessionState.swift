import Combine
import FlowTabCore

@MainActor
protocol SwitcherSessionManaging: AnyObject {
    var session: SwitcherSession? { get }
    var publisher: AnyPublisher<SwitcherSession?, Never> { get }
    var willChange: ObservableObjectPublisher { get }
    var didPublish: ((SwitcherSession?, SwitcherSession?) -> Void)? { get set }
    func publish(_ session: SwitcherSession?)
    func applying(_ input: KeyInput) -> SwitcherSession?
    func resolvingSelection() -> (session: SwitcherSession, target: ActivationTarget?)?
    func buildWindowSession(app: AppSwitchCandidate, preferences: SwitcherPreferences,
                            direction: CycleDirection, rememberedWindows: [String: String]) -> SwitcherSession?
}

@MainActor
final class SwitcherSessionState: ObservableObject, SwitcherSessionManaging {
    @Published private(set) var session: SwitcherSession?
    var didPublish: ((SwitcherSession?, SwitcherSession?) -> Void)?

    var publisher: AnyPublisher<SwitcherSession?, Never> { $session.eraseToAnyPublisher() }
    var willChange: ObservableObjectPublisher { objectWillChange }

    func publish(_ session: SwitcherSession?) {
        let previous = self.session
        self.session = session
        didPublish?(previous, session)
    }

    func applying(_ input: KeyInput) -> SwitcherSession? {
        guard var session else { return nil }
        session.handle(input)
        return session
    }

    func resolvingSelection() -> (session: SwitcherSession, target: ActivationTarget?)? {
        guard var session else { return nil }
        let target = session.commitSelection()
        return (session, target)
    }

    func buildWindowSession(app: AppSwitchCandidate, preferences: SwitcherPreferences,
                            direction: CycleDirection, rememberedWindows: [String: String]) -> SwitcherSession? {
        var session = SwitcherSession(apps: [app], preferences: preferences,
            triggerDirection: direction, rememberedWindowIDByAppID: rememberedWindows)
        return session.enterWindowCycle(allowSingleWindow: true) ? session : nil
    }
}
