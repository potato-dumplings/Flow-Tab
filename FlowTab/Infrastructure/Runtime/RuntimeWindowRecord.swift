import ApplicationServices
import Foundation

struct RuntimeCurrentAXAttachment {
    let axWindowID: String
    var axWindow: AXUIElement
    var title: String?
    var frame: CGRect?
    var isMinimized: Bool
}

struct RuntimeSpaceRecoveryState {
    let cgWindowID: CGWindowID
    var spaceIDs: [Int]
    var hasConfirmedActivationRoute: Bool
    var lastValidatedAt: TimeInterval?
    var invalidatedAt: TimeInterval?
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
    }

    var hasStickyBinding: Bool {
        lastExactAXWindowID != nil || lastExactAXWindow != nil || lastConfirmationSource != nil
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
        currentAXAttachment?.isMinimized ?? false
    }

    mutating func refreshCGState(
        from cgWindow: RuntimeSnapshotProvider.CGWindowEntry,
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
    }

    mutating func clearCurrentAXAttachment() {
        currentAXAttachment = nil
    }

    mutating func updateFallbackDisplayStateIfNeeded() {
        if lastKnownDisplayTitle == nil {
            lastKnownDisplayTitle = lastKnownCGTitle
        }
    }

    mutating func applyExactMatch(
        axWindow: RuntimeSnapshotProvider.AXWindowEntry,
        resolvedTitle: String,
        confirmationSource: WindowBindingConfirmationSource,
        observedAt: TimeInterval,
        matchedCGWindow: RuntimeSnapshotProvider.CGWindowEntry?
    ) {
        if let matchedCGWindow {
            refreshCGState(from: matchedCGWindow, observedAt: observedAt)
        } else {
            lastSeenAt = observedAt
            suspectDeletedAt = nil
        }
        currentAXAttachment = RuntimeCurrentAXAttachment(
            axWindowID: axWindow.id,
            axWindow: axWindow.window,
            title: normalizedRuntimeWindowTitle(resolvedTitle) ?? resolvedTitle,
            frame: axWindow.frame,
            isMinimized: axWindow.isMinimized
        )
        lastExactAXWindowID = axWindow.id
        lastExactAXWindow = axWindow.window
        lastKnownDisplayTitle = currentAXAttachment?.title ?? lastKnownDisplayTitle
        lastConfirmationSource = confirmationSource
        lastExactConfirmedAt = observedAt
    }

    func synthesizedKnownCGWindowEntry() -> RuntimeSnapshotProvider.CGWindowEntry? {
        let spaceIDs = spaceRecovery?.spaceIDs ?? []
        guard lastKnownCGTitle != nil || lastKnownCGFrame != nil || !spaceIDs.isEmpty else {
            return nil
        }
        return RuntimeSnapshotProvider.CGWindowEntry(
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
