import AppKit
import SwiftUI

struct FlowDropdownRepresentable: NSViewRepresentable {
    @Binding var selectedID: String

    let options: [FlowDropdownOption]
    let presentation: FlowDropdownPresentation
    let accessibilityIdentifier: String?
    var isEnabled = true

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedID: $selectedID)
    }

    func makeNSView(context: Context) -> FlowDropdownControl {
        let control = FlowDropdownControl(frame: .zero)
        configure(control, context: context)
        return control
    }

    func updateNSView(_ nsView: FlowDropdownControl, context: Context) {
        context.coordinator.selectedID = $selectedID
        configure(nsView, context: context)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: FlowDropdownControl,
        context: Context
    ) -> CGSize? {
        nsView.intrinsicContentSize
    }

    private func configure(_ control: FlowDropdownControl, context: Context) {
        if let accessibilityIdentifier {
            control.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
            control.setAccessibilityIdentifier(accessibilityIdentifier)
        }
        control.isEnabled = isEnabled
        control.onSelectionChanged = { id in
            context.coordinator.selectedID.wrappedValue = id
        }
        control.configure(
            options: options,
            selectedID: selectedID,
            presentation: presentation
        )
    }

    final class Coordinator {
        var selectedID: Binding<String>

        init(selectedID: Binding<String>) {
            self.selectedID = selectedID
        }
    }
}
