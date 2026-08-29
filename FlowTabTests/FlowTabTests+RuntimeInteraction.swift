import AppKit
import SwiftUI
import XCTest
@testable import FlowTab
import FlowTabCore
import Carbon

private enum RuntimeInteractionWatchdogPolicy {
    static let keyboardReadinessEvent: TimeInterval = 1
    static let mainQueueTransition: TimeInterval = 1
}

extension FlowTabTests {
    func testRuntimeInteractionWatchdogPolicyPreservesKeyboardReadinessEventBound() {
        let keyboardReadinessEvent =
            RuntimeInteractionWatchdogPolicy.keyboardReadinessEvent

        XCTAssertEqual(keyboardReadinessEvent, 1)
        XCTAssertTrue(keyboardReadinessEvent.isFinite)
        XCTAssertGreaterThan(keyboardReadinessEvent, 0)
    }

    func testRuntimeInteractionWatchdogPolicyPreservesMainQueueTransitionBound() {
        let mainQueueTransition =
            RuntimeInteractionWatchdogPolicy.mainQueueTransition

        XCTAssertEqual(mainQueueTransition, 1)
        XCTAssertTrue(mainQueueTransition.isFinite)
        XCTAssertGreaterThan(mainQueueTransition, 0)
    }

    @MainActor
    func testSearchSystemTextInputBridgeConfiguresVisiblePlainTextResponder() {
        let harness = SearchSystemTextInputBridgeTestHarness()
        let textView = harness.textView
        let scrollView = harness.enclosingScrollView

        XCTAssertEqual(harness.containerAccessibilityIdentifier, "flowtab.switcher.search.input")
        XCTAssertNotNil(scrollView)
        XCTAssertEqual(scrollView?.drawsBackground, false)
        XCTAssertEqual(scrollView?.hasHorizontalScroller, false)
        XCTAssertEqual(scrollView?.hasVerticalScroller, false)
        XCTAssertTrue(textView.acceptsFirstResponder)
        XCTAssertFalse(textView.drawsBackground)
        XCTAssertEqual(textView.backgroundColor, .clear)
        XCTAssertEqual(textView.textColor, .labelColor)
        XCTAssertEqual(textView.insertionPointColor, .controlAccentColor)
        XCTAssertTrue(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertFalse(textView.isRichText)
        XCTAssertFalse(textView.importsGraphics)
        XCTAssertFalse(textView.allowsUndo)
        XCTAssertFalse(textView.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticDataDetectionEnabled)
        XCTAssertFalse(textView.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticLinkDetectionEnabled)
        XCTAssertFalse(textView.isAutomaticSpellingCorrectionEnabled)
        XCTAssertFalse(textView.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(textView.isContinuousSpellCheckingEnabled)
        XCTAssertFalse(textView.isGrammarCheckingEnabled)
        XCTAssertEqual(textView.textContainerInset, .zero)
        XCTAssertTrue(textView.isHorizontallyResizable)
        XCTAssertFalse(textView.isVerticallyResizable)
        XCTAssertEqual(textView.textContainer?.lineFragmentPadding, 0)
        XCTAssertEqual(textView.textContainer?.maximumNumberOfLines, 1)
        XCTAssertEqual(textView.textContainer?.lineBreakMode, .byClipping)
        XCTAssertEqual(textView.textContainer?.widthTracksTextView, false)
        XCTAssertEqual(textView.textContainer?.heightTracksTextView, true)
    }

    @MainActor
    func testSearchSystemTextInputBridgePublishesExactKeyboardReadiness()
        async
    {
        let readiness =
            expectation(
                description:
                    "unmetCondition=exactSearchKeyboardReadiness callback"
            )
        let harness = SearchSystemTextInputBridgeTestHarness()
        harness.observeKeyboardReadiness { isReady in
            if isReady {
                readiness.fulfill()
            }
        }
        XCTAssertTrue(harness.hasKeyboardReadinessTestObserver)
        let window = harness.installInKeyWindow()
        defer {
            harness.closeHostingWindow()
            XCTAssertFalse(
                harness.hasKeyboardReadinessTestObserver
            )
        }

        XCTAssertTrue(harness.keyboardReadinessChanges.isEmpty)
        XCTAssertFalse(window.firstResponder === harness.textView)

        harness.synchronize(
            query: "",
            cursorPosition: 0,
            isSearchActive: true
        )

        await fulfillment(
            of: [readiness],
            timeout:
                RuntimeInteractionWatchdogPolicy
                    .keyboardReadinessEvent
        )
        let readinessEvidence =
            searchInputKeyboardReadinessEvidence(
                harness: harness,
                window: window
            )
        XCTAssertTrue(window.isKeyWindow, readinessEvidence)
        XCTAssertTrue(
            window.firstResponder === harness.textView,
            readinessEvidence
        )
        XCTAssertEqual(
            harness.textView.accessibilityIdentifier(),
            "flowtab.switcher.search.input"
        )
        XCTAssertEqual(
            harness.keyboardReadinessChanges,
            [true],
            readinessEvidence
        )

        harness.postHostingWindowDidBecomeKey()
        harness.postHostingWindowDidBecomeKey()
        await waitForSearchInputMainQueueTurn()
        XCTAssertEqual(
            harness.keyboardReadinessChanges,
            [true]
        )
    }

    @MainActor
    func testSearchSystemTextInputBridgeWaitsForKeyWindowEvidence()
        async
    {
        let readiness =
            expectation(
                description:
                    "unmetCondition=delayedKeyWindowKeyboardReadiness callback"
            )
        let harness = SearchSystemTextInputBridgeTestHarness()
        harness.observeKeyboardReadiness { isReady in
            if isReady {
                readiness.fulfill()
            }
        }
        XCTAssertTrue(harness.hasKeyboardReadinessTestObserver)
        let window = harness.installInWindow()
        defer {
            harness.closeHostingWindow()
            XCTAssertFalse(
                harness.hasKeyboardReadinessTestObserver
            )
        }

        XCTAssertTrue(harness.keyboardReadinessChanges.isEmpty)

        harness.synchronize(
            query: "",
            cursorPosition: 0,
            isSearchActive: true
        )
        await waitForSearchInputMainQueueTurn()

        XCTAssertFalse(window.isKeyWindow)
        XCTAssertTrue(
            harness.keyboardReadinessChanges.isEmpty
        )

        harness.makeHostingWindowKey()
        await fulfillment(
            of: [readiness],
            timeout:
                RuntimeInteractionWatchdogPolicy
                    .keyboardReadinessEvent
        )
        let readinessEvidence =
            searchInputKeyboardReadinessEvidence(
                harness: harness,
                window: window
            )

        XCTAssertTrue(window.isKeyWindow, readinessEvidence)
        XCTAssertTrue(
            window.firstResponder === harness.textView,
            readinessEvidence
        )
        XCTAssertEqual(
            harness.keyboardReadinessChanges,
            [true],
            readinessEvidence
        )
    }

    @MainActor
    func testSearchSystemTextInputBridgeCancelsStaleReadiness()
        async
    {
        let harness = SearchSystemTextInputBridgeTestHarness()
        let window = harness.installInWindow()
        defer { harness.closeHostingWindow() }

        harness.synchronize(
            query: "",
            cursorPosition: 0,
            isSearchActive: true
        )
        harness.synchronize(
            query: "",
            cursorPosition: 0,
            isSearchActive: false
        )
        await waitForSearchInputMainQueueTurn()

        harness.makeHostingWindowKey()
        await waitForSearchInputMainQueueTurn()

        XCTAssertTrue(window.isKeyWindow)
        XCTAssertFalse(
            window.firstResponder === harness.textView
        )
        XCTAssertFalse(
            harness.keyboardReadinessChanges.contains(true)
        )
    }

    @MainActor
    func testSearchSystemTextInputBridgeSuspendsReadinessWhenOverlayDeactivates()
        async
    {
        let harness = SearchSystemTextInputBridgeTestHarness()
        let window = harness.installInKeyWindow()
        defer { harness.closeHostingWindow() }

        harness.synchronize(
            query: "",
            cursorPosition: 0,
            isSearchActive: true
        )
        await waitForSearchInputMainQueueTurn()
        XCTAssertTrue(window.firstResponder === harness.textView)

        harness.updatePresentationSessionActivity(false)
        harness.postHostingWindowDidBecomeKey()
        await waitForSearchInputMainQueueTurn()

        XCTAssertFalse(window.firstResponder === harness.textView)
        XCTAssertEqual(harness.keyboardReadinessChanges, [true, false])

        harness.updatePresentationSessionActivity(true)
        await waitForSearchInputMainQueueTurn()

        XCTAssertFalse(window.firstResponder === harness.textView)
        XCTAssertEqual(harness.keyboardReadinessChanges, [true, false])

        harness.synchronize(
            query: "",
            cursorPosition: 0,
            isSearchActive: true
        )
        await waitForSearchInputMainQueueTurn()

        XCTAssertTrue(window.firstResponder === harness.textView)
        XCTAssertEqual(
            harness.keyboardReadinessChanges,
            [true, false, true]
        )
    }

    @MainActor
    func testSearchSystemTextInputBridgeSynchronizeClampsQueryAndCursor() {
        let harness = SearchSystemTextInputBridgeTestHarness()

        harness.synchronize(query: "wechat", cursorPosition: 99, showsInsertionPoint: true)

        XCTAssertEqual(harness.textView.string, "wechat")
        XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 6, length: 0))
        XCTAssertEqual(harness.textView.insertionPointColor, .controlAccentColor)
        XCTAssertTrue(harness.inputChanges.isEmpty)
        XCTAssertGreaterThanOrEqual(harness.markedTextChanges.count, 1)
        XCTAssertEqual(harness.markedTextChanges.last, false)

        harness.synchronize(query: "wechat", cursorPosition: -4, showsInsertionPoint: false)

        XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertEqual(harness.textView.insertionPointColor, .clear)
        XCTAssertEqual(harness.markedTextChanges.last, false)
    }

    @MainActor
    func testSearchSystemTextInputBridgePublishesQueryAndCursorFromTextInput() {
        let harness = SearchSystemTextInputBridgeTestHarness()
        harness.synchronize(query: "abc", cursorPosition: 3)
        harness.resetRecordedChanges()

        harness.textView.insertText("d", replacementRange: NSRange(location: 3, length: 0))
        harness.notifyTextDidChange()

        XCTAssertEqual(
            harness.inputChanges.last,
            SearchSystemTextInputBridgeTestHarness.InputChange(
                query: "abcd",
                cursorPosition: 4
            )
        )
        XCTAssertEqual(harness.markedTextChanges.last, false)

        harness.textView.setSelectedRange(NSRange(location: 2, length: 0))
        harness.notifySelectionDidChange()

        XCTAssertEqual(
            harness.inputChanges.last,
            SearchSystemTextInputBridgeTestHarness.InputChange(
                query: "abcd",
                cursorPosition: 2
            )
        )
    }

    @MainActor
    func testSearchSystemTextInputBridgePreservesSelectAllAndDoesNotPublishCollapsedCursor() {
        let harness = SearchSystemTextInputBridgeTestHarness()
        harness.synchronize(query: "abcdef", cursorPosition: 6)
        harness.resetRecordedChanges()

        harness.textView.setSelectedRange(NSRange(location: 0, length: 6))
        harness.notifySelectionDidChange()

        XCTAssertTrue(harness.inputChanges.isEmpty)
        XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 0, length: 6))

        harness.synchronize(query: "abcdef", cursorPosition: 6)

        XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 0, length: 6))
    }

    @MainActor
    func testSearchSystemTextInputBridgeTracksMarkedTextCompositionLifecycle() {
        let harness = SearchSystemTextInputBridgeTestHarness()
        harness.resetRecordedChanges()

        harness.textView.setMarkedText(
            "ni",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        harness.notifyTextDidChange()

        XCTAssertTrue(harness.textView.hasMarkedText())
        XCTAssertEqual(harness.inputChanges.last?.query, "ni")
        XCTAssertEqual(harness.markedTextChanges.last, true)

        harness.textView.unmarkText()
        harness.notifyTextDidChange()

        XCTAssertFalse(harness.textView.hasMarkedText())
        XCTAssertEqual(harness.inputChanges.last?.query, "ni")
        XCTAssertEqual(harness.markedTextChanges.last, false)
    }

    @MainActor
    func testSearchSystemTextInputBridgeDetachClearsMarkedStateAndIgnoresUntrackedViews() {
        let harness = SearchSystemTextInputBridgeTestHarness()
        let untrackedTextView = NSTextView()

        untrackedTextView.string = "ignored"
        untrackedTextView.setSelectedRange(NSRange(location: 7, length: 0))
        harness.notifyTextDidChange(for: untrackedTextView)
        harness.notifySelectionDidChange(for: untrackedTextView)

        XCTAssertTrue(harness.inputChanges.isEmpty)
        XCTAssertTrue(harness.markedTextChanges.isEmpty)

        harness.detachTrackedTextView()

        XCTAssertEqual(harness.markedTextChanges, [false])
    }

    @MainActor
    func testTerminateSelectedAppBehaviorKeepsAppUntilWorkspaceTerminationArrives() {
        let initialApps = terminateScenarioApps()
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: initialApps)
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        guard let terminatedAppID = model.session?.selectedApp.id else {
            XCTFail("Expected an active session before terminate flow")
            return
        }

        let appsAfterTermination = initialApps.filter { $0.id != terminatedAppID }

        let terminatedPID = pid_t(42_000)
        model.terminateRequestOverride = { _ in (sent: true, pid: terminatedPID) }

        var layoutRefreshCount = 0
        model.onSessionLayoutChanged = { layoutRefreshCount += 1 }
        defer {
            model.onSessionLayoutChanged = nil
            model.cancelSelection()
        }

        let result = model.terminateSelectedApp()
        XCTAssertEqual(result, .updatedSession)
        assertRuntimeProjectionSessionRead(
            from: runtimeProjectionService,
            maintenanceRequests: [.switcherSessionStarted, .appLifecycleRefresh]
        )
        XCTAssertEqual(model.appCount, initialApps.count)
        XCTAssertTrue(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? false)
        XCTAssertEqual(model.terminatingAppID, terminatedAppID)
        XCTAssertEqual(model.pendingTerminateRequest?.appID, terminatedAppID)
        XCTAssertEqual(model.pendingTerminateRequest?.pid, terminatedPID)
        XCTAssertTrue(runtimeProjectionService.appTerminationSignalsRecorded().isEmpty)
        XCTAssertEqual(layoutRefreshCount, 0)

        XCTAssertTrue(model.handleApplicationTerminated(appID: terminatedAppID, pid: terminatedPID))
        XCTAssertEqual(
            layoutRefreshCount,
            1,
            "unmetCondition=terminationLayoutPublished "
                + "finalLayoutRefreshCount=\(layoutRefreshCount)"
        )
        XCTAssertEqual(runtimeProjectionService.appTerminationSignalsRecorded().map(\.appID), [terminatedAppID])
        assertRuntimeProjectionSessionRead(
            from: runtimeProjectionService,
            minimumReadCount: 2,
            maintenanceRequests: [.switcherSessionStarted, .appLifecycleRefresh]
        )
        XCTAssertEqual(model.appCount, appsAfterTermination.count)
        XCTAssertFalse(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? true)
        XCTAssertNil(model.terminatingAppID)
        XCTAssertNil(model.pendingTerminateRequest)
    }

    @MainActor
    func testTerminateSelectedAppBehaviorDoesNotTreatSentQuitRequestAsTerminationFact() async {
        let initialApps = terminateScenarioApps()
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: initialApps)
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        guard let terminatedAppID = model.session?.selectedApp.id else {
            XCTFail("Expected an active session before terminate flow")
            return
        }

        model.terminateRequestOverride = { _ in (sent: true, pid: 42_010) }

        let result = model.terminateSelectedApp()
        XCTAssertEqual(result, .updatedSession)
        assertRuntimeProjectionSessionRead(
            from: runtimeProjectionService,
            maintenanceRequests: [.switcherSessionStarted, .appLifecycleRefresh]
        )
        XCTAssertTrue(runtimeProjectionService.appTerminationSignalsRecorded().isEmpty)
        XCTAssertEqual(model.appCount, initialApps.count)
        XCTAssertTrue(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? false)
        XCTAssertEqual(model.terminatingAppID, terminatedAppID)
        XCTAssertEqual(model.pendingTerminateRequest?.appID, terminatedAppID)
        model.cancelSelection()
    }

    @MainActor
    func testHandleApplicationTerminatedRefreshesFromRuntimeProjectionWithoutFullSnapshot() {
        let initialApps = terminateScenarioApps()
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: initialApps)
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        guard let terminatedAppID = model.session?.selectedApp.id else {
            XCTFail("Expected an active session before termination refresh")
            return
        }
        assertRuntimeProjectionSessionRead(from: runtimeProjectionService)

        let refreshedApps = initialApps.filter { $0.id != terminatedAppID }

        var layoutRefreshCount = 0
        model.onSessionLayoutChanged = { layoutRefreshCount += 1 }
        defer {
            model.onSessionLayoutChanged = nil
            model.cancelSelection()
        }

        XCTAssertTrue(model.handleApplicationTerminated(appID: terminatedAppID, pid: 42_012))
        XCTAssertEqual(
            layoutRefreshCount,
            1,
            "unmetCondition=terminationLayoutPublished "
                + "finalLayoutRefreshCount=\(layoutRefreshCount)"
        )
        assertRuntimeProjectionSessionRead(from: runtimeProjectionService, minimumReadCount: 2)
        XCTAssertEqual(
            runtimeProjectionService.appTerminationSignalsRecorded().map(\.appID),
            [terminatedAppID]
        )
        XCTAssertFalse(
            runtimeProjectionService.readCommittedSearchIndexForSearch().projection?.appEntries.contains {
                $0.appID == terminatedAppID
            } ?? true
        )
        XCTAssertEqual(runtimeProjectionService.committedSearchIndexReadCount(), 1)
        XCTAssertEqual(model.appCount, refreshedApps.count)
        XCTAssertFalse(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? true)
    }

    @MainActor
    func testTerminateSelectedAppUnitKeepsPendingRequestWithoutSurfaceTimeout() {
        let initialApps = terminateScenarioApps()
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: initialApps)
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        guard let terminatedAppID = model.session?.selectedApp.id else {
            XCTFail("Expected an active session before terminate flow")
            return
        }

        let terminatedPID = pid_t(42_001)
        model.terminateRequestOverride = { _ in
            (sent: true, pid: terminatedPID)
        }

        var layoutRefreshCount = 0
        model.onSessionLayoutChanged = { layoutRefreshCount += 1 }
        defer {
            model.onSessionLayoutChanged = nil
            model.cancelSelection()
        }

        let result = model.terminateSelectedApp()
        XCTAssertEqual(result, .updatedSession)
        assertRuntimeProjectionSessionRead(
            from: runtimeProjectionService,
            maintenanceRequests: [.switcherSessionStarted, .appLifecycleRefresh]
        )
        XCTAssertEqual(model.appCount, initialApps.count)
        XCTAssertTrue(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? false)
        XCTAssertEqual(model.terminatingAppID, terminatedAppID)

        XCTAssertEqual(
            layoutRefreshCount,
            0,
            "unmetCondition=layoutRefreshRequiresTerminationEvidence "
                + "finalLayoutRefreshCount=\(layoutRefreshCount)"
        )
        XCTAssertTrue(runtimeProjectionService.appTerminationSignalsRecorded().isEmpty)
        assertRuntimeProjectionSessionRead(
            from: runtimeProjectionService,
            maintenanceRequests: [.switcherSessionStarted, .appLifecycleRefresh]
        )
        XCTAssertEqual(model.appCount, initialApps.count)
        XCTAssertTrue(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? false)
        XCTAssertEqual(model.terminatingAppID, terminatedAppID)
        XCTAssertEqual(model.pendingTerminateRequest?.appID, terminatedAppID)
        XCTAssertEqual(model.pendingTerminateRequest?.pid, terminatedPID)
        XCTAssertEqual(model.pendingTerminateRequest?.generation, 1)
    }

    @MainActor
    func testTerminateSelectedAppUnitKeepsPendingInstanceWhenSameBundleDifferentPIDTerminates() async {
        let initialApps = terminateScenarioApps()
        let currentApp = NSRunningApplication.current
        let activePID = currentApp.processIdentifier
        let contextsByID = Dictionary(
            uniqueKeysWithValues: initialApps.map { app in
                (
                    app.id,
                    RuntimeAppContext(
                        appID: app.id,
                        runningApp: currentApp,
                        windowsByID: [:]
                    )
                )
            }
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherApps: initialApps,
            contextsByID: contextsByID
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        guard let terminatedAppID = model.session?.selectedApp.id else {
            XCTFail("Expected an active session before terminate flow")
            return
        }

        model.terminateRequestOverride = { _ in (sent: true, pid: activePID) }

        let result = model.terminateSelectedApp()
        XCTAssertEqual(result, .updatedSession)
        XCTAssertEqual(model.pendingTerminateRequest?.appID, terminatedAppID)
        XCTAssertEqual(model.pendingTerminateRequest?.pid, activePID)
        XCTAssertEqual(model.pendingTerminateRequest?.generation, 1)
        XCTAssertEqual(model.terminatingAppID, terminatedAppID)
        assertRuntimeProjectionSessionRead(
            from: runtimeProjectionService,
            maintenanceRequests: [.switcherSessionStarted, .appLifecycleRefresh]
        )

        XCTAssertTrue(model.handleApplicationTerminated(appID: terminatedAppID, pid: activePID + 1))

        XCTAssertEqual(runtimeProjectionService.appTerminationSignalsRecorded().map(\.appID), [terminatedAppID])
        assertRuntimeProjectionSessionRead(
            from: runtimeProjectionService,
            minimumReadCount: 2,
            maintenanceRequests: [.switcherSessionStarted, .appLifecycleRefresh]
        )
        XCTAssertEqual(model.pendingTerminateRequest?.appID, terminatedAppID)
        XCTAssertEqual(model.pendingTerminateRequest?.pid, activePID)
        XCTAssertEqual(model.pendingTerminateRequest?.generation, 1)
        XCTAssertEqual(model.terminatingAppID, terminatedAppID)
        XCTAssertTrue(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? false)
        model.cancelSelection()
    }

    @MainActor
    func testTerminateSelectedAppUnitRefreshesOnWorkspaceTerminateAfterPendingRequest() {
        let initialApps = terminateScenarioApps()
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: initialApps)
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        guard let terminatedAppID = model.session?.selectedApp.id else {
            XCTFail("Expected an active session before terminate flow")
            return
        }

        let appsAfterTermination = initialApps.filter { $0.id != terminatedAppID }

        model.terminateRequestOverride = { _ in (sent: true, pid: 42_002) }

        var layoutRefreshCount = 0
        model.onSessionLayoutChanged = {
            layoutRefreshCount += 1
        }
        defer {
            model.onSessionLayoutChanged = nil
            model.cancelSelection()
        }

        let result = model.terminateSelectedApp()
        XCTAssertEqual(result, .updatedSession)
        assertRuntimeProjectionSessionRead(
            from: runtimeProjectionService,
            maintenanceRequests: [.switcherSessionStarted, .appLifecycleRefresh]
        )
        XCTAssertEqual(model.appCount, initialApps.count)
        XCTAssertTrue(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? false)

        XCTAssertEqual(layoutRefreshCount, 0)
        XCTAssertTrue(runtimeProjectionService.appTerminationSignalsRecorded().isEmpty)
        assertRuntimeProjectionSessionRead(
            from: runtimeProjectionService,
            maintenanceRequests: [.switcherSessionStarted, .appLifecycleRefresh]
        )
        XCTAssertEqual(model.terminatingAppID, terminatedAppID)

        XCTAssertTrue(
            model.handleApplicationTerminated(
                appID: terminatedAppID,
                pid: 42_002
            )
        )
        XCTAssertEqual(
            layoutRefreshCount,
            1,
            "unmetCondition=terminationLayoutPublished "
                + "finalLayoutRefreshCount=\(layoutRefreshCount)"
        )
        XCTAssertEqual(runtimeProjectionService.appTerminationSignalsRecorded().map(\.appID), [terminatedAppID])
        assertRuntimeProjectionSessionRead(
            from: runtimeProjectionService,
            minimumReadCount: 2,
            maintenanceRequests: [.switcherSessionStarted, .appLifecycleRefresh]
        )
        XCTAssertEqual(model.appCount, appsAfterTermination.count)
        XCTAssertFalse(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? true)
    }

    private func assertRuntimeProjectionSessionRead(
        from runtimeProjectionService: RecordingRuntimeProjectionService,
        minimumReadCount: Int = 1,
        maintenanceRequests: [RuntimeProjectionMaintenanceReason] = [.switcherSessionStarted],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            runtimeProjectionService.appSwitcherProjectionReadCount(),
            minimumReadCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded(),
            maintenanceRequests,
            file: file,
            line: line
        )
    }

    @MainActor
    private func waitForSearchInputMainQueueTurn()
        async
    {
        var didDeliverMainQueueTurn = false
        let mainQueueTurn =
            expectation(
                description:
                    "unmetCondition=searchInputMainQueueTransition callback"
            )
        let mainQueueTurnWorkItem = DispatchWorkItem {
            didDeliverMainQueueTurn = true
            mainQueueTurn.fulfill()
        }
        defer { mainQueueTurnWorkItem.cancel() }
        DispatchQueue.main.async(execute: mainQueueTurnWorkItem)
        await fulfillment(
            of: [mainQueueTurn],
            timeout:
                RuntimeInteractionWatchdogPolicy
                    .mainQueueTransition
        )
        XCTAssertTrue(
            didDeliverMainQueueTurn,
            "unmetCondition=searchInputMainQueueTransition "
                + "finalCallbackDelivered="
                + "\(didDeliverMainQueueTurn ? 1 : 0)"
        )
    }

    @MainActor
    private func searchInputKeyboardReadinessEvidence(
        harness: SearchSystemTextInputBridgeTestHarness,
        window: NSWindow
    ) -> String {
        let responder = window.firstResponder.map {
            String(describing: type(of: $0))
        } ?? "nil"
        return "unmetCondition=exactSearchKeyboardReadiness "
            + "finalWindowKey=\(window.isKeyWindow ? 1 : 0) "
            + "finalResponderMatches="
            + "\(window.firstResponder === harness.textView ? 1 : 0) "
            + "finalResponder=\(responder) "
            + "finalReadinessChanges="
            + "\(harness.keyboardReadinessChanges)"
    }

}
