import AppKit

final class FlowDropdownMenuWindowController {
    var onClose: (() -> Void)?

    private let panel: NSPanel
    private let menuView: FlowDropdownMenuView
    private weak var control: FlowDropdownControl?
    private var localEventMonitor: Any?
    private var notificationObservers: [NSObjectProtocol] = []
    private var layout: FlowDropdownMenuLayout
    private var isClosed = false

    init(
        control: FlowDropdownControl,
        menuView: FlowDropdownMenuView,
        layout: FlowDropdownMenuLayout
    ) {
        self.control = control
        self.menuView = menuView
        self.layout = layout
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: layout.contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }

    func show() {
        guard let control, let parentWindow = control.window else { return }
        positionPanel()
        parentWindow.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()
        startObserving()
    }

    func update(layout: FlowDropdownMenuLayout) {
        self.layout = layout
        menuView.frame = NSRect(origin: .zero, size: layout.contentSize)
        panel.setContentSize(layout.contentSize)
        positionPanel()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        stopObserving()
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        onClose?()
    }

    private func configurePanel() {
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .ignoresCycle, .moveToActiveSpace]
        panel.contentView = menuView
        menuView.frame = NSRect(origin: .zero, size: layout.contentSize)
        menuView.autoresizingMask = [.width, .height]
    }

    private func positionPanel() {
        panel.setFrame(layout.frame, display: true)
    }

    private func startObserving() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            self?.handle(event) ?? event
        }
        guard let parentWindow = control?.window else { return }
        notificationObservers = [
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                self?.close()
            },
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                self?.close()
            },
            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                self?.repositionIfOpen()
            },
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                self?.repositionIfOpen()
            }
        ]
    }

    private func stopObserving() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        notificationObservers.removeAll()
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown, event.keyCode == 53 {
            close()
            return nil
        }
        if event.window === panel {
            return event
        }
        if event.window === control?.window, let control {
            let pointInControl = control.convert(event.locationInWindow, from: nil)
            if control.bounds.contains(pointInControl) {
                return event
            }
        }
        close()
        return event
    }

    private func repositionIfOpen() {
        guard !isClosed, let control else { return }
        guard let layout = control.makeMenuLayoutForCurrentGeometry() else {
            close()
            return
        }
        update(layout: layout)
    }
}
