import AppKit
import Combine
import FlowTabCore

@MainActor
protocol SwitcherPreviewPublishing {
    func publish(completedCount: Int)
}

@MainActor
final class SwitcherPreviewPublication: SwitcherPreviewPublishing {
    let changes = ObservableObjectPublisher()
    var preparationChanged: (() -> Void)?

    func publish(completedCount: Int) {
        if completedCount > 0 { changes.send() }
        preparationChanged?()
    }
}
