import AppKit
import SwiftUI
import XCTest
@testable import FlowTab
import FlowTabCore
import Carbon

final class TestAppWindow: AppWindowOpeningWindow {
    let isPanelWindow: Bool
    var isMiniaturized: Bool
    var isVisible: Bool
    let flowTabWindowIdentifier: String?

    private(set) var deminiaturizeCallCount = 0
    private(set) var makeKeyAndOrderFrontCallCount = 0
    private(set) var orderFrontRegardlessCallCount = 0

    init(
        isPanelWindow: Bool,
        isMiniaturized: Bool,
        isVisible: Bool = true,
        flowTabWindowIdentifier: String? = nil
    ) {
        self.isPanelWindow = isPanelWindow
        self.isMiniaturized = isMiniaturized
        self.isVisible = isVisible
        self.flowTabWindowIdentifier = flowTabWindowIdentifier
    }

    func deminiaturize(_ sender: Any?) {
        deminiaturizeCallCount += 1
        isMiniaturized = false
    }

    func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyAndOrderFrontCallCount += 1
    }

    func orderFrontRegardless() {
        orderFrontRegardlessCallCount += 1
    }
}

final class TestAppWindowApplication: AppWindowOpeningApplication {
    var isHidden: Bool
    let appWindows: [any AppWindowOpeningWindow]

    private(set) var activateCallCount = 0
    private(set) var lastActivateIgnoringOtherApps: Bool?
    private(set) var unhideCallCount = 0
    private(set) var showSettingsWindowActionCount = 0

    init(isHidden: Bool, appWindows: [any AppWindowOpeningWindow]) {
        self.isHidden = isHidden
        self.appWindows = appWindows
    }

    func activate(ignoringOtherApps flag: Bool) {
        activateCallCount += 1
        lastActivateIgnoringOtherApps = flag
    }

    func unhide(_ sender: Any?) {
        unhideCallCount += 1
        isHidden = false
    }

    func sendShowSettingsWindowAction() -> Bool {
        showSettingsWindowActionCount += 1
        return true
    }
}
