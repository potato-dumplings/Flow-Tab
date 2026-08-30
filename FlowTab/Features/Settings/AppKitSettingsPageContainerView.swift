import AppKit

final class AppKitFlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class AppKitSettingsPageContainerView: NSView {
    let pageView = AppKitSettingsPageView()

    private let scrollView = NSScrollView()
    private let documentView = AppKitFlippedDocumentView()
    private let horizontalContentInset = FlowPageLayout.horizontalInset
    private let verticalContentInset = FlowPageLayout.alignedTopInset
    private let maximumLayoutSettlingPasses = 3
    private var wasActive = false
    private var pendingInitialFocusClear = false
    private var contentRefreshGate = AppKitSettingsPageContentRefreshGate()
    private var layoutMeasurementCache =
        AppKitSettingsPageLayoutMeasurementCache()
    private var appliedAppearanceName: NSAppearance.Name?
    private var pendingState: AppKitSettingsPageState?
    private var activationRefreshGeneration: UInt64 = 0
    private var scheduledActivationRefreshGeneration: UInt64?
    private var hasDeferredLayoutRefresh = false
    private var pageLeadingConstraint: NSLayoutConstraint?
    private var pageTopConstraint: NSLayoutConstraint?
    private var pageWidthConstraint: NSLayoutConstraint?
    private var pageHeightConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    func update(with state: AppKitSettingsPageState, isActive: Bool) {
        let becameActive = isActive && !wasActive
        wasActive = isActive
        pendingState = state
        if becameActive {
            clearInitialFirstResponderIfNeeded()
        }

        guard contentRefreshGate.hasAppliedState else {
            applyPendingStateIfNeeded()
            return
        }
        guard isActive else {
            cancelScheduledActivationRefresh()
            return
        }
        if becameActive {
            scheduleActivationRefresh()
            return
        }
        guard !hasScheduledActivationRefresh else { return }
        applyPendingStateIfNeeded()
    }

    private var hasScheduledActivationRefresh: Bool {
        scheduledActivationRefreshGeneration != nil
    }

    private func applyPendingStateIfNeeded() {
        guard let state = pendingState,
              contentRefreshGate.consume(state)
        else {
            return
        }

        let targetAppearance = FlowSettingsStyleResolver.targetAppearance(
            named: state.targetNSAppearanceName,
            fallback: inheritedAppearanceFallback
        )
        applyAppearanceIfNeeded(targetAppearance)
        pageView.update(with: state)
        refreshLayoutAfterSettingsUpdate()
    }

    private func scheduleActivationRefresh() {
        guard !hasScheduledActivationRefresh else { return }
        activationRefreshGeneration &+= 1
        let generation = activationRefreshGeneration
        scheduledActivationRefreshGeneration = generation

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.scheduledActivationRefreshGeneration == generation
            else {
                return
            }
            self.scheduledActivationRefreshGeneration = nil
            guard self.wasActive else { return }
            self.applyPendingStateIfNeeded()
        }
    }

    private func cancelScheduledActivationRefresh() {
        activationRefreshGeneration &+= 1
        scheduledActivationRefreshGeneration = nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        let previousSize = frame.size
        super.setFrameSize(newSize)
        if previousSize != newSize {
            needsLayout = true
        }
    }

    override func setBoundsSize(_ newSize: NSSize) {
        let previousSize = bounds.size
        super.setBoundsSize(newSize)
        if previousSize != newSize {
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()

        let viewportSize = bounds.size
        guard viewportSize.width > 0 else { return }

        let pageWidth = max(
            viewportSize.width - horizontalContentInset * 2,
            320
        )
        let topInset = verticalContentInset + safeAreaInsets.top
        pageLeadingConstraint?.constant = horizontalContentInset
        pageTopConstraint?.constant = topInset
        pageWidthConstraint?.constant = pageWidth
        let signature = AppKitSettingsPageLayoutSignature(
            viewportSize: viewportSize,
            safeAreaTop: safeAreaInsets.top,
            contentRevision: contentRefreshGate.contentRevision
        )
        if let fittedSize = layoutMeasurementCache.fittedSize(
            for: signature
        ) {
            applyLayoutGeometry(
                viewportWidth: viewportSize.width,
                pageWidth: pageWidth,
                topInset: topInset,
                fittedSize: fittedSize,
                settlesDocumentLayout: false
            )
            return
        }

        var previousHeight: CGFloat?
        var measuredSize = CGSize(width: pageWidth, height: 0)
        for _ in 0..<maximumLayoutSettlingPasses {
            pageHeightConstraint?.isActive = false
            pageView.prepareLayout(forWidth: pageWidth)
            measuredSize = pageView.preferredFittingSize(
                forWidth: pageWidth
            )
            applyLayoutGeometry(
                viewportWidth: viewportSize.width,
                pageWidth: pageWidth,
                topInset: topInset,
                fittedSize: measuredSize,
                settlesDocumentLayout: true
            )

            if let previousHeight,
               abs(previousHeight - measuredSize.height) <= 0.5
            {
                break
            }
            previousHeight = measuredSize.height
        }
        layoutMeasurementCache.store(
            fittedSize: measuredSize,
            for: signature
        )
    }

    private func buildViewHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        documentView.translatesAutoresizingMaskIntoConstraints = true
        pageView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(pageView)
        scrollView.documentView = documentView

        addSubview(scrollView)

        let pageLeadingConstraint = pageView.leadingAnchor.constraint(
            equalTo: documentView.leadingAnchor,
            constant: horizontalContentInset
        )
        let pageTopConstraint = pageView.topAnchor.constraint(
            equalTo: documentView.topAnchor,
            constant: verticalContentInset
        )
        let pageWidthConstraint = pageView.widthAnchor.constraint(
            equalToConstant: 320
        )
        let pageHeightConstraint = pageView.heightAnchor.constraint(
            equalToConstant: 1
        )
        self.pageLeadingConstraint = pageLeadingConstraint
        self.pageTopConstraint = pageTopConstraint
        self.pageWidthConstraint = pageWidthConstraint
        self.pageHeightConstraint = pageHeightConstraint

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            pageLeadingConstraint,
            pageTopConstraint,
            pageWidthConstraint
        ])
    }

    private func applyLayoutGeometry(
        viewportWidth: CGFloat,
        pageWidth: CGFloat,
        topInset: CGFloat,
        fittedSize: CGSize,
        settlesDocumentLayout: Bool
    ) {
        let documentHeight =
            fittedSize.height + topInset + verticalContentInset
        let targetDocumentFrame = NSRect(
            x: 0,
            y: 0,
            width: viewportWidth,
            height: documentHeight
        )
        if documentView.frame != targetDocumentFrame {
            documentView.frame = targetDocumentFrame
        }
        pageLeadingConstraint?.constant = horizontalContentInset
        pageTopConstraint?.constant = topInset
        pageWidthConstraint?.constant = pageWidth
        pageHeightConstraint?.constant = fittedSize.height
        pageHeightConstraint?.isActive = true
        if settlesDocumentLayout {
            documentView.layoutSubtreeIfNeeded()
        }
    }

    private func applyAppearanceIfNeeded(_ targetAppearance: NSAppearance) {
        guard appliedAppearanceName != targetAppearance.name else { return }
        appliedAppearanceName = targetAppearance.name
        if appearance?.name != targetAppearance.name {
            appearance = targetAppearance
        }
        if scrollView.appearance?.name != targetAppearance.name {
            scrollView.appearance = targetAppearance
        }
        if documentView.appearance?.name != targetAppearance.name {
            documentView.appearance = targetAppearance
        }
        pageView.applySettingsAppearance(targetAppearance)
    }

    private func clearInitialFirstResponderIfNeeded() {
        guard !pendingInitialFocusClear else { return }
        pendingInitialFocusClear = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingInitialFocusClear = false
            self.resignPageFirstResponderIfNeeded()
        }
    }

    private func resignPageFirstResponderIfNeeded() {
        guard let window else { return }

        if let view = window.firstResponder as? NSView,
           view.isDescendant(of: pageView)
        {
            window.makeFirstResponder(nil)
            return
        }

        if let editor = window.firstResponder as? NSTextView,
           let editedView = editor.delegate as? NSView,
           editedView.isDescendant(of: pageView)
        {
            window.makeFirstResponder(nil)
        }
    }

    private func refreshLayoutAfterSettingsUpdate() {
        layoutMeasurementCache.invalidate()
        pageView.invalidateMeasuredContentHeight()
        pageView.needsLayout = true
        documentView.needsLayout = true
        needsLayout = true
        scheduleDeferredLayoutRefresh()
    }

    private func scheduleDeferredLayoutRefresh() {
        guard !hasDeferredLayoutRefresh else { return }
        hasDeferredLayoutRefresh = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasDeferredLayoutRefresh = false
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
        }
    }

    private var inheritedAppearanceFallback: NSAppearance {
        window?.effectiveAppearance
            ?? superview?.effectiveAppearance
            ?? NSApp.effectiveAppearance
    }
}
