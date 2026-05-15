import Foundation
import XCTest

extension FlowTabUITests {
    func flowTabStatusItem(
        in app: XCUIApplication? = nil,
        timeout: TimeInterval = 6
    ) -> XCUIElement {
        let systemUIServer = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
        let predicate = NSPredicate(
            format: "identifier == %@ OR label == %@ OR label == %@",
            Identifier.statusItem,
            "FlowTab",
            "Flow Tab"
        )
        let queries = ([app].compactMap { $0 } + [systemUIServer]).map {
            $0.descendants(matching: .any).matching(predicate).firstMatch
        }

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let statusItem = queries.first(where: { $0.exists }) {
                return statusItem
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail("Missing FlowTab status item")
        return queries.first ?? systemUIServer.descendants(matching: .any).firstMatch
    }

    func flowTabStatusMenuQuitItem(
        in app: XCUIApplication? = nil,
        timeout: TimeInterval = 6
    ) -> XCUIElement {
        let systemUIServer = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
        let predicate = NSPredicate(
            format: "identifier == %@ OR label == %@ OR label == %@",
            Identifier.statusItemQuit,
            "退出",
            "Quit"
        )
        let queries = ([app].compactMap { $0 } + [systemUIServer]).map {
            $0.descendants(matching: .any).matching(predicate).firstMatch
        }

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let quitItem = queries.first(where: { $0.exists }) {
                return quitItem
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail("Missing status-item quit menu item")
        return queries.first ?? systemUIServer.descendants(matching: .any).firstMatch
    }
}
