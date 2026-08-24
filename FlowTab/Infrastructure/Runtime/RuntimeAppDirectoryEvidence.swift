import AppKit
import Foundation
import FlowTabCore

struct RuntimeAppProcessIdentity: Equatable, Hashable, Sendable {
    let appID: String
    let pid: pid_t
    let isDirectoryMember: Bool
    let isSwitcherEligible: Bool

    var processKey: RuntimeAppProcessKey {
        RuntimeAppProcessKey(appID: appID, pid: pid)
    }
}

struct RuntimeAppProcessKey: Equatable, Hashable, Sendable {
    let appID: String
    let pid: pid_t
}

struct RuntimeAppDirectorySnapshotEvidence: Equatable, Sendable {
    let sourceID: UUID
    let revision: UInt64
    let capturedAt: TimeInterval
    let processIdentities: [RuntimeAppProcessIdentity]
    let entries: [RuntimeAppDirectoryEntry]

    init(
        sourceID: UUID,
        revision: UInt64,
        capturedAt: TimeInterval,
        processIdentities: [RuntimeAppProcessIdentity],
        entries: [RuntimeAppDirectoryEntry]
    ) {
        self.sourceID = sourceID
        self.revision = revision
        self.capturedAt = capturedAt
        self.processIdentities = processIdentities.sorted(by: Self.identitySort)
        self.entries = entries.sorted(by: Self.entrySort)
    }

    var membership: ApplicationDirectoryMembership {
        ApplicationDirectoryMembership(
            directoryAppIDs: Set(
                processIdentities.lazy
                    .filter(\.isDirectoryMember)
                    .map(\.appID)
            ),
            switcherEligibleAppIDs: Set(
                processIdentities.lazy
                    .filter(\.isSwitcherEligible)
                    .map(\.appID)
            )
        )
    }

    var processMembershipSignature: Set<RuntimeAppProcessIdentity> {
        Set(processIdentities)
    }

    func containsDirectoryProcess(appID: String, pid: pid_t) -> Bool {
        processIdentities.contains {
            $0.appID == appID && $0.pid == pid && $0.isDirectoryMember
        }
    }

    func containsSwitcherEligibleProcess(appID: String, pid: pid_t) -> Bool {
        processIdentities.contains {
            $0.appID == appID && $0.pid == pid && $0.isSwitcherEligible
        }
    }

    func withEntries(_ entries: [RuntimeAppDirectoryEntry]) -> Self {
        Self(
            sourceID: sourceID,
            revision: revision,
            capturedAt: capturedAt,
            processIdentities: processIdentities,
            entries: entries
        )
    }

    func excludingProcesses(_ processKeys: Set<RuntimeAppProcessKey>) -> Self {
        guard !processKeys.isEmpty else { return self }
        return Self(
            sourceID: sourceID,
            revision: revision,
            capturedAt: capturedAt,
            processIdentities: processIdentities.filter {
                !processKeys.contains($0.processKey)
            },
            entries: entries.filter {
                !processKeys.contains(RuntimeAppProcessKey(appID: $0.appID, pid: $0.pid))
            }
        )
    }

    private static func identitySort(
        _ lhs: RuntimeAppProcessIdentity,
        _ rhs: RuntimeAppProcessIdentity
    ) -> Bool {
        lhs.appID == rhs.appID ? lhs.pid < rhs.pid : lhs.appID < rhs.appID
    }

    private static func entrySort(
        _ lhs: RuntimeAppDirectoryEntry,
        _ rhs: RuntimeAppDirectoryEntry
    ) -> Bool {
        lhs.appID == rhs.appID ? lhs.pid < rhs.pid : lhs.appID < rhs.appID
    }
}

protocol RuntimeAppDirectoryProviding: AnyObject {
    func appDirectoryEntriesForRuntimeMaintenance() -> [RuntimeAppDirectoryEntry]
    func appDirectorySnapshotEvidenceForPresentation() -> RuntimeAppDirectorySnapshotEvidence
    func appDirectorySnapshotEvidenceForRuntimeMaintenance() -> RuntimeAppDirectorySnapshotEvidence
}

extension RuntimeAppDirectoryProviding {
    func appDirectorySnapshotEvidenceForPresentation() -> RuntimeAppDirectorySnapshotEvidence {
        RuntimeLegacyAppDirectoryEvidenceFactory.make(
            provider: self,
            entries: appDirectoryEntriesForRuntimeMaintenance()
        )
    }

    func appDirectorySnapshotEvidenceForRuntimeMaintenance() -> RuntimeAppDirectorySnapshotEvidence {
        RuntimeLegacyAppDirectoryEvidenceFactory.make(
            provider: self,
            entries: appDirectoryEntriesForRuntimeMaintenance()
        )
    }
}

enum RuntimeAppDirectoryProviderFactory {
    static func makeDefault() -> RuntimeAppDirectoryProviding {
#if FLOWTAB_TESTING
        if FlowTabTestLaunchOptions.usesMockRuntimeProjection {
            return RuntimeUITestProjectionAppDirectoryProvider(
                attachesRunningApplication: false
            )
        }
#endif
        return RuntimeWorkspaceAppDirectoryProvider()
    }
}

final class RuntimeWorkspaceAppDirectoryProvider: RuntimeAppDirectoryProviding {
    private struct CapturedProcess {
        let identity: RuntimeAppProcessIdentity
        let entry: RuntimeAppDirectoryEntry?
    }

    private let snapshotLock = NSLock()
    private let sourceID = UUID()
    private var revision: UInt64 = 0
    private let runningApplicationsProvider: () -> [NSRunningApplication]
    private let currentPIDProvider: () -> pid_t
    private let showInCommandTabProvider: () -> Bool
    private let rankProvider: ([NSRunningApplication]) -> [pid_t: Int]

    init(
        runningApplicationsProvider: @escaping () -> [NSRunningApplication] = {
            NSWorkspace.shared.runningApplications
        },
        currentPIDProvider: @escaping () -> pid_t = {
            ProcessInfo.processInfo.processIdentifier
        },
        showInCommandTabProvider: @escaping () -> Bool = {
            AppVisibilityPreferencesStore.loadShowInCommandTab()
        },
        rankProvider: @escaping ([NSRunningApplication]) -> [pid_t: Int] = {
            RuntimeAppRankProvider.collectAppRankByPID(for: $0)
        }
    ) {
        self.runningApplicationsProvider = runningApplicationsProvider
        self.currentPIDProvider = currentPIDProvider
        self.showInCommandTabProvider = showInCommandTabProvider
        self.rankProvider = rankProvider
    }

    func appDirectoryEntriesForRuntimeMaintenance() -> [RuntimeAppDirectoryEntry] {
        appDirectorySnapshotEvidenceForRuntimeMaintenance().entries
    }

    func appDirectorySnapshotEvidenceForPresentation() -> RuntimeAppDirectorySnapshotEvidence {
        captureEvidence().evidence
    }

    func appDirectorySnapshotEvidenceForRuntimeMaintenance() -> RuntimeAppDirectorySnapshotEvidence {
        let captured = captureEvidence()
        let rankByPID = rankProvider(captured.directoryApplications)
        return captured.evidence.withEntries(
            captured.evidence.entries.map { entry in
                entry.withActivationRank(rankByPID[entry.pid])
            }
        )
    }

    private func captureEvidence() -> (
        evidence: RuntimeAppDirectorySnapshotEvidence,
        directoryApplications: [NSRunningApplication]
    ) {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }

        revision &+= 1
        let capturedAt = Date.timeIntervalSinceReferenceDate
        let currentPID = currentPIDProvider()
        let showInCommandTab = showInCommandTabProvider()
        let capturedProcesses = runningApplicationsProvider().map { app in
            capturedProcess(
                app,
                currentPID: currentPID,
                showInCommandTab: showInCommandTab
            )
        }
        let entries = capturedProcesses.compactMap(\.entry)
        return (
            RuntimeAppDirectorySnapshotEvidence(
                sourceID: sourceID,
                revision: revision,
                capturedAt: capturedAt,
                processIdentities: capturedProcesses.map(\.identity),
                entries: entries
            ),
            entries.compactMap(\.runningApplication)
        )
    }

    private func capturedProcess(
        _ app: NSRunningApplication,
        currentPID: pid_t,
        showInCommandTab: Bool
    ) -> CapturedProcess {
        let pid = app.processIdentifier
        let appID = RuntimeAppIdentity.appID(for: app)
        let isCurrentProcess = pid == currentPID
        let isTerminated = app.isTerminated
        let isDirectoryMember = RuntimeApplicationDirectoryFilter.shouldIncludeRunningApplication(
            activationPolicy: app.activationPolicy,
            isTerminated: isTerminated,
            pid: pid,
            currentPID: currentPID
        )
        let isSwitcherEligible = isDirectoryMember
            && !isTerminated
            && (isCurrentProcess ? showInCommandTab : app.activationPolicy == .regular)
        let identity = RuntimeAppProcessIdentity(
            appID: appID,
            pid: pid,
            isDirectoryMember: isDirectoryMember,
            isSwitcherEligible: isSwitcherEligible
        )
        guard isDirectoryMember else {
            return CapturedProcess(identity: identity, entry: nil)
        }
        return CapturedProcess(
            identity: identity,
            entry: RuntimeAppDirectoryEntry(
                app: app,
                isEligibleForAppSwitcherProjection: isSwitcherEligible
            )
        )
    }
}

private final class RuntimeLegacyAppDirectoryEvidenceFactory: @unchecked Sendable {
    private struct ProviderState {
        let sourceID: UUID
        var revision: UInt64
    }

    private static let shared = RuntimeLegacyAppDirectoryEvidenceFactory()

    private let lock = NSLock()
    private var statesByProviderID: [ObjectIdentifier: ProviderState] = [:]

    static func make(
        provider: AnyObject,
        entries: [RuntimeAppDirectoryEntry]
    ) -> RuntimeAppDirectorySnapshotEvidence {
        shared.make(provider: provider, entries: entries)
    }

    private func make(
        provider: AnyObject,
        entries: [RuntimeAppDirectoryEntry]
    ) -> RuntimeAppDirectorySnapshotEvidence {
        lock.lock()
        defer { lock.unlock() }
        let providerID = ObjectIdentifier(provider)
        var state = statesByProviderID[providerID]
            ?? ProviderState(sourceID: UUID(), revision: 0)
        state.revision &+= 1
        statesByProviderID[providerID] = state
        return RuntimeAppDirectorySnapshotEvidence(
            sourceID: state.sourceID,
            revision: state.revision,
            capturedAt: Date.timeIntervalSinceReferenceDate,
            processIdentities: entries.map { entry in
                RuntimeAppProcessIdentity(
                    appID: entry.appID,
                    pid: entry.pid,
                    isDirectoryMember: true,
                    isSwitcherEligible: entry.isEligibleForAppSwitcherProjection
                )
            },
            entries: entries
        )
    }
}
