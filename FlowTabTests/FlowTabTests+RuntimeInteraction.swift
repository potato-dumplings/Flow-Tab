import AppKit
import SwiftUI
import XCTest
@testable import FlowTab
import FlowTabCore
import Carbon

extension FlowTabTests {
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
    func testTerminateSelectedAppBehaviorKeepsAppUntilProcessActuallyExits() async {
        let model = LiveSwitcherModel()
        let initialApps = terminateScenarioApps()
        var snapshots: [RuntimeSnapshot] = [makeRuntimeSnapshot(apps: initialApps)]
        var snapshotReadCount = 0
        model.testingSnapshotProviderOverride = {
            snapshotReadCount += 1
            XCTAssertFalse(snapshots.isEmpty)
            return snapshots.removeFirst()
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        guard let terminatedAppID = model.session?.selectedApp.id else {
            XCTFail("Expected an active session before terminate flow")
            return
        }

        let appsAfterTermination = initialApps.filter { $0.id != terminatedAppID }
        snapshots.append(makeRuntimeSnapshot(apps: appsAfterTermination))

        model.terminateRequestOverride = { _ in (sent: true, pid: 42_000) }
        model.terminateRefreshPollIntervalNs = 2_000_000
        model.terminateRefreshTimeoutNs = 100_000_000

        var processCheckCount = 0
        model.isProcessRunningOverride = { _ in
            processCheckCount += 1
            return processCheckCount < 2
        }

        let layoutRefreshed = expectation(description: "post terminate layout refreshed")
        model.onSessionLayoutChanged = { layoutRefreshed.fulfill() }

        let result = model.terminateSelectedApp()
        XCTAssertEqual(result, .updatedSession)
        XCTAssertEqual(snapshotReadCount, 1)
        XCTAssertEqual(model.appCount, initialApps.count)
        XCTAssertTrue(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? false)
        XCTAssertEqual(model.terminatingAppID, terminatedAppID)

        await fulfillment(of: [layoutRefreshed], timeout: 1.0)
        XCTAssertEqual(snapshotReadCount, 2)
        XCTAssertGreaterThanOrEqual(processCheckCount, 2)
        XCTAssertEqual(model.appCount, appsAfterTermination.count)
        XCTAssertFalse(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? true)
        XCTAssertNil(model.terminatingAppID)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.appID, terminatedAppID)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.pid, 42_000)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.appInstanceGeneration, 1)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.attempt, 1)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.finalProcessState, .exited)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.reason, "poll")
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.action, .refresh)
        XCTAssertTrue(
            model.lastTerminateRefreshPollingDiagnostic?.logMessage.contains("finalProcessState=exited") ?? false
        )
        model.cancelSelection()
    }

    @MainActor
    func testTerminateSelectedAppBehaviorRefreshesWithoutPollingDelayWhenProcessAlreadyExited() async {
        let model = LiveSwitcherModel()
        let initialApps = terminateScenarioApps()
        var snapshots: [RuntimeSnapshot] = [makeRuntimeSnapshot(apps: initialApps)]
        var snapshotReadCount = 0
        model.testingSnapshotProviderOverride = {
            snapshotReadCount += 1
            XCTAssertFalse(snapshots.isEmpty)
            return snapshots.removeFirst()
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        guard let terminatedAppID = model.session?.selectedApp.id else {
            XCTFail("Expected an active session before terminate flow")
            return
        }

        let appsAfterTermination = initialApps.filter { $0.id != terminatedAppID }
        snapshots.append(makeRuntimeSnapshot(apps: appsAfterTermination))

        model.terminateRequestOverride = { _ in (sent: true, pid: 42_010) }
        model.terminateRefreshPollIntervalNs = 5_000_000_000
        model.terminateRefreshTimeoutNs = 5_000_000_000

        var processCheckCount = 0
        model.isProcessRunningOverride = { _ in
            processCheckCount += 1
            return false
        }

        let layoutRefreshed = expectation(description: "post terminate layout refreshed without polling delay")
        model.onSessionLayoutChanged = { layoutRefreshed.fulfill() }

        let result = model.terminateSelectedApp()
        XCTAssertEqual(result, .updatedSession)
        XCTAssertEqual(snapshotReadCount, 1)

        await fulfillment(of: [layoutRefreshed], timeout: 0.5)
        XCTAssertEqual(snapshotReadCount, 2)
        XCTAssertEqual(processCheckCount, 1)
        XCTAssertEqual(model.appCount, appsAfterTermination.count)
        XCTAssertFalse(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? true)
        XCTAssertNil(model.terminatingAppID)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.appID, terminatedAppID)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.pid, 42_010)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.appInstanceGeneration, 1)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.attempt, 0)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.finalProcessState, .exited)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.reason, "initial_process_check")
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.action, .refresh)
        model.cancelSelection()
    }

    @MainActor
    func testHandleApplicationTerminatedRefreshesFromRuntimeProjectionWithoutFullSnapshot() async {
        let initialApps = terminateScenarioApps()
        let snapshotService = RecordingRuntimeSnapshotService(appSwitcherApps: initialApps)
        let model = LiveSwitcherModel(snapshotService: snapshotService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        guard let terminatedAppID = model.session?.selectedApp.id else {
            XCTFail("Expected an active session before termination refresh")
            return
        }
        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.lightweightSnapshotRequestCount(), 0)

        let refreshedApps = initialApps.filter { $0.id != terminatedAppID }

        let layoutRefreshed = expectation(description: "layout refreshed from runtime projection")
        model.onSessionLayoutChanged = { layoutRefreshed.fulfill() }

        XCTAssertTrue(model.handleApplicationTerminated(appID: terminatedAppID, pid: 42_012))

        await fulfillment(of: [layoutRefreshed], timeout: 1.0)
        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.lightweightSnapshotRequestCount(), 0)
        XCTAssertEqual(
            snapshotService.appTerminationSignalsRecorded().map(\.appID),
            [terminatedAppID]
        )
        XCTAssertFalse(
            snapshotService.readCommittedSearchIndexProjection()?.appEntries.contains {
                $0.appID == terminatedAppID
            } ?? true
        )
        XCTAssertEqual(model.appCount, refreshedApps.count)
        XCTAssertFalse(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? true)
    }

    @MainActor
    func testTerminateSelectedAppUnitStopsPollingAfterTimeoutWhenAppStillRunning() async {
        let model = LiveSwitcherModel()
        let initialApps = terminateScenarioApps()
        var snapshots: [RuntimeSnapshot] = [makeRuntimeSnapshot(apps: initialApps)]
        var snapshotReadCount = 0
        model.testingSnapshotProviderOverride = {
            snapshotReadCount += 1
            XCTAssertFalse(snapshots.isEmpty)
            return snapshots.removeFirst()
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        guard let terminatedAppID = model.session?.selectedApp.id else {
            XCTFail("Expected an active session before terminate flow")
            return
        }

        model.terminateRequestOverride = { _ in (sent: true, pid: 42_001) }
        model.terminateRefreshPollIntervalNs = 2_000_000
        model.terminateRefreshTimeoutNs = 12_000_000
        var processCheckCount = 0
        model.isProcessRunningOverride = { _ in
            processCheckCount += 1
            return true
        }

        let noDeferredLayoutRefresh = expectation(description: "no deferred layout refresh")
        noDeferredLayoutRefresh.isInverted = true
        model.onSessionLayoutChanged = { noDeferredLayoutRefresh.fulfill() }

        let result = model.terminateSelectedApp()
        XCTAssertEqual(result, .updatedSession)
        XCTAssertEqual(snapshotReadCount, 1)
        XCTAssertEqual(model.appCount, initialApps.count)
        XCTAssertTrue(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? false)
        XCTAssertEqual(model.terminatingAppID, terminatedAppID)

        let didReachTerminateTimeout = await waitUntil("terminate polling reaches timeout") {
            model.lastTerminateRefreshPollingDiagnostic?.action == .timeout
        }
        await fulfillment(of: [noDeferredLayoutRefresh], timeout: 0.01)
        XCTAssertTrue(didReachTerminateTimeout)
        XCTAssertGreaterThan(processCheckCount, 0)
        XCTAssertEqual(snapshotReadCount, 1)
        XCTAssertEqual(model.appCount, initialApps.count)
        XCTAssertTrue(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? false)
        XCTAssertNil(model.terminatingAppID)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.appID, terminatedAppID)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.pid, 42_001)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.appInstanceGeneration, 1)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.attempt, 6)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.maxAttempts, 6)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.finalProcessState, .running)
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.reason, "timeout")
        XCTAssertEqual(model.lastTerminateRefreshPollingDiagnostic?.action, .timeout)
        XCTAssertTrue(
            model.lastTerminateRefreshPollingDiagnostic?.logMessage.contains("attempt=6/6") ?? false
        )
        model.cancelSelection()
    }

    @MainActor
    func testTerminateSelectedAppUnitKeepsPendingInstanceWhenSameBundleDifferentPIDTerminates() async {
        let model = LiveSwitcherModel()
        let initialApps = terminateScenarioApps()
        var snapshots: [RuntimeSnapshot] = [
            makeRuntimeSnapshot(apps: initialApps),
            makeRuntimeSnapshot(apps: initialApps)
        ]
        var snapshotReadCount = 0
        model.testingSnapshotProviderOverride = {
            snapshotReadCount += 1
            XCTAssertFalse(snapshots.isEmpty)
            return snapshots.removeFirst()
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        guard let terminatedAppID = model.session?.selectedApp.id else {
            XCTFail("Expected an active session before terminate flow")
            return
        }

        model.terminateRequestOverride = { _ in (sent: true, pid: 42_003) }
        model.terminateRefreshPollIntervalNs = 1_000_000_000
        model.terminateRefreshTimeoutNs = 1_000_000_000
        model.isProcessRunningOverride = { _ in true }

        let result = model.terminateSelectedApp()
        XCTAssertEqual(result, .updatedSession)
        XCTAssertEqual(model.pendingTerminateRequest?.appID, terminatedAppID)
        XCTAssertEqual(model.pendingTerminateRequest?.pid, 42_003)
        XCTAssertEqual(model.pendingTerminateRequest?.generation, 1)
        XCTAssertEqual(model.terminatingAppID, terminatedAppID)

        XCTAssertTrue(model.handleApplicationTerminated(appID: terminatedAppID, pid: 42_004))

        XCTAssertEqual(snapshotReadCount, 2)
        XCTAssertEqual(model.pendingTerminateRequest?.appID, terminatedAppID)
        XCTAssertEqual(model.pendingTerminateRequest?.pid, 42_003)
        XCTAssertEqual(model.pendingTerminateRequest?.generation, 1)
        XCTAssertEqual(model.terminatingAppID, terminatedAppID)
        XCTAssertTrue(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? false)
        model.cancelSelection()
    }

    @MainActor
    func testTerminateSelectedAppUnitRefreshesOnWorkspaceTerminateAfterPollingTimeout() async {
        let model = LiveSwitcherModel()
        let initialApps = terminateScenarioApps()
        var snapshots: [RuntimeSnapshot] = [makeRuntimeSnapshot(apps: initialApps)]
        var snapshotReadCount = 0
        model.testingSnapshotProviderOverride = {
            snapshotReadCount += 1
            XCTAssertFalse(snapshots.isEmpty)
            return snapshots.removeFirst()
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        guard let terminatedAppID = model.session?.selectedApp.id else {
            XCTFail("Expected an active session before terminate flow")
            return
        }

        let appsAfterTermination = initialApps.filter { $0.id != terminatedAppID }
        snapshots.append(makeRuntimeSnapshot(apps: appsAfterTermination))

        model.terminateRequestOverride = { _ in (sent: true, pid: 42_002) }
        model.terminateRefreshPollIntervalNs = 2_000_000
        model.terminateRefreshTimeoutNs = 12_000_000

        var processCheckCount = 0
        model.isProcessRunningOverride = { _ in
            processCheckCount += 1
            return true
        }

        let deferredLayoutRefresh = expectation(description: "deferred layout refresh")
        var layoutRefreshCount = 0
        model.onSessionLayoutChanged = {
            layoutRefreshCount += 1
            deferredLayoutRefresh.fulfill()
        }

        let result = model.terminateSelectedApp()
        XCTAssertEqual(result, .updatedSession)
        XCTAssertEqual(snapshotReadCount, 1)
        XCTAssertEqual(model.appCount, initialApps.count)
        XCTAssertTrue(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? false)

        let didReachTerminateTimeout = await waitUntil("terminate polling reaches timeout before workspace notification") {
            model.lastTerminateRefreshPollingDiagnostic?.action == .timeout
        }
        XCTAssertTrue(didReachTerminateTimeout)
        XCTAssertGreaterThan(processCheckCount, 0)
        XCTAssertEqual(layoutRefreshCount, 0)
        XCTAssertEqual(snapshotReadCount, 1)
        XCTAssertNil(model.terminatingAppID)

        model.handleApplicationTerminated(appID: terminatedAppID, pid: 42_002)

        await fulfillment(of: [deferredLayoutRefresh], timeout: 1.0)
        XCTAssertEqual(layoutRefreshCount, 1)
        XCTAssertEqual(snapshotReadCount, 2)
        XCTAssertEqual(model.appCount, appsAfterTermination.count)
        XCTAssertFalse(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? true)
        model.cancelSelection()
    }

}
