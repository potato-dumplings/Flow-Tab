import AppKit
import SwiftUI

struct SearchSystemTextInputBridge: NSViewRepresentable {
    let query: String
    let cursorPosition: Int
    let isSearchActive: Bool
    let showsInsertionPoint: Bool
    let onInputChanged: (String, Int) -> Void
    let onMarkedTextChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onInputChanged: onInputChanged,
            onMarkedTextChanged: onMarkedTextChanged
        )
    }

    func makeNSView(context: Context) -> SearchSystemTextInputContainerView {
        let view = SearchSystemTextInputContainerView()
        view.textView.delegate = context.coordinator
        context.coordinator.attach(textView: view.textView)
        view.onWindowChanged = {
            [weak coordinator = context.coordinator,
             weak textView = view.textView] window in
            guard let coordinator, let textView else { return }
            coordinator.windowDidChange(
                for: textView,
                to: window
            )
        }
        view.onPresentationSessionActivityChanged = {
            [weak coordinator = context.coordinator,
             weak textView = view.textView] isActive in
            guard let coordinator, let textView else { return }
            coordinator.updatePresentationSessionActivity(
                isActive,
                for: textView
            )
        }
        return view
    }

    func updateNSView(_ nsView: SearchSystemTextInputContainerView, context: Context) {
        context.coordinator.updateCallbacks(
            onInputChanged: onInputChanged,
            onMarkedTextChanged: onMarkedTextChanged
        )
        context.coordinator.synchronize(
            textView: nsView.textView,
            query: query,
            cursorPosition: cursorPosition,
            isSearchActive: isSearchActive,
            showsInsertionPoint: showsInsertionPoint
        )
    }

    static func dismantleNSView(
        _ nsView: SearchSystemTextInputContainerView,
        coordinator: Coordinator
    ) {
        nsView.onWindowChanged = nil
        nsView.onPresentationSessionActivityChanged = nil
        coordinator.detach(textView: nsView.textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private struct InputSnapshot: Equatable {
            let query: String
            let cursorPosition: Int
        }

        private var onInputChanged: (String, Int) -> Void
        private var onMarkedTextChanged: (Bool) -> Void
        private let onKeyboardReadinessChanged: (Bool) -> Void
        private let keyboardReadinessNotificationCenter:
            NotificationCenter
        private var isApplyingViewState = false
        private weak var trackedTextView: NSTextView?
        private var lastPublishedInputSnapshot: InputSnapshot?
        private var lastPublishedMarkedTextState: Bool?
        private var lastPublishedKeyboardReadiness = false
        private var firstResponderSynchronizationGeneration = 0
        private var isKeyboardReadinessActive = false
        private weak var keyboardReadinessWindow: NSWindow?
        private var keyboardReadinessObservers:
            [NSObjectProtocol] = []

        init(
            onInputChanged: @escaping (String, Int) -> Void,
            onMarkedTextChanged: @escaping (Bool) -> Void,
            onKeyboardReadinessChanged:
                @escaping (Bool) -> Void = { _ in },
            keyboardReadinessNotificationCenter:
                NotificationCenter = .default
        ) {
            self.onInputChanged = onInputChanged
            self.onMarkedTextChanged = onMarkedTextChanged
            self.onKeyboardReadinessChanged =
                onKeyboardReadinessChanged
            self.keyboardReadinessNotificationCenter =
                keyboardReadinessNotificationCenter
        }

        func attach(textView: NSTextView) {
            if trackedTextView !== textView {
                cancelKeyboardReadinessObservation()
                publishKeyboardReadiness(false)
            }
            trackedTextView = textView
        }

        func detach(textView: NSTextView) {
            guard trackedTextView === textView else { return }
            firstResponderSynchronizationGeneration &+= 1
            isKeyboardReadinessActive = false
            cancelKeyboardReadinessObservation()
            trackedTextView = nil
            onMarkedTextChanged(false)
            publishKeyboardReadiness(false)
        }

        func windowDidChange(
            for textView: NSTextView,
            to window: NSWindow?
        ) {
            guard trackedTextView === textView else { return }
            firstResponderSynchronizationGeneration &+= 1
            guard isKeyboardReadinessActive,
                  let window
            else {
                cancelKeyboardReadinessObservation()
                publishKeyboardReadiness(false)
                return
            }
            observeKeyboardReadiness(
                for: textView,
                in: window
            )
            synchronizeExactFirstResponder(
                for: textView,
                in: window
            )
        }

        func updateCallbacks(
            onInputChanged: @escaping (String, Int) -> Void,
            onMarkedTextChanged: @escaping (Bool) -> Void
        ) {
            self.onInputChanged = onInputChanged
            self.onMarkedTextChanged = onMarkedTextChanged
        }

        func updatePresentationSessionActivity(
            _ isActive: Bool,
            for textView: NSTextView
        ) {
            guard trackedTextView === textView else { return }
            // The active root update owns responder restoration. Restoring here
            // would enqueue responder work once for the cached tree and again
            // when SwiftUI synchronizes the current search state.
            guard !isActive else { return }

            firstResponderSynchronizationGeneration &+= 1
            isKeyboardReadinessActive = false
            cancelKeyboardReadinessObservation()
            if let window = textView.window,
               window.firstResponder === textView
            {
                _ = window.makeFirstResponder(nil)
            }
            publishKeyboardReadiness(false)
        }

        func synchronize(
            textView: NSTextView,
            query: String,
            cursorPosition: Int,
            isSearchActive: Bool,
            showsInsertionPoint: Bool
        ) {
            let resolvedCursorPosition = min(max(cursorPosition, 0), query.count)
            let selectedRange = NSRange(location: resolvedCursorPosition, length: 0)
            let shouldPreserveSelection = textView.string == query && textView.selectedRange().length > 0
            isApplyingViewState = true
            if textView.string != query {
                textView.string = query
            }
            if !shouldPreserveSelection, textView.selectedRange() != selectedRange {
                textView.setSelectedRange(selectedRange)
            }
            let insertionPointColor: NSColor = showsInsertionPoint ? .controlAccentColor : .clear
            if textView.insertionPointColor != insertionPointColor {
                textView.insertionPointColor = insertionPointColor
            }
            isApplyingViewState = false

            ensureCursorIsVisible(for: textView)
            synchronizeFirstResponder(for: textView, isSearchActive: isSearchActive)
            publishMarkedTextState(for: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard trackedTextView === textView else { return }
            guard !isApplyingViewState else {
                publishMarkedTextState(for: textView)
                return
            }
            ensureCursorIsVisible(for: textView)
            publishInputState(for: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard trackedTextView === textView else { return }
            guard !isApplyingViewState else {
                publishMarkedTextState(for: textView)
                return
            }
            ensureCursorIsVisible(for: textView)
            publishInputState(for: textView)
        }

        private func publishInputState(for textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            guard selectedRange.length == 0 else {
                publishMarkedTextState(for: textView)
                return
            }
            let snapshot = InputSnapshot(
                query: textView.string,
                cursorPosition: selectedRange.location
            )
            if lastPublishedInputSnapshot != snapshot {
                lastPublishedInputSnapshot = snapshot
                Self.logSearchInput(
                    "publishInputState query=\(snapshot.query.debugDescription) cursor=\(snapshot.cursorPosition) hasMarked=\(textView.hasMarkedText() ? 1 : 0)"
                )
            }
            onInputChanged(textView.string, selectedRange.location)
            publishMarkedTextState(for: textView)
        }

        private func publishMarkedTextState(for textView: NSTextView) {
            let hasMarkedText = textView.hasMarkedText()
            if lastPublishedMarkedTextState != hasMarkedText {
                lastPublishedMarkedTextState = hasMarkedText
                Self.logSearchInput(
                    "publishMarkedTextState hasMarked=\(hasMarkedText ? 1 : 0) query=\(textView.string.debugDescription)"
                )
            }
            onMarkedTextChanged(hasMarkedText)
        }

        private func ensureCursorIsVisible(for textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            guard selectedRange.length == 0 else { return }
            textView.scrollRangeToVisible(selectedRange)
        }

        private func synchronizeFirstResponder(for textView: NSTextView, isSearchActive: Bool) {
            firstResponderSynchronizationGeneration &+= 1
            let generation =
                firstResponderSynchronizationGeneration
            isKeyboardReadinessActive = isSearchActive
            if isSearchActive {
                DispatchQueue.main.async {
                    [weak self, weak textView] in
                    guard let self, let textView else { return }
                    guard
                        self.firstResponderSynchronizationGeneration
                            == generation,
                        self.isKeyboardReadinessActive,
                        self.trackedTextView === textView
                    else {
                        return
                    }
                    guard let window = textView.window else {
                        Self.logSearchInput("syncFirstResponder active=1 skipped=noWindow")
                        self.cancelKeyboardReadinessObservation()
                        self.publishKeyboardReadiness(false)
                        return
                    }
                    self.observeKeyboardReadiness(
                        for: textView,
                        in: window
                    )
                    self.synchronizeExactFirstResponder(
                        for: textView,
                        in: window
                    )
                }
            } else {
                cancelKeyboardReadinessObservation()
                publishKeyboardReadiness(false)
                DispatchQueue.main.async {
                    [weak self, weak textView] in
                    guard let self, let textView else { return }
                    guard
                        self.firstResponderSynchronizationGeneration
                            == generation,
                        !self.isKeyboardReadinessActive,
                        self.trackedTextView === textView
                    else {
                        return
                    }
                    guard let window = textView.window else {
                        Self.logSearchInput("syncFirstResponder active=0 skipped=noWindow")
                        return
                    }
                    guard window.firstResponder === textView else {
                        return
                    }
                    let before = Self.responderName(window.firstResponder)
                    let clearedFirstResponder = window.makeFirstResponder(nil)
                    let after = Self.responderName(window.firstResponder)
                    Self.logSearchInput(
                        "syncFirstResponder active=0 result=\(clearedFirstResponder ? 1 : 0) windowKey=\(window.isKeyWindow ? 1 : 0) appActive=\(NSApp.isActive ? 1 : 0) before=\(before) after=\(after)"
                    )
                }
            }
        }

        private func observeKeyboardReadiness(
            for textView: NSTextView,
            in window: NSWindow
        ) {
            if keyboardReadinessWindow === window,
               !keyboardReadinessObservers.isEmpty
            {
                return
            }
            cancelKeyboardReadinessObservation()
            keyboardReadinessWindow = window
            let center =
                keyboardReadinessNotificationCenter
            keyboardReadinessObservers = [
                center.addObserver(
                    forName:
                        NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) {
                    [weak self, weak textView, weak window] _ in
                    guard
                        let self,
                        let textView,
                        let window,
                        self.isKeyboardReadinessActive,
                        self.trackedTextView === textView,
                        self.keyboardReadinessWindow === window
                    else {
                        return
                    }
                    self.handleKeyboardReadinessWindowBecameKey(
                        for: textView,
                        in: window
                    )
                },
                center.addObserver(
                    forName:
                        NSWindow.didResignKeyNotification,
                    object: window,
                    queue: .main
                ) {
                    [weak self, weak textView, weak window] _ in
                    guard
                        let self,
                        let textView,
                        let window,
                        self.isKeyboardReadinessActive,
                        self.trackedTextView === textView,
                        self.keyboardReadinessWindow === window
                    else {
                        return
                    }
                    self.publishKeyboardReadiness(false)
                }
            ]
        }

        private func cancelKeyboardReadinessObservation() {
            let center =
                keyboardReadinessNotificationCenter
            keyboardReadinessObservers.forEach {
                center.removeObserver($0)
            }
            keyboardReadinessObservers.removeAll()
            keyboardReadinessWindow = nil
        }

        private func handleKeyboardReadinessWindowBecameKey(
            for textView: NSTextView,
            in window: NSWindow
        ) {
            let generation =
                firstResponderSynchronizationGeneration
            DispatchQueue.main.async {
                [weak self, weak textView, weak window] in
                guard
                    let self,
                    let textView,
                    let window,
                    self.firstResponderSynchronizationGeneration
                        == generation,
                    self.isKeyboardReadinessActive,
                    self.trackedTextView === textView,
                    self.keyboardReadinessWindow === window
                else {
                    return
                }
                self.synchronizeExactFirstResponder(
                    for: textView,
                    in: window
                )
            }
        }

        private func synchronizeExactFirstResponder(
            for textView: NSTextView,
            in window: NSWindow
        ) {
            if window.firstResponder === textView {
                Self.logSearchInput(
                    "syncFirstResponder active=1 skipped=alreadyFirstResponder windowKey=\(window.isKeyWindow ? 1 : 0) appActive=\(NSApp.isActive ? 1 : 0)"
                )
                _ = publishKeyboardReadiness(
                    for: textView,
                    in: window
                )
                return
            }
            let before =
                Self.responderName(window.firstResponder)
            let didBecomeFirstResponder =
                window.makeFirstResponder(textView)
            let after =
                Self.responderName(window.firstResponder)
            Self.logSearchInput(
                "syncFirstResponder active=1 result=\(didBecomeFirstResponder ? 1 : 0) windowKey=\(window.isKeyWindow ? 1 : 0) appActive=\(NSApp.isActive ? 1 : 0) before=\(before) after=\(after)"
            )
            _ = publishKeyboardReadiness(
                for: textView,
                in: window
            )
        }

        @discardableResult
        private func publishKeyboardReadiness(
            for textView: NSTextView,
            in window: NSWindow
        ) -> Bool {
            let isReady =
                window.isKeyWindow
                    && window.firstResponder === textView
            let didChange =
                publishKeyboardReadiness(isReady)
            guard isReady, didChange else {
                return isReady
            }
            let identifier =
                textView.accessibilityIdentifier()
                    ?? "unavailable"
            RuntimeLog.info(
                .searchInput,
                "keyboardReadiness ready=1 "
                    + "identifier=\(identifier) "
                    + "responder="
                    + "\(Self.responderName(window.firstResponder)) "
                    + "windowKey=1"
            )
            return true
        }

        @discardableResult
        private func publishKeyboardReadiness(
            _ isReady: Bool
        ) -> Bool {
            guard
                lastPublishedKeyboardReadiness
                    != isReady
            else {
                return false
            }
            lastPublishedKeyboardReadiness = isReady
            onKeyboardReadinessChanged(isReady)
            return true
        }

        private static func logSearchInput(_ message: String) {
            RuntimeLog.debug(.searchInput, message)
        }

        private static func responderName(_ responder: NSResponder?) -> String {
            guard let responder else { return "nil" }
            return String(describing: type(of: responder))
        }

        deinit {
            cancelKeyboardReadinessObservation()
        }
    }
}

@MainActor
protocol SwitcherOverlayPresentationSessionLifecycleHandling: AnyObject {
    func switcherOverlayPresentationSessionActivityDidChange(
        _ isActive: Bool
    )
}

extension NSView {
    func updateSwitcherOverlayPresentationSessionActivity(
        _ isActive: Bool
    ) {
        if let handler = self as?
            SwitcherOverlayPresentationSessionLifecycleHandling
        {
            handler.switcherOverlayPresentationSessionActivityDidChange(
                isActive
            )
        }
        subviews.forEach {
            $0.updateSwitcherOverlayPresentationSessionActivity(isActive)
        }
    }
}

final class SearchSystemTextInputContainerView:
    NSView,
    SwitcherOverlayPresentationSessionLifecycleHandling
{
    let textView: SearchSystemTextView
    let scrollView: NSScrollView
    var onWindowChanged: ((NSWindow?) -> Void)?
    var onPresentationSessionActivityChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = true
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 1
        textContainer.lineBreakMode = .byClipping
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        textView = SearchSystemTextView(frame: .zero, textContainer: textContainer)
        scrollView = NSScrollView(frame: .zero)
        super.init(frame: frameRect)
        setAccessibilityIdentifier("flowtab.switcher.search.input")
        textView.setAccessibilityIdentifier("flowtab.switcher.search.input")

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none

        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = false
        textView.autoresizingMask = [.height]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = true

        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.font = .systemFont(ofSize: 20, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.textContainerInset = .zero
        scrollView.documentView = textView

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(window)
    }

    func switcherOverlayPresentationSessionActivityDidChange(
        _ isActive: Bool
    ) {
        onPresentationSessionActivityChanged?(isActive)
    }
}

final class SearchSystemTextView: NSTextView {
    override var acceptsFirstResponder: Bool {
        true
    }
}

#if DEBUG
@MainActor
private final class SearchSystemTextInputBridgeTestWindow:
    NSWindow
{
    var reportsKeyWindow = false
    private weak var reportedFirstResponder: NSResponder?

    override var isKeyWindow: Bool {
        reportsKeyWindow
    }

    override var firstResponder: NSResponder? {
        reportedFirstResponder
    }

    override func makeFirstResponder(
        _ responder: NSResponder?
    ) -> Bool {
        reportedFirstResponder = responder
        return true
    }
}

@MainActor
final class SearchSystemTextInputBridgeTestHarness {
    struct InputChange: Equatable {
        let query: String
        let cursorPosition: Int
    }

    private let containerView =
        SearchSystemTextInputContainerView()
    private let keyboardReadinessNotificationCenter =
        NotificationCenter()
    private lazy var coordinator =
        SearchSystemTextInputBridge.Coordinator(
            onInputChanged: { _, _ in },
            onMarkedTextChanged: { _ in },
            onKeyboardReadinessChanged: {
                [weak self] isReady in
                self?.keyboardReadinessChanges
                    .append(isReady)
                self?.onKeyboardReadinessChanged?(
                    isReady
                )
            },
            keyboardReadinessNotificationCenter:
                keyboardReadinessNotificationCenter
        )
    private var hostingWindow:
        SearchSystemTextInputBridgeTestWindow?
    private var onKeyboardReadinessChanged:
        ((Bool) -> Void)?

    private(set) var inputChanges: [InputChange] = []
    private(set) var markedTextChanges: [Bool] = []
    private(set) var keyboardReadinessChanges: [Bool] = []

    init() {
        containerView.textView.delegate = coordinator
        coordinator.attach(textView: containerView.textView)
        coordinator.updateCallbacks(
            onInputChanged: { [weak self] query, cursorPosition in
                self?.inputChanges.append(
                    InputChange(query: query, cursorPosition: cursorPosition)
                )
            },
            onMarkedTextChanged: { [weak self] hasMarkedText in
                self?.markedTextChanges.append(hasMarkedText)
            }
        )
    }

    var textView: NSTextView {
        containerView.textView
    }

    var containerAccessibilityIdentifier: String? {
        containerView.accessibilityIdentifier()
    }

    var enclosingScrollView: NSScrollView? {
        containerView.textView.enclosingScrollView
    }

    var hasKeyboardReadinessTestObserver: Bool {
        onKeyboardReadinessChanged != nil
    }

    func installInKeyWindow() -> NSWindow {
        installInWindow(makeKey: true)
    }

    func installInWindow(
        makeKey: Bool = false
    ) -> NSWindow {
        let window =
            SearchSystemTextInputBridgeTestWindow(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: 320,
                    height: 80
                ),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
        window.contentView = containerView
        window.reportsKeyWindow = makeKey
        hostingWindow = window
        return window
    }

    func makeHostingWindowKey() {
        guard let hostingWindow else { return }
        hostingWindow.reportsKeyWindow = true
        keyboardReadinessNotificationCenter.post(
            name: NSWindow.didBecomeKeyNotification,
            object: hostingWindow
        )
    }

    func postHostingWindowDidBecomeKey() {
        guard let hostingWindow else { return }
        keyboardReadinessNotificationCenter.post(
            name: NSWindow.didBecomeKeyNotification,
            object: hostingWindow
        )
    }

    func observeKeyboardReadiness(
        _ observer: @escaping (Bool) -> Void
    ) {
        onKeyboardReadinessChanged = observer
    }

    func closeHostingWindow() {
        onKeyboardReadinessChanged = nil
        coordinator.detach(textView: containerView.textView)
        if hostingWindow?.firstResponder
            === containerView.textView
        {
            _ = hostingWindow?.makeFirstResponder(nil)
        }
        hostingWindow?.reportsKeyWindow = false
        containerView.textView.delegate = nil
        hostingWindow?.contentView = nil
        hostingWindow = nil
    }

    func synchronize(
        query: String,
        cursorPosition: Int,
        isSearchActive: Bool = false,
        showsInsertionPoint: Bool = true
    ) {
        coordinator.synchronize(
            textView: containerView.textView,
            query: query,
            cursorPosition: cursorPosition,
            isSearchActive: isSearchActive,
            showsInsertionPoint: showsInsertionPoint
        )
    }

    func updatePresentationSessionActivity(_ isActive: Bool) {
        coordinator.updatePresentationSessionActivity(
            isActive,
            for: containerView.textView
        )
    }

    func notifyTextDidChange(for textView: NSTextView? = nil) {
        let target = textView ?? containerView.textView
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: target))
    }

    func notifySelectionDidChange(for textView: NSTextView? = nil) {
        let target = textView ?? containerView.textView
        coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: target)
        )
    }

    func resetRecordedChanges() {
        inputChanges.removeAll()
        markedTextChanges.removeAll()
        keyboardReadinessChanges.removeAll()
    }

    func detachTrackedTextView() {
        coordinator.detach(textView: containerView.textView)
    }
}
#endif
