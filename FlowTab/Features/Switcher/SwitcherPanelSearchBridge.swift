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
        coordinator.detach(textView: nsView.textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private struct InputSnapshot: Equatable {
            let query: String
            let cursorPosition: Int
        }

        private var onInputChanged: (String, Int) -> Void
        private var onMarkedTextChanged: (Bool) -> Void
        private var isApplyingViewState = false
        private weak var trackedTextView: NSTextView?
        private var lastPublishedInputSnapshot: InputSnapshot?
        private var lastPublishedMarkedTextState: Bool?

        init(
            onInputChanged: @escaping (String, Int) -> Void,
            onMarkedTextChanged: @escaping (Bool) -> Void
        ) {
            self.onInputChanged = onInputChanged
            self.onMarkedTextChanged = onMarkedTextChanged
        }

        func attach(textView: NSTextView) {
            trackedTextView = textView
        }

        func detach(textView: NSTextView) {
            guard trackedTextView === textView else { return }
            trackedTextView = nil
            onMarkedTextChanged(false)
        }

        func updateCallbacks(
            onInputChanged: @escaping (String, Int) -> Void,
            onMarkedTextChanged: @escaping (Bool) -> Void
        ) {
            self.onInputChanged = onInputChanged
            self.onMarkedTextChanged = onMarkedTextChanged
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
            if isSearchActive {
                DispatchQueue.main.async { [weak textView] in
                    guard let textView else { return }
                    guard let window = textView.window else {
                        Self.logSearchInput("syncFirstResponder active=1 skipped=noWindow")
                        return
                    }
                    if window.firstResponder === textView {
                        Self.logSearchInput(
                            "syncFirstResponder active=1 skipped=alreadyFirstResponder windowKey=\(window.isKeyWindow ? 1 : 0) appActive=\(NSApp.isActive ? 1 : 0)"
                        )
                        return
                    }
                    let before = Self.responderName(window.firstResponder)
                    let didBecomeFirstResponder = window.makeFirstResponder(textView)
                    let after = Self.responderName(window.firstResponder)
                    Self.logSearchInput(
                        "syncFirstResponder active=1 result=\(didBecomeFirstResponder ? 1 : 0) windowKey=\(window.isKeyWindow ? 1 : 0) appActive=\(NSApp.isActive ? 1 : 0) before=\(before) after=\(after)"
                    )
                }
            } else {
                DispatchQueue.main.async { [weak textView] in
                    guard let textView else { return }
                    guard let window = textView.window else {
                        Self.logSearchInput("syncFirstResponder active=0 skipped=noWindow")
                        return
                    }
                    guard window.firstResponder === textView else { return }
                    let before = Self.responderName(window.firstResponder)
                    let clearedFirstResponder = window.makeFirstResponder(nil)
                    let after = Self.responderName(window.firstResponder)
                    Self.logSearchInput(
                        "syncFirstResponder active=0 result=\(clearedFirstResponder ? 1 : 0) windowKey=\(window.isKeyWindow ? 1 : 0) appActive=\(NSApp.isActive ? 1 : 0) before=\(before) after=\(after)"
                    )
                }
            }
        }

        private static func logSearchInput(_ message: String) {
            RuntimeLog.debug(.searchInput, message)
        }

        private static func responderName(_ responder: NSResponder?) -> String {
            guard let responder else { return "nil" }
            return String(describing: type(of: responder))
        }
    }
}

final class SearchSystemTextInputContainerView: NSView {
    let textView: SearchSystemTextView
    let scrollView: NSScrollView

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
}

final class SearchSystemTextView: NSTextView {
    override var acceptsFirstResponder: Bool {
        true
    }
}

#if DEBUG
@MainActor
final class SearchSystemTextInputBridgeTestHarness {
    struct InputChange: Equatable {
        let query: String
        let cursorPosition: Int
    }

    private let containerView = SearchSystemTextInputContainerView()
    private let coordinator = SearchSystemTextInputBridge.Coordinator(
        onInputChanged: { _, _ in },
        onMarkedTextChanged: { _ in }
    )

    private(set) var inputChanges: [InputChange] = []
    private(set) var markedTextChanges: [Bool] = []

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
    }

    func detachTrackedTextView() {
        coordinator.detach(textView: containerView.textView)
    }
}
#endif
