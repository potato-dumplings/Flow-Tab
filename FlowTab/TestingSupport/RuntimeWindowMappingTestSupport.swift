#if FLOWTAB_TESTING
import AppKit
import ApplicationServices
import Foundation

enum RuntimeWindowMappingTestSupport {
    struct ResolvedEntry {
        let windowID: String
        let title: String
        let isMinimized: Bool
        let cgWindowID: CGWindowID?
        let frame: CGRect?
        let spaceIDs: [Int]
        let hasActivationHandle: Bool
        let lastConfirmationSource: WindowBindingConfirmationSource?

        init(
            windowID: String,
            title: String,
            isMinimized: Bool,
            cgWindowID: CGWindowID?,
            frame: CGRect? = nil,
            spaceIDs: [Int] = [],
            hasActivationHandle: Bool = false,
            lastConfirmationSource: WindowBindingConfirmationSource? = nil
        ) {
            self.windowID = windowID
            self.title = title
            self.isMinimized = isMinimized
            self.cgWindowID = cgWindowID
            self.frame = frame
            self.spaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(spaceIDs)
            self.hasActivationHandle = hasActivationHandle
            self.lastConfirmationSource = lastConfirmationSource
        }
    }

    static func validCGWindowIDs(
        existingCGWindowIDs: Set<CGWindowID>,
        allCGWindows: [RuntimeCGWindowEntry]
    ) -> [CGWindowID] {
        RuntimeWindowListSupplementer.selectSupplementalOffSpaceCGWindows(
            existingCGWindowIDs: existingCGWindowIDs,
            allCGWindows: allCGWindows
        ).map(\.id)
    }

    static func supplementalCGWindowIDs(
        existingCGWindowIDs: Set<CGWindowID>,
        allCGWindows: [RuntimeCGWindowEntry]
    ) -> [CGWindowID] {
        validCGWindowIDs(
            existingCGWindowIDs: existingCGWindowIDs,
            allCGWindows: allCGWindows
        )
    }

    static func supplementalCGWindowTitle(
        appName: String,
        cgWindow: RuntimeCGWindowEntry,
        cachedAXTitlesByCGWindowID: [CGWindowID: String] = [:]
    ) -> String {
        _ = cachedAXTitlesByCGWindowID
        return RuntimeWindowTitleResolver.supplementalCGWindowTitle(
            appName: appName,
            cgWindow: cgWindow
        )
    }

    static func appendOffSpaceCGWindows(
        entries: [ResolvedEntry],
        appName: String,
        pid: pid_t,
        allCGWindows: [RuntimeCGWindowEntry],
        matchedCGWindowIDs: Set<CGWindowID> = []
    ) -> [ResolvedEntry] {
        RuntimeWindowListSupplementer.appendOffSpaceCGWindows(
            to: entries.map {
                RuntimeWindowListEntry(
                    windowID: $0.windowID,
                    title: $0.title,
                    isMinimized: $0.isMinimized,
                    cgWindowID: $0.cgWindowID,
                    axWindow: nil,
                    frame: $0.frame,
                    spaceIDs: $0.spaceIDs,
                    lastConfirmationSource: $0.lastConfirmationSource
                )
            },
            appName: appName,
            pid: pid,
            allCGWindows: allCGWindows,
            matchedCGWindowIDs: matchedCGWindowIDs
        ).map(Self.resolvedEntry)
    }

    static func resolveCGWindowAssignments(
        axWindows: [RuntimeAXWindowEntry],
        cgWindows: [RuntimeCGWindowEntry],
        exactBridgeMatches: [String: CGWindowID] = [:],
        previousMatches: [String: CGWindowID] = [:],
        previousAXWindowIDs: Set<String> = [],
        previousCGWindowIDs: Set<CGWindowID> = [],
        pid: pid_t = 100,
        appName: String = "FlowTab Test"
    ) -> [String: CGWindowID] {
        let windowRecordStore = mappingStore(
            previousMatches: previousMatches,
            previousAXWindowIDs: previousAXWindowIDs,
            previousCGWindowIDs: previousCGWindowIDs,
            pid: pid
        )
        let previousExactBridgeOverride = AXWindowInspector.cgWindowIDOverrideForTesting
        AXWindowInspector.cgWindowIDOverrideForTesting = exactBridgeOverride(
            axEntries: axWindows,
            requestedWindowIDsByAXWindowID: exactBridgeMatches
        )
        defer {
            AXWindowInspector.cgWindowIDOverrideForTesting = previousExactBridgeOverride
        }
        return windowRecordStore.resolveStableWindowMapping(
            axWindows: axWindows,
            cgWindows: cgWindows,
            pid: pid,
            appName: appName
        ).exactMatchesByAXWindowID
    }

    static func resolveCGWindowAssignmentDiagnostics(
        axWindows: [RuntimeAXWindowEntry],
        cgWindows: [RuntimeCGWindowEntry],
        exactBridgeMatches: [String: CGWindowID] = [:],
        previousMatches: [String: CGWindowID] = [:],
        previousAXWindowIDs: Set<String> = [],
        previousCGWindowIDs: Set<CGWindowID> = [],
        pid: pid_t = 100,
        appName: String = "FlowTab Test"
    ) -> [WindowBindingDiagnostic] {
        let windowRecordStore = mappingStore(
            previousMatches: previousMatches,
            previousAXWindowIDs: previousAXWindowIDs,
            previousCGWindowIDs: previousCGWindowIDs,
            pid: pid
        )
        let previousExactBridgeOverride = AXWindowInspector.cgWindowIDOverrideForTesting
        AXWindowInspector.cgWindowIDOverrideForTesting = exactBridgeOverride(
            axEntries: axWindows,
            requestedWindowIDsByAXWindowID: exactBridgeMatches
        )
        defer {
            AXWindowInspector.cgWindowIDOverrideForTesting = previousExactBridgeOverride
        }
        return windowRecordStore.resolveStableWindowMapping(
            axWindows: axWindows,
            cgWindows: cgWindows,
            pid: pid,
            appName: appName
        ).bindingDiagnostics
    }

    static func resolveWindowEntries(
        axWindows: [RuntimeAXWindowEntry],
        cgWindows: [RuntimeCGWindowEntry],
        exactBridgeMatches: [String: CGWindowID] = [:],
        previousMatches: [String: CGWindowID] = [:],
        previousAXWindowIDs: Set<String> = [],
        previousCGWindowIDs: Set<CGWindowID> = [],
        pid: pid_t = 100,
        appName: String = "FlowTab Test"
    ) -> [ResolvedEntry] {
        let windowRecordStore = mappingStore(
            previousMatches: previousMatches,
            previousAXWindowIDs: previousAXWindowIDs,
            previousCGWindowIDs: previousCGWindowIDs,
            pid: pid
        )
        let previousExactBridgeOverride = AXWindowInspector.cgWindowIDOverrideForTesting
        AXWindowInspector.cgWindowIDOverrideForTesting = exactBridgeOverride(
            axEntries: axWindows,
            requestedWindowIDsByAXWindowID: exactBridgeMatches
        )
        defer {
            AXWindowInspector.cgWindowIDOverrideForTesting = previousExactBridgeOverride
        }
        return RuntimeWindowMappingPresentationAssembler.resolvedStableWindowEntries(
            windowRecordStore: windowRecordStore,
            axWindows: axWindows,
            cgWindows: cgWindows,
            pid: pid,
            appName: appName
        ).map(Self.resolvedEntry)
    }

    static func resolveWindowEntriesAndProjectedEntries(
        axWindows: [RuntimeAXWindowEntry],
        cgWindows: [RuntimeCGWindowEntry],
        exactBridgeMatches: [String: CGWindowID] = [:],
        previousMatches: [String: CGWindowID] = [:],
        previousAXWindowIDs: Set<String> = [],
        previousCGWindowIDs: Set<CGWindowID> = [],
        pid: pid_t = 100,
        appName: String = "FlowTab Test"
    ) -> (resolvedEntries: [ResolvedEntry], projectedEntries: [ResolvedEntry]) {
        let windowRecordStore = mappingStore(
            previousMatches: previousMatches,
            previousAXWindowIDs: previousAXWindowIDs,
            previousCGWindowIDs: previousCGWindowIDs,
            pid: pid
        )
        let previousExactBridgeOverride = AXWindowInspector.cgWindowIDOverrideForTesting
        AXWindowInspector.cgWindowIDOverrideForTesting = exactBridgeOverride(
            axEntries: axWindows,
            requestedWindowIDsByAXWindowID: exactBridgeMatches
        )
        defer {
            AXWindowInspector.cgWindowIDOverrideForTesting = previousExactBridgeOverride
        }
        let resolvedEntries = RuntimeWindowMappingPresentationAssembler.resolvedStableWindowEntries(
            windowRecordStore: windowRecordStore,
            axWindows: axWindows,
            cgWindows: cgWindows,
            pid: pid,
            appName: appName
        ).map(Self.resolvedEntry)
        let projectedEntries = windowRecordStore.projectedWindowEntries(
            processIdentifier: pid,
            appName: appName
        ).map(Self.resolvedEntry)
        return (resolvedEntries, projectedEntries)
    }

    private static func mappingStore(
        previousMatches: [String: CGWindowID],
        previousAXWindowIDs: Set<String>,
        previousCGWindowIDs: Set<CGWindowID>,
        pid: pid_t
    ) -> RuntimeWindowRecordStore {
        let windowRecordStore = RuntimeWindowRecordStore()
        windowRecordStore.setState(
            windowMappingState(
                previousMatches: previousMatches,
                previousAXWindowIDs: previousAXWindowIDs,
                previousCGWindowIDs: previousCGWindowIDs,
                pid: pid
            ),
            for: pid
        )
        return windowRecordStore
    }

    private static func exactBridgeOverride(
        axEntries: [RuntimeAXWindowEntry],
        requestedWindowIDsByAXWindowID: [String: CGWindowID]
    ) -> ((AXUIElement) -> CGWindowID?)? {
        guard !requestedWindowIDsByAXWindowID.isEmpty else { return nil }
        let requestedWindowIDsByPointer = [UnsafeMutableRawPointer: CGWindowID](
            uniqueKeysWithValues: axEntries.compactMap { axEntry in
                guard let cgWindowID = requestedWindowIDsByAXWindowID[axEntry.id] else { return nil }
                let pointer = Unmanaged.passUnretained(axEntry.window).toOpaque()
                return (pointer, cgWindowID)
            }
        )
        return { window in
            requestedWindowIDsByPointer[Unmanaged.passUnretained(window).toOpaque()]
        }
    }

    private static func windowMappingState(
        previousMatches: [String: CGWindowID],
        previousAXWindowIDs: Set<String>,
        previousCGWindowIDs: Set<CGWindowID>,
        pid: pid_t
    ) -> RuntimeWindowMappingState {
        let seedTimestamp = Date.timeIntervalSinceReferenceDate
        let historicalCGWindowIDs = Set(previousMatches.values).union(previousCGWindowIDs)
        let records = Dictionary(uniqueKeysWithValues: historicalCGWindowIDs.map { cgWindowID in
            var record = RuntimeWindowRecord(
                cgWindowID: cgWindowID,
                stableWindowID: RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID),
                firstSeenAt: seedTimestamp
            )
            if let previousAXWindowID = previousMatches.first(where: { $0.value == cgWindowID })?.key {
                if previousAXWindowIDs.contains(previousAXWindowID) {
                    record.lastExactAXWindowID = previousAXWindowID
                }
                record.lastConfirmationSource = .stickyBinding
                record.lastExactConfirmedAt = seedTimestamp
            }
            return (cgWindowID, record)
        })
        return RuntimeWindowMappingState(
            windowRecordsByCGWindowID: records,
            validCGWindowIDs: previousCGWindowIDs,
            lastAXWindowIDs: previousAXWindowIDs
        )
    }

    private static func resolvedEntry(_ entry: RuntimeWindowListEntry) -> ResolvedEntry {
        ResolvedEntry(
            windowID: entry.windowID,
            title: entry.title,
            isMinimized: entry.isMinimized,
            cgWindowID: entry.cgWindowID,
            frame: entry.frame,
            spaceIDs: entry.spaceIDs,
            hasActivationHandle: entry.activationHandleID != nil || entry.axWindow != nil,
            lastConfirmationSource: entry.lastConfirmationSource
        )
    }
}
#endif
