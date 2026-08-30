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
    private var wasActive = false
    private var pendingInitialFocusClear = false
    private var contentRefreshGate = AppKitSettingsPageContentRefreshGate()
    private var layoutMeasurementCache =
        AppKitSettingsPageLayoutMeasurementCache()
    private var appliedAppearanceName: NSAppearance.Name?
    private var appliedLayoutSignature:
        AppKitSettingsPageLayoutSignature?
    private var pendingState: AppKitSettingsPageState?
    private var isApplyingState = false
    private var hasPendingContentLayout = false
    private var hasDeferredLayoutRefresh = false
    private var hasEstablishedInitialScrollPosition = false
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
        guard isActive else { return }
        applyPendingStateIfNeeded()
        applyPendingContentLayoutIfNeeded()
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
        isApplyingState = true
        pageView.update(with: state)
        isApplyingState = false
        markContentLayoutDirty()
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
        let viewportSize = bounds.size
        guard viewportSize.width > 0 else { return }

        let signature = currentLayoutSignature(
            viewportSize: viewportSize
        )
        guard appliedLayoutSignature != signature else { return }
        if layoutMeasurementCache.fittedSize(for: signature) != nil {
            appliedLayoutSignature = signature
            return
        }

        super.layout()

        let safeArea = signature.safeAreaInsets
        let pageWidth = max(
            viewportSize.width
                - safeArea.left
                - safeArea.right
                - horizontalContentInset * 2,
            320
        )
        let leadingInset = horizontalContentInset + safeArea.left
        let topInset = verticalContentInset + safeArea.top
        if pageHeightConstraint?.isActive != true {
            let provisionalHeight = max(
                viewportSize.height
                    - topInset
                    - verticalContentInset
                    - safeArea.bottom,
                1
            )
            applyLayoutGeometry(
                viewportWidth: viewportSize.width,
                leadingInset: leadingInset,
                pageWidth: pageWidth,
                topInset: topInset,
                bottomSafeAreaInset: safeArea.bottom,
                fittedSize: CGSize(
                    width: pageWidth,
                    height: provisionalHeight
                )
            )
        }
        pageView.prepareLayout(forWidth: pageWidth)
        let measuredSize = pageView.preferredFittingSize(
            forWidth: pageWidth
        )
        applyLayoutGeometry(
            viewportWidth: viewportSize.width,
            leadingInset: leadingInset,
            pageWidth: pageWidth,
            topInset: topInset,
            bottomSafeAreaInset: safeArea.bottom,
            fittedSize: measuredSize
        )
        establishInitialScrollPositionIfNeeded()
        scrollView.needsLayout = true
        scrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()
        layoutMeasurementCache.store(
            fittedSize: measuredSize,
            for: signature
        )
        appliedLayoutSignature = signature
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
        pageView.onContentLayoutInvalidated = { [weak self] in
            guard let self, !self.isApplyingState else { return }
            self.invalidateContentLayout()
        }
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
        leadingInset: CGFloat,
        pageWidth: CGFloat,
        topInset: CGFloat,
        bottomSafeAreaInset: CGFloat,
        fittedSize: CGSize
    ) {
        let documentHeight =
            fittedSize.height
                + topInset
                + verticalContentInset
                + bottomSafeAreaInset
        let targetDocumentFrame = NSRect(
            x: 0,
            y: 0,
            width: viewportWidth,
            height: documentHeight
        )
        if documentView.frame != targetDocumentFrame {
            documentView.frame = targetDocumentFrame
        }
        update(pageLeadingConstraint, constant: leadingInset)
        update(pageTopConstraint, constant: topInset)
        update(pageWidthConstraint, constant: pageWidth)
        update(pageHeightConstraint, constant: fittedSize.height)
        if pageHeightConstraint?.isActive == false {
            pageHeightConstraint?.isActive = true
        }
        documentView.layoutSubtreeIfNeeded()
    }

    private func update(
        _ constraint: NSLayoutConstraint?,
        constant: CGFloat
    ) {
        guard let constraint,
              abs(constraint.constant - constant) > 0.5
        else {
            return
        }
        constraint.constant = constant
    }

    private func establishInitialScrollPositionIfNeeded() {
        guard !hasEstablishedInitialScrollPosition else { return }
        hasEstablishedInitialScrollPosition = true
        scrollView.contentView.setBoundsOrigin(.zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
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

    func invalidateContentLayout() {
        contentRefreshGate.invalidateContent()
        pageView.invalidateMeasuredContentHeight()
        markContentLayoutDirty()
        applyPendingContentLayoutIfNeeded()
    }

    private func markContentLayoutDirty() {
        layoutMeasurementCache.invalidate()
        appliedLayoutSignature = nil
        hasPendingContentLayout = true
    }

    private func applyPendingContentLayoutIfNeeded() {
        guard wasActive, hasPendingContentLayout else { return }
        hasPendingContentLayout = false
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

    private func currentLayoutSignature(
        viewportSize: CGSize
    ) -> AppKitSettingsPageLayoutSignature {
        AppKitSettingsPageLayoutSignature(
            viewportSize: viewportSize,
            safeAreaInsets: AppKitSettingsPageSafeAreaInsets(
                safeAreaInsets
            ),
            layoutDirection: userInterfaceLayoutDirection,
            backingScale: resolvedBackingScale,
            effectiveAppearanceName: effectiveAppearance.name,
            contentRevision: contentRefreshGate.contentRevision
        )
    }

    private var resolvedBackingScale: CGFloat {
        let scale = window?.backingScaleFactor
            ?? window?.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1
        return scale.isFinite && scale > 0 ? scale : 1
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }
}
