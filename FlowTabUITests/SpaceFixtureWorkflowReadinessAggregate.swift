import Foundation

struct SpaceFixtureWorkflowReadinessAggregateExpectation:
    Equatable
{
    let workflowAppID: String
    let bundleIdentifier: String
    let windowPlanIndices: [Int]
    let fullscreenWindowPlanIndices: [Int]
    let windowTitles: [String]

    init(
        workflowAppID: String,
        bundleIdentifier: String,
        windowPlanIndices: [Int],
        fullscreenWindowPlanIndices: [Int],
        windowTitles: [String]
    ) {
        precondition(!workflowAppID.isEmpty)
        precondition(!bundleIdentifier.isEmpty)
        precondition(!windowPlanIndices.isEmpty)
        precondition(
            windowPlanIndices
                == Array(Set(windowPlanIndices)).sorted()
        )
        precondition(
            fullscreenWindowPlanIndices
                == Array(
                    Set(fullscreenWindowPlanIndices)
                ).sorted()
        )
        precondition(
            fullscreenWindowPlanIndices.allSatisfy(
                windowPlanIndices.contains
            )
        )
        precondition(
            windowTitles.count == windowPlanIndices.count
        )
        self.workflowAppID = workflowAppID
        self.bundleIdentifier = bundleIdentifier
        self.windowPlanIndices = windowPlanIndices
        self.fullscreenWindowPlanIndices =
            fullscreenWindowPlanIndices
        self.windowTitles = windowTitles
    }
}

struct SpaceFixtureWorkflowReadinessAggregateSnapshot:
    Equatable
{
    let observationGeneration: Int
    let expectedWorkflowAppIDs: [String]
    let configuredEvidenceByWorkflowAppID:
        [String: SpaceFixtureWorkflowReadinessEvidence]
    let readyEvidenceByWorkflowAppID:
        [String: SpaceFixtureWorkflowReadinessEvidence]
    let lastEvidenceByWorkflowAppID:
        [String: SpaceFixtureWorkflowReadinessEvidence]

    var isReady: Bool {
        readyEvidenceByWorkflowAppID.count
            == expectedWorkflowAppIDs.count
            && expectedWorkflowAppIDs.allSatisfy {
                readyEvidenceByWorkflowAppID[$0] != nil
            }
    }

    var unmetConditions: [String] {
        expectedWorkflowAppIDs.compactMap {
            workflowAppID in
            if configuredEvidenceByWorkflowAppID[
                workflowAppID
            ] == nil {
                return "\(workflowAppID).configured"
            }
            if readyEvidenceByWorkflowAppID[
                workflowAppID
            ] == nil {
                return "\(workflowAppID).ready"
            }
            return nil
        }
    }

    var logFields: String {
        "observationGeneration=\(observationGeneration) "
            + "expectedApps=\(list(expectedWorkflowAppIDs)) "
            + "configuredApps="
            + "\(list(configuredEvidenceByWorkflowAppID.keys.sorted())) "
            + "readyApps="
            + "\(list(readyEvidenceByWorkflowAppID.keys.sorted())) "
            + "unmet=\(list(unmetConditions)) "
            + "last={\(lastEvidenceFields)}"
    }

    private var lastEvidenceFields: String {
        expectedWorkflowAppIDs.map {
            workflowAppID in
            let fields =
                lastEvidenceByWorkflowAppID[workflowAppID]?
                    .logFields
                ?? "unobserved"
            return "\(workflowAppID):{\(fields)}"
        }
        .joined(separator: " | ")
    }

    private func list<S: Sequence>(
        _ values: S
    ) -> String where S.Element == String {
        "[" + values.joined(separator: ",") + "]"
    }
}

final class SpaceFixtureWorkflowReadinessAggregateOwner {
    typealias ReadyHandler = (
        SpaceFixtureWorkflowReadinessAggregateSnapshot
    ) -> Void

    private struct EntryState {
        let expectation:
            SpaceFixtureWorkflowReadinessAggregateExpectation
        var configuredEvidence:
            SpaceFixtureWorkflowReadinessEvidence?
        var readyEvidence:
            SpaceFixtureWorkflowReadinessEvidence?
        var pendingReadyEvidence:
            [SpaceFixtureWorkflowReadinessEvidence] = []
        var lastEvidence:
            SpaceFixtureWorkflowReadinessEvidence?
    }

    private struct ActiveObservation {
        let observationGeneration: Int
        let workflowAppIDs: [String]
        let onReady: ReadyHandler
        var entries: [String: EntryState]
    }

    private var active: ActiveObservation?

    private(set) var observationGeneration = 0
    private(set) var lastSnapshot:
        SpaceFixtureWorkflowReadinessAggregateSnapshot?

    var isObserving: Bool {
        active != nil
    }

    @discardableResult
    func start(
        expectations:
            [SpaceFixtureWorkflowReadinessAggregateExpectation],
        onReady: @escaping ReadyHandler
    ) -> Int {
        precondition(!expectations.isEmpty)
        let workflowAppIDs =
            expectations.map(\.workflowAppID)
        precondition(
            Set(workflowAppIDs).count == workflowAppIDs.count
        )
        cancel(invalidate: false)
        observationGeneration += 1
        let generation = observationGeneration
        let observation = ActiveObservation(
            observationGeneration: generation,
            workflowAppIDs: workflowAppIDs,
            onReady: onReady,
            entries: Dictionary(
                uniqueKeysWithValues:
                    expectations.map {
                        (
                            $0.workflowAppID,
                            EntryState(expectation: $0)
                        )
                    }
            )
        )
        active = observation
        lastSnapshot = snapshot(for: observation)
        return generation
    }

    func observe(
        _ evidence: SpaceFixtureWorkflowReadinessEvidence,
        for workflowAppID: String,
        observationGeneration: Int
    ) {
        guard var current = matchingActive(
            observationGeneration
        ), var entry = current.entries[workflowAppID]
        else {
            return
        }
        entry.lastEvidence = evidence
        if matchesStaticExpectation(
            evidence,
            expectation: entry.expectation
        ) {
            switch evidence.stage {
            case .configured:
                observeConfigured(
                    evidence,
                    entry: &entry
                )
            case .ready:
                observeReady(
                    evidence,
                    entry: &entry
                )
            case .windowTopology,
                 .fullscreenTopology,
                 .desktopPresentation,
                 .applicationAXExposure:
                break
            }
        }
        current.entries[workflowAppID] = entry
        active = current
        let currentSnapshot = snapshot(for: current)
        lastSnapshot = currentSnapshot
        guard currentSnapshot.isReady else { return }
        active = nil
        current.onReady(currentSnapshot)
    }

    func cancel(invalidate: Bool = true) {
        let hadActiveObservation = active != nil
        active = nil
        if invalidate && hadActiveObservation {
            observationGeneration += 1
        }
    }

    private func observeConfigured(
        _ evidence: SpaceFixtureWorkflowReadinessEvidence,
        entry: inout EntryState
    ) {
        guard entry.configuredEvidence == nil,
              evidence.snapshot
                .observedWindowPlanIndices.isEmpty,
              evidence.snapshot
                .completedFullscreenWindowPlanIndices.isEmpty
        else {
            return
        }
        entry.configuredEvidence = evidence
        let matchingReadyEvidence =
            entry.pendingReadyEvidence.filter {
                candidate in
                matchesBaseline(
                    candidate,
                    configuredEvidence: evidence
                )
            }
        if let readyEvidence = matchingReadyEvidence.max(
            by: { lhs, rhs in
                lhs.transitionGeneration
                    < rhs.transitionGeneration
            }
        ) {
            entry.readyEvidence = readyEvidence
        }
        entry.pendingReadyEvidence.removeAll()
    }

    private func observeReady(
        _ evidence: SpaceFixtureWorkflowReadinessEvidence,
        entry: inout EntryState
    ) {
        guard evidence.snapshot.isReady,
              entry.readyEvidence == nil
        else {
            return
        }
        guard let configuredEvidence =
                entry.configuredEvidence
        else {
            if !entry.pendingReadyEvidence.contains(evidence) {
                entry.pendingReadyEvidence.append(evidence)
            }
            return
        }
        if matchesBaseline(
            evidence,
            configuredEvidence: configuredEvidence
        ) {
            entry.readyEvidence = evidence
        }
    }

    private func matchesStaticExpectation(
        _ evidence: SpaceFixtureWorkflowReadinessEvidence,
        expectation:
            SpaceFixtureWorkflowReadinessAggregateExpectation
    ) -> Bool {
        evidence.identity.bundleIdentifier
            == expectation.bundleIdentifier
            && evidence.snapshot.expectedWindowPlanIndices
                == expectation.windowPlanIndices
            && evidence.snapshot
                .expectedFullscreenWindowPlanIndices
                == expectation.fullscreenWindowPlanIndices
            && evidence.snapshot.windowTitles
                == expectation.windowTitles
    }

    private func matchesBaseline(
        _ evidence: SpaceFixtureWorkflowReadinessEvidence,
        configuredEvidence:
            SpaceFixtureWorkflowReadinessEvidence
    ) -> Bool {
        evidence.identity == configuredEvidence.identity
            && evidence.observationGeneration
                == configuredEvidence.observationGeneration
            && evidence.transitionGeneration
                > configuredEvidence.transitionGeneration
            && evidence.snapshot.windowTitles
                == configuredEvidence.snapshot.windowTitles
    }

    private func matchingActive(
        _ observationGeneration: Int
    ) -> ActiveObservation? {
        guard let active,
              active.observationGeneration
                == observationGeneration
        else {
            return nil
        }
        return active
    }

    private func snapshot(
        for active: ActiveObservation
    ) -> SpaceFixtureWorkflowReadinessAggregateSnapshot {
        SpaceFixtureWorkflowReadinessAggregateSnapshot(
            observationGeneration:
                active.observationGeneration,
            expectedWorkflowAppIDs:
                active.workflowAppIDs,
            configuredEvidenceByWorkflowAppID:
                active.entries.compactMapValues(
                    \.configuredEvidence
                ),
            readyEvidenceByWorkflowAppID:
                active.entries.compactMapValues(
                    \.readyEvidence
                ),
            lastEvidenceByWorkflowAppID:
                active.entries.compactMapValues(
                    \.lastEvidence
                )
        )
    }
}
