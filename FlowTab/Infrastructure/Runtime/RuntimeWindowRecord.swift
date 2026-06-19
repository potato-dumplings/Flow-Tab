import ApplicationServices
import Foundation

struct RuntimeAXWindowState: Equatable {
    var isMinimized: Bool
    var isFocused: Bool
    var isMain: Bool

    static let inactive = RuntimeAXWindowState(
        isMinimized: false,
        isFocused: false,
        isMain: false
    )
}

struct RuntimeAXWindowEntry {
    let index: Int
    let id: String
    let title: String
    let sourceTitle: String?
    let state: RuntimeAXWindowState
    let window: AXUIElement
    let frame: CGRect?

    init(
        index: Int,
        id: String,
        title: String,
        sourceTitle: String?,
        isMinimized: Bool,
        isFocused: Bool = false,
        isMain: Bool = false,
        window: AXUIElement,
        frame: CGRect?
    ) {
        self.index = index
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        state = RuntimeAXWindowState(
            isMinimized: isMinimized,
            isFocused: isFocused,
            isMain: isMain
        )
        self.window = window
        self.frame = frame
    }

    var isMinimized: Bool { state.isMinimized }
    var isFocused: Bool { state.isFocused }
    var isMain: Bool { state.isMain }
}

struct RuntimeCurrentAXAttachment {
    let axWindowID: String
    var axWindow: AXUIElement
    var title: String?
    var frame: CGRect?
    var state: RuntimeAXWindowState
}

struct RuntimeSpaceRecoveryState {
    let cgWindowID: CGWindowID
    var spaceIDs: [Int]
    var hasConfirmedActivationRoute: Bool
    var lastValidatedAt: TimeInterval?
    var invalidatedAt: TimeInterval?
}

struct RuntimeWindowRecordDerivedIndexes: Equatable {
    let currentAXToCG: [String: CGWindowID]
    let validCGWindowIDs: Set<CGWindowID>
    let lastAXWindowIDs: Set<String>

    var currentCGToAX: [CGWindowID: String] {
        Dictionary(uniqueKeysWithValues: currentAXToCG.map { ($1, $0) })
    }
}

struct RuntimeWindowMappingState {
    var windowRecordsByCGWindowID: [CGWindowID: RuntimeWindowRecord]
    private var derivedIndexes: RuntimeWindowRecordDerivedIndexes
    var hasObservedAXWindowHandle: Bool
    var consecutiveSnapshotsWithoutAXWindows: Int

    init(
        windowRecordsByCGWindowID: [CGWindowID: RuntimeWindowRecord] = [:],
        currentAXToCG: [String: CGWindowID] = [:],
        validCGWindowIDs: Set<CGWindowID> = [],
        lastAXWindowIDs: Set<String> = [],
        hasObservedAXWindowHandle: Bool = false,
        consecutiveSnapshotsWithoutAXWindows: Int = 0
    ) {
        self.windowRecordsByCGWindowID = windowRecordsByCGWindowID
        derivedIndexes = RuntimeWindowRecordDerivedIndexes(
            currentAXToCG: currentAXToCG,
            validCGWindowIDs: validCGWindowIDs,
            lastAXWindowIDs: lastAXWindowIDs
        )
        self.hasObservedAXWindowHandle = hasObservedAXWindowHandle
        self.consecutiveSnapshotsWithoutAXWindows = consecutiveSnapshotsWithoutAXWindows
    }

    var currentAXToCG: [String: CGWindowID] {
        derivedIndexes.currentAXToCG
    }

    var currentCGToAX: [CGWindowID: String] {
        derivedIndexes.currentCGToAX
    }

    var validCGWindowIDs: Set<CGWindowID> {
        derivedIndexes.validCGWindowIDs
    }

    var lastAXWindowIDs: Set<String> {
        derivedIndexes.lastAXWindowIDs
    }

    var isEmpty: Bool {
        windowRecordsByCGWindowID.isEmpty
    }

    @discardableResult
    mutating func clearDestroyedAXAttachment(
        axWindowID: String,
        observedAt: TimeInterval
    ) -> CGWindowID? {
        guard let cgWindowID = derivedIndexes.currentAXToCG[axWindowID],
              var record = windowRecordsByCGWindowID[cgWindowID] else {
            return nil
        }

        record.clearDestroyedAXAttachment(observedAt: observedAt)
        windowRecordsByCGWindowID[cgWindowID] = record

        var currentAXToCG = derivedIndexes.currentAXToCG
        currentAXToCG.removeValue(forKey: axWindowID)
        var lastAXWindowIDs = derivedIndexes.lastAXWindowIDs
        lastAXWindowIDs.remove(axWindowID)
        derivedIndexes = RuntimeWindowRecordDerivedIndexes(
            currentAXToCG: currentAXToCG,
            validCGWindowIDs: derivedIndexes.validCGWindowIDs,
            lastAXWindowIDs: lastAXWindowIDs
        )
        return cgWindowID
    }
}

enum RuntimeWindowRecordLifecycleDecision: Equatable {
    case keep
    case delete
}

struct RuntimeWindowRecordLifecyclePolicy: Equatable {
    let evidenceGraceInterval: TimeInterval

    static let runtimeDefault = RuntimeWindowRecordLifecyclePolicy(
        evidenceGraceInterval: 1.0
    )
}

struct RuntimeWindowRecord {
    let cgWindowID: CGWindowID
    let stableWindowID: String
    var lastKnownCGTitle: String?
    var lastKnownCGFrame: CGRect?
    var lastKnownDisplayTitle: String?
    var currentAXAttachment: RuntimeCurrentAXAttachment?
    var lastExactAXWindowID: String?
    var lastExactAXWindow: AXUIElement?
    var lastConfirmationSource: WindowBindingConfirmationSource?
    var lastExactConfirmedAt: TimeInterval?
    var spaceRecovery: RuntimeSpaceRecoveryState?
    let firstSeenAt: TimeInterval
    var lastSeenAt: TimeInterval
    var suspectDeletedAt: TimeInterval?
    var needsReconciliation: Bool
    var lastReconciliationMarkedAt: TimeInterval?

    init(
        cgWindowID: CGWindowID,
        stableWindowID: String,
        firstSeenAt: TimeInterval
    ) {
        self.cgWindowID = cgWindowID
        self.stableWindowID = stableWindowID
        lastKnownCGTitle = nil
        lastKnownCGFrame = nil
        lastKnownDisplayTitle = nil
        currentAXAttachment = nil
        lastExactAXWindowID = nil
        lastExactAXWindow = nil
        lastConfirmationSource = nil
        lastExactConfirmedAt = nil
        spaceRecovery = nil
        self.firstSeenAt = firstSeenAt
        lastSeenAt = firstSeenAt
        suspectDeletedAt = nil
        needsReconciliation = false
        lastReconciliationMarkedAt = nil
    }

    var hasStickyBinding: Bool {
        lastExactAXWindowID != nil || lastExactAXWindow != nil || lastConfirmationSource != nil
    }

    var bindingConfidence: WindowBindingConfidence {
        if let lastConfirmationSource {
            return lastConfirmationSource.bindingConfidence
        }
        if hasStickyBinding {
            return .sticky
        }
        return .provisional
    }

    var bindingAllowedActions: Set<WindowBindingAction> {
        bindingConfidence.allowedActions
    }

    var bindingDiagnostic: WindowBindingDiagnostic {
        WindowBindingDiagnostic(
            stableWindowID: stableWindowID,
            axWindowID: currentAXWindowID ?? lastExactAXWindowID,
            cgWindowID: cgWindowID,
            confidence: bindingConfidence,
            source: lastConfirmationSource,
            reason: nil,
            candidateCount: 1,
            allowedActions: bindingAllowedActions
        )
    }

    var hasCurrentActivationHandle: Bool {
        currentAXAttachment != nil
    }

    var currentAXWindowID: String? {
        currentAXAttachment?.axWindowID
    }

    var displayTitle: String? {
        currentAXAttachment?.title ?? lastKnownDisplayTitle ?? lastKnownCGTitle
    }

    var displayFrame: CGRect? {
        currentAXAttachment?.frame ?? lastKnownCGFrame
    }

    var isMinimized: Bool {
        currentAXAttachment?.state.isMinimized ?? false
    }

    var isFocused: Bool {
        currentAXAttachment?.state.isFocused ?? false
    }

    var isMain: Bool {
        currentAXAttachment?.state.isMain ?? false
    }

    mutating func refreshCGState(
        from cgWindow: RuntimeCGWindowEntry,
        observedAt: TimeInterval
    ) {
        if let cgTitle = normalizedRuntimeWindowTitle(cgWindow.title) {
            lastKnownCGTitle = cgTitle
        }
        if let cgBounds = cgWindow.bounds {
            lastKnownCGFrame = cgBounds
        }
        let normalizedSpaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(cgWindow.spaceIDs)
        if !normalizedSpaceIDs.isEmpty {
            var recovery = spaceRecovery ?? RuntimeSpaceRecoveryState(
                cgWindowID: cgWindow.id,
                spaceIDs: normalizedSpaceIDs,
                hasConfirmedActivationRoute: true,
                lastValidatedAt: observedAt,
                invalidatedAt: nil
            )
            recovery.spaceIDs = normalizedSpaceIDs
            recovery.hasConfirmedActivationRoute = true
            recovery.lastValidatedAt = observedAt
            recovery.invalidatedAt = nil
            spaceRecovery = recovery
        }
        lastSeenAt = observedAt
        suspectDeletedAt = nil
        clearReconciliationNeed()
    }

    mutating func reconcileLifecycle(
        validCGWindowIDs: Set<CGWindowID>,
        observedAt: TimeInterval,
        policy: RuntimeWindowRecordLifecyclePolicy = .runtimeDefault
    ) -> RuntimeWindowRecordLifecycleDecision {
        if validCGWindowIDs.contains(cgWindowID) || currentAXAttachment != nil {
            suspectDeletedAt = nil
            if var recovery = spaceRecovery {
                recovery.invalidatedAt = nil
                spaceRecovery = recovery
            }
            clearReconciliationNeed()
            return .keep
        }

        guard hasStickyBinding || spaceRecovery?.hasConfirmedActivationRoute == true else {
            clearReconciliationNeed()
            return .delete
        }

        let firstSuspectAt = suspectDeletedAt ?? observedAt
        suspectDeletedAt = firstSuspectAt
        if var recovery = spaceRecovery, recovery.invalidatedAt == nil {
            recovery.invalidatedAt = observedAt
            spaceRecovery = recovery
        }
        guard observedAt - firstSuspectAt < policy.evidenceGraceInterval else {
            clearReconciliationNeed()
            return .delete
        }
        clearReconciliationNeed()
        return .keep
    }

    mutating func clearCurrentAXAttachment() {
        currentAXAttachment = nil
    }

    mutating func clearDestroyedAXAttachment(observedAt: TimeInterval) {
        currentAXAttachment = nil
        lastConfirmationSource = nil
        markNeedsReconciliation(observedAt: observedAt)
    }

    mutating func markNeedsReconciliation(observedAt: TimeInterval) {
        needsReconciliation = true
        lastReconciliationMarkedAt = observedAt
    }

    mutating func clearReconciliationNeed() {
        needsReconciliation = false
    }

    mutating func invalidateSpaceRecovery(observedAt: TimeInterval) {
        guard var recovery = spaceRecovery else { return }
        recovery.invalidatedAt = observedAt
        spaceRecovery = recovery
    }

    mutating func updateFallbackDisplayStateIfNeeded() {
        if lastKnownDisplayTitle == nil {
            lastKnownDisplayTitle = lastKnownCGTitle
        }
    }

    mutating func applyExactMatch(
        axWindow: RuntimeAXWindowEntry,
        resolvedTitle: String,
        confirmationSource: WindowBindingConfirmationSource,
        observedAt: TimeInterval,
        matchedCGWindow: RuntimeCGWindowEntry?
    ) {
        let previousSource = lastConfirmationSource
        let previousConfidence = bindingConfidence
        if let matchedCGWindow {
            refreshCGState(from: matchedCGWindow, observedAt: observedAt)
        } else {
            lastSeenAt = observedAt
            suspectDeletedAt = nil
            clearReconciliationNeed()
        }
        currentAXAttachment = RuntimeCurrentAXAttachment(
            axWindowID: axWindow.id,
            axWindow: axWindow.window,
            title: normalizedRuntimeWindowTitle(resolvedTitle) ?? resolvedTitle,
            frame: axWindow.frame,
            state: axWindow.state
        )
        lastKnownDisplayTitle = currentAXAttachment?.title ?? lastKnownDisplayTitle
        lastConfirmationSource = confirmationSource
        let allowsStickyHistoryUpdate = confirmationSource.bindingConfidence
            .allowedActions
            .contains(.updateStickyHistory)
        if allowsStickyHistoryUpdate {
            lastExactAXWindowID = axWindow.id
            lastExactAXWindow = axWindow.window
            lastExactConfirmedAt = observedAt
        } else {
            RuntimeLog.debug(
                .axMatch,
                "sticky-history-update skipped windowID=\(stableWindowID) cg=\(cgWindowID) ax=\(axWindow.id) source=\(confirmationSource.rawValue) confidence=\(confirmationSource.bindingConfidence.rawValue)"
            )
        }
        let currentConfidence = bindingConfidence
        if previousSource != confirmationSource || previousConfidence != currentConfidence {
            RuntimeLog.debug(
                .axMatch,
                "binding-confidence-change windowID=\(stableWindowID) cg=\(cgWindowID) ax=\(axWindow.id) confidence=\(previousConfidence.rawValue)->\(currentConfidence.rawValue) source=\(previousSource?.rawValue ?? "none")->\(confirmationSource.rawValue)"
            )
        }
    }

    func synthesizedKnownCGWindowEntry() -> RuntimeCGWindowEntry? {
        let spaceIDs = spaceRecovery?.spaceIDs ?? []
        guard lastKnownCGTitle != nil || lastKnownCGFrame != nil || !spaceIDs.isEmpty else {
            return nil
        }
        return RuntimeCGWindowEntry(
            id: cgWindowID,
            title: lastKnownCGTitle,
            bounds: lastKnownCGFrame,
            isOnscreen: false,
            alpha: 1.0,
            storeType: 1,
            spaceIDs: spaceIDs
        )
    }
}
