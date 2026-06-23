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

struct RuntimeWindowRecordAffectedEvidence: Equatable {
    let knownAffectedCGWindowIDs: Set<CGWindowID>
    let exactAffectedCGWindowIDs: Set<CGWindowID>

    static let empty = RuntimeWindowRecordAffectedEvidence(
        knownAffectedCGWindowIDs: [],
        exactAffectedCGWindowIDs: []
    )
}

struct RuntimeWindowMappingResolution {
    let exactMatchesByAXWindowID: [String: CGWindowID]
    let windowRecordsByCGWindowID: [CGWindowID: RuntimeWindowRecord]
    let validCGWindows: [RuntimeCGWindowEntry]
    let allowSpaceOneWithoutCurrentAXHandle: Bool
    let bindingDiagnostics: [WindowBindingDiagnostic]

    var knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry] {
        RuntimeWindowRecord.knownCGWindowsByID(
            windowRecordsByCGWindowID: windowRecordsByCGWindowID,
            validCGWindows: validCGWindows
        )
    }

    var windowLayerCGWindows: [RuntimeCGWindowEntry] {
        RuntimeWindowRecord.windowLayerCGWindows(
            windowRecordsByCGWindowID: windowRecordsByCGWindowID,
            validCGWindows: validCGWindows
        )
    }
}

struct RuntimeWindowMappingState {
    var windowRecordsByCGWindowID: [CGWindowID: RuntimeWindowRecord]
    private var derivedIndexes: RuntimeWindowRecordDerivedIndexes
    var hasObservedAXWindowHandle: Bool
    var consecutiveAXCollectionMisses: Int

    init(
        windowRecordsByCGWindowID: [CGWindowID: RuntimeWindowRecord] = [:],
        currentAXToCG: [String: CGWindowID] = [:],
        validCGWindowIDs: Set<CGWindowID> = [],
        lastAXWindowIDs: Set<String> = [],
        hasObservedAXWindowHandle: Bool = false,
        consecutiveAXCollectionMisses: Int = 0
    ) {
        self.windowRecordsByCGWindowID = windowRecordsByCGWindowID
        derivedIndexes = RuntimeWindowRecordDerivedIndexes(
            currentAXToCG: currentAXToCG,
            validCGWindowIDs: validCGWindowIDs,
            lastAXWindowIDs: lastAXWindowIDs
        )
        self.hasObservedAXWindowHandle = hasObservedAXWindowHandle
        self.consecutiveAXCollectionMisses = consecutiveAXCollectionMisses
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

    var isLikelyTransientAXRebuild: Bool {
        RuntimeAXWindowAbsencePolicy.isLikelyTransientRebuild(
            hasObservedAXWindowHandle: hasObservedAXWindowHandle,
            consecutiveAXCollectionMissCount: consecutiveAXCollectionMisses
        )
    }

    func isTransientEmptyCurrentAppWindowPayload(
        currentAppWindowPayloadWasEmpty: Bool
    ) -> Bool {
        currentAppWindowPayloadWasEmpty && isLikelyTransientAXRebuild
    }

    static func affectedCGWindowIDsByPID(
        affectedCGWindowIDs: Set<CGWindowID>,
        currentCGWindowsByPID: [pid_t: [RuntimeCGWindowEntry]],
        mappingStatesByPID: [pid_t: RuntimeWindowMappingState]
    ) -> [pid_t: Set<CGWindowID>] {
        guard !affectedCGWindowIDs.isEmpty else { return [:] }

        var affectedCGWindowIDsByPID: [pid_t: Set<CGWindowID>] = [:]
        for (pid, cgWindows) in currentCGWindowsByPID {
            let affected = Set(cgWindows.map(\.id)).intersection(affectedCGWindowIDs)
            if !affected.isEmpty {
                affectedCGWindowIDsByPID[pid, default: []].formUnion(affected)
            }
        }

        for (pid, mappingState) in mappingStatesByPID {
            let affected = mappingState.affectedWindowEvidence(
                for: affectedCGWindowIDs
            ).knownAffectedCGWindowIDs
            if !affected.isEmpty {
                affectedCGWindowIDsByPID[pid, default: []].formUnion(affected)
            }
        }
        return affectedCGWindowIDsByPID
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

    func affectedWindowEvidence(
        for affectedCGWindowIDs: Set<CGWindowID>
    ) -> RuntimeWindowRecordAffectedEvidence {
        let knownAffectedCGWindowIDs = affectedCGWindowIDs.intersection(
            windowRecordsByCGWindowID.keys
        )
        let exactAffectedCGWindowIDs = knownAffectedCGWindowIDs.filter { cgWindowID in
            windowRecordsByCGWindowID[cgWindowID]?.bindingConfidence == .exact
        }
        return RuntimeWindowRecordAffectedEvidence(
            knownAffectedCGWindowIDs: knownAffectedCGWindowIDs,
            exactAffectedCGWindowIDs: exactAffectedCGWindowIDs
        )
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

    static func knownCGWindowsByID(
        windowRecordsByCGWindowID: [CGWindowID: RuntimeWindowRecord],
        validCGWindows: [RuntimeCGWindowEntry]
    ) -> [CGWindowID: RuntimeCGWindowEntry] {
        var knownCGWindowsByID = Dictionary(uniqueKeysWithValues: validCGWindows.map { ($0.id, $0) })
        for (cgWindowID, record) in windowRecordsByCGWindowID {
            guard knownCGWindowsByID[cgWindowID] == nil else { continue }
            guard let knownCGWindow = record.synthesizedKnownCGWindowEntry() else { continue }
            knownCGWindowsByID[cgWindowID] = knownCGWindow
        }
        return knownCGWindowsByID
    }

    static func windowLayerCGWindows(
        windowRecordsByCGWindowID: [CGWindowID: RuntimeWindowRecord],
        validCGWindows: [RuntimeCGWindowEntry]
    ) -> [RuntimeCGWindowEntry] {
        let knownCGWindowsByID = knownCGWindowsByID(
            windowRecordsByCGWindowID: windowRecordsByCGWindowID,
            validCGWindows: validCGWindows
        )
        let validCGWindowIDs = Set(validCGWindows.map(\.id))
        let synthesizedWindows: [RuntimeCGWindowEntry] =
            windowRecordsByCGWindowID.keys.sorted().compactMap { cgWindowID in
                guard !validCGWindowIDs.contains(cgWindowID) else { return nil }
                return knownCGWindowsByID[cgWindowID]
            }
        return validCGWindows + synthesizedWindows
    }

    static func applyExactMatches(
        _ matches: [String: CGWindowID],
        source: WindowBindingConfirmationSource,
        pid: pid_t,
        currentAXWindowsByID: [String: RuntimeAXWindowEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String,
        observedAt: TimeInterval,
        windowRecordsByCGWindowID: inout [CGWindowID: RuntimeWindowRecord],
        exactMatchesByAXWindowID: inout [String: CGWindowID]
    ) {
        for (axWindowID, cgWindowID) in matches {
            guard let axWindow = currentAXWindowsByID[axWindowID] else { continue }
            var record = windowRecordsByCGWindowID[cgWindowID]
                ?? RuntimeWindowRecord(
                    cgWindowID: cgWindowID,
                    stableWindowID: RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID),
                    firstSeenAt: observedAt
                )
            let resolvedTitle = RuntimeWindowTitleResolver.stableWindowTitle(
                sourceTitle: axWindow.sourceTitle,
                matchedCGTitle: knownCGWindowsByID[cgWindowID]?.title,
                appName: appName,
                fallbackIndex: axWindow.index,
                refreshedAXTitle: nil
            )
            record.applyExactMatch(
                axWindow: axWindow,
                resolvedTitle: resolvedTitle,
                confirmationSource: source,
                observedAt: observedAt,
                matchedCGWindow: knownCGWindowsByID[cgWindowID]
            )
            windowRecordsByCGWindowID[cgWindowID] = record
            exactMatchesByAXWindowID[axWindowID] = cgWindowID
        }
    }

    func canReuseStickyBinding(with axWindow: RuntimeAXWindowEntry) -> Bool {
        let normalizedBindingTitle = normalizedRuntimeWindowTitle(displayTitle)
        let normalizedAXTitle = normalizedRuntimeWindowTitle(axWindow.sourceTitle ?? axWindow.title)
        let titleMatches: Bool
        switch (normalizedBindingTitle, normalizedAXTitle) {
        case let (bindingTitle?, axTitle?):
            titleMatches = bindingTitle.caseInsensitiveCompare(axTitle) == .orderedSame
        case (nil, _):
            titleMatches = true
        default:
            titleMatches = false
        }

        let frameMatches: Bool
        switch (displayFrame, axWindow.frame) {
        case let (bindingFrame?, axFrame?):
            frameMatches = RuntimeWindowTopologyClassifier.framesApproximatelyMatch(axFrame, bindingFrame)
        case (nil, _):
            frameMatches = true
        default:
            frameMatches = false
        }

        return titleMatches && frameMatches
    }

    func reusableStickyAXWindow(
        from axWindows: [RuntimeAXWindowEntry],
        assignedAXWindowIDs: Set<String>
    ) -> RuntimeAXWindowEntry? {
        if
            let lastKnownAXWindowID = lastExactAXWindowID,
            let exactIDMatch = axWindows.first(where: {
                $0.id == lastKnownAXWindowID && !assignedAXWindowIDs.contains($0.id)
            }),
            canReuseStickyBinding(with: exactIDMatch)
        {
            return exactIDMatch
        }

        guard let previousAXWindow = lastExactAXWindow else { return nil }
        return axWindows.first { axWindow in
            guard !assignedAXWindowIDs.contains(axWindow.id) else { return false }
            guard CFEqual(axWindow.window, previousAXWindow) else { return false }
            // Title changes are expected for a stable AX window handle. Once the
            // underlying AX element identity matches, prefer continuity and let
            // the current snapshot refresh title/frame in binding state.
            return true
        }
    }
}
