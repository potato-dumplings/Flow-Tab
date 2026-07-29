import AppKit
import SwiftUI
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testRuntimeLogsDropdownUpdatesRuntimeLogLevelBinding() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        var diagnosticSessionExpiration = 0.0
        var runtimeLogLevelRaw = RuntimeLogLevel.info.rawValue
        let hostedView = NSHostingView(
            rootView: RuntimeLogsSection(
                diagnosticSessionExpiration: Binding(
                    get: { diagnosticSessionExpiration },
                    set: { diagnosticSessionExpiration = $0 }
                ),
                runtimeLogLevelRaw: Binding(
                    get: { runtimeLogLevelRaw },
                    set: { runtimeLogLevelRaw = $0 }
                ),
                hotkeyShortcutText: "Option + Tab",
                appLanguage: .english,
                targetAppearance: appearance
            )
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 620, height: 620)
        hostedView.layoutSubtreeIfNeeded()

        let dropdown: FlowDropdownControl = try XCTUnwrap(
            runtimeLogsDescendant(
                in: hostedView,
                identifier: "flowtab.logs.level"
            )
        )
        XCTAssertNil(
            runtimeLogsDescendant(in: hostedView, as: NSPopUpButton.self)
        )

        dropdown.selectOptionForTesting(RuntimeLogLevel.warning.rawValue)

        XCTAssertEqual(runtimeLogLevelRaw, RuntimeLogLevel.warning.rawValue)
        XCTAssertEqual(
            dropdown.selectedIdentifierForTesting,
            RuntimeLogLevel.warning.rawValue
        )
    }

    private func runtimeLogsDescendant<View: NSView>(
        in view: NSView,
        identifier: String
    ) -> View? {
        if view.identifier?.rawValue == identifier
            || view.accessibilityIdentifier() == identifier
        {
            return view as? View
        }
        for subview in view.subviews {
            if let match: View = runtimeLogsDescendant(
                in: subview,
                identifier: identifier
            ) {
                return match
            }
        }
        return nil
    }

    private func runtimeLogsDescendant<View: NSView>(
        in view: NSView,
        as type: View.Type
    ) -> View? {
        if let match = view as? View {
            return match
        }
        for subview in view.subviews {
            if let match = runtimeLogsDescendant(in: subview, as: type) {
                return match
            }
        }
        return nil
    }
}
