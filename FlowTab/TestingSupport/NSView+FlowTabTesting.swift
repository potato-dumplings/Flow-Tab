import AppKit

extension NSView {
    func setFlowTabTestingIdentifier(_ identifier: String) {
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        setAccessibilityIdentifier(identifier)
    }
}
