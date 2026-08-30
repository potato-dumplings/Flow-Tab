import Combine

@MainActor
final class HomeRetainedTabLifecycle {
    enum State: Equatable {
        case inactive
        case active
    }

    private let transitionSubject = PassthroughSubject<State, Never>()
    private(set) var state: State

    var transitions: AnyPublisher<State, Never> {
        transitionSubject.eraseToAnyPublisher()
    }

    init(state: State = .inactive) {
        self.state = state
    }

    @discardableResult
    func transition(to state: State) -> Bool {
        guard self.state != state else { return false }
        self.state = state
        transitionSubject.send(state)
        return true
    }
}
