import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testManualWindowLayerEntryTreatsInitiallyCompleteProjectionAsRequestBaseline() {
        let owner = ManualWindowLayerEntryObservationOwner()
        let baselineGeneration = RuntimeReadModelGeneration(
            space: 7,
            projection: 11
        )
        var snapshot = Self.manualWindowLayerSnapshot(
            projection: Self.manualWindowLayerProjection(
                windowIDs: ["normal", "fullscreen"],
                generation: baselineGeneration,
                isCompleteForScope: true
            )
        )
        var completions: [ManualWindowLayerEntryEvidence] = []

        let generation = owner.start(
            targetAppID: "app-a",
            targetPID: 4_201,
            presentationGeneration: 13,
            readback: { snapshot },
            onSettled: { completions.append($0) }
        )

        XCTAssertTrue(completions.isEmpty)
        XCTAssertTrue(owner.isObserving)
        snapshot = Self.manualWindowLayerSnapshot(
            projection: Self.manualWindowLayerProjection(
                windowIDs: ["fullscreen", "normal"],
                generation: RuntimeReadModelGeneration(
                    space: 8,
                    projection: 12
                ),
                isCompleteForScope: true
            )
        )

        XCTAssertTrue(
            owner.observe(
                source: .projectionRequestReturnReadback,
                observationGeneration: generation,
                presentationGeneration: 13
            )
        )
        XCTAssertEqual(
            completions.map(\.source),
            [.projectionRequestReturnReadback]
        )
        XCTAssertEqual(
            completions.first?.snapshot.projection?.windowIDs,
            ["fullscreen", "normal"]
        )
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testManualWindowLayerEntryWaitsForLaterCompleteProjection() {
        let owner = ManualWindowLayerEntryObservationOwner()
        var snapshot = Self.manualWindowLayerSnapshot(
            projection: Self.manualWindowLayerProjection(
                windowIDs: ["normal", "fullscreen"],
                generation: RuntimeReadModelGeneration(
                    space: 17,
                    projection: 23
                ),
                isCompleteForScope: false
            )
        )
        var completions: [ManualWindowLayerEntryEvidence] = []
        let generation = owner.start(
            targetAppID: "app-a",
            targetPID: 4_201,
            presentationGeneration: 13,
            readback: { snapshot },
            onSettled: { completions.append($0) }
        )

        XCTAssertTrue(owner.isObserving)
        XCTAssertTrue(completions.isEmpty)
        snapshot = Self.manualWindowLayerSnapshot(
            selectedWindowIDs: ["normal", "fullscreen"],
            projection: Self.manualWindowLayerProjection(
                windowIDs: ["fullscreen", "normal"],
                generation: RuntimeReadModelGeneration(
                    space: 18,
                    projection: 24
                ),
                isCompleteForScope: true
            )
        )

        XCTAssertTrue(
            owner.observe(
                source: .projectionRequestReturnReadback,
                observationGeneration: generation,
                presentationGeneration: 13
            )
        )
        XCTAssertEqual(
            completions.map(\.source),
            [.projectionRequestReturnReadback]
        )
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testManualWindowLayerEntryRejectsUnrelatedStaleAndDuplicateEvents() {
        let owner = ManualWindowLayerEntryObservationOwner()
        let baselineGeneration = RuntimeReadModelGeneration(
            space: 31,
            projection: 37
        )
        var snapshot = Self.manualWindowLayerSnapshot(
            projection: Self.manualWindowLayerProjection(
                windowIDs: ["normal", "fullscreen"],
                generation: baselineGeneration,
                isCompleteForScope: false
            )
        )
        var completions: [ManualWindowLayerEntryEvidence] = []
        let generation = owner.start(
            targetAppID: "app-a",
            targetPID: 4_201,
            presentationGeneration: 13,
            readback: { snapshot },
            onSettled: { completions.append($0) }
        )
        let staleEvent = RuntimeCurrentAppWindowProjectionUpdateEvidence(
            appID: "app-a",
            processIdentifier: 4_201,
            windowIDs: ["normal", "fullscreen"],
            isCompleteForScope: true,
            sourceGeneration: baselineGeneration
        )

        XCTAssertFalse(
            owner.observe(
                source: .currentAppWindowProjectionUpdated,
                eventAppID: "app-b",
                eventEvidence: staleEvent,
                observationGeneration: generation,
                presentationGeneration: 13
            )
        )
        XCTAssertFalse(
            owner.observe(
                source: .currentAppWindowProjectionUpdated,
                eventAppID: "app-a",
                eventEvidence: RuntimeCurrentAppWindowProjectionUpdateEvidence(
                    appID: "app-a",
                    processIdentifier: 4_202,
                    windowIDs: ["fullscreen", "normal"],
                    isCompleteForScope: true,
                    sourceGeneration: RuntimeReadModelGeneration(
                        space: 32,
                        projection: 38
                    )
                ),
                observationGeneration: generation,
                presentationGeneration: 13
            )
        )
        XCTAssertFalse(
            owner.observe(
                source: .currentAppWindowProjectionUpdated,
                eventAppID: "app-a",
                eventEvidence: staleEvent,
                observationGeneration: generation,
                presentationGeneration: 13
            )
        )
        XCTAssertTrue(completions.isEmpty)

        let laterGeneration = RuntimeReadModelGeneration(
            space: 32,
            projection: 38
        )
        snapshot = Self.manualWindowLayerSnapshot(
            selectedWindowIDs: ["normal", "fullscreen"],
            projection: Self.manualWindowLayerProjection(
                windowIDs: ["fullscreen", "normal"],
                generation: laterGeneration,
                isCompleteForScope: true
            )
        )
        let laterEvent = RuntimeCurrentAppWindowProjectionUpdateEvidence(
            appID: "app-a",
            processIdentifier: 4_201,
            windowIDs: ["fullscreen", "normal"],
            isCompleteForScope: true,
            sourceGeneration: laterGeneration
        )

        XCTAssertTrue(
            owner.observe(
                source: .currentAppWindowProjectionUpdated,
                eventAppID: "app-a",
                eventEvidence: laterEvent,
                observationGeneration: generation,
                presentationGeneration: 13
            )
        )
        XCTAssertFalse(
            owner.observe(
                source: .currentAppWindowProjectionUpdated,
                eventAppID: "app-a",
                eventEvidence: laterEvent,
                observationGeneration: generation,
                presentationGeneration: 13
            )
        )
        XCTAssertEqual(completions.count, 1)
    }

    @MainActor
    func testManualWindowLayerEntryRequiresPostRequestExactProjection() {
        let owner = ManualWindowLayerEntryObservationOwner()
        let baselineGeneration = RuntimeReadModelGeneration(
            projection: 41
        )
        var snapshot = Self.manualWindowLayerSnapshot(
            readModelGeneration: baselineGeneration,
            projection: nil
        )
        var completionCount = 0
        let generation = owner.start(
            targetAppID: "app-a",
            targetPID: 4_201,
            presentationGeneration: 13,
            readback: { snapshot },
            onSettled: { _ in completionCount += 1 }
        )

        XCTAssertTrue(owner.isObserving)
        XCTAssertEqual(completionCount, 0)
        XCTAssertFalse(
            owner.observe(
                source: .projectionRequestReturnReadback,
                observationGeneration: generation,
                presentationGeneration: 13
            )
        )
        snapshot = Self.manualWindowLayerSnapshot(
            selectedWindowIDs: ["normal", "fullscreen"],
            projection: Self.manualWindowLayerProjection(
                windowIDs: ["fullscreen", "normal"],
                generation: RuntimeReadModelGeneration(projection: 42),
                isCompleteForScope: true
            )
        )

        XCTAssertTrue(
            owner.observe(
                source: .projectionRequestReturnReadback,
                observationGeneration: generation,
                presentationGeneration: 13
            )
        )
        XCTAssertEqual(completionCount, 1)
    }

    @MainActor
    func testManualWindowLayerEntryReplacementAndCancellationPressure() {
        let owner = ManualWindowLayerEntryObservationOwner()
        var completionCount = 0

        for index in 0..<2_000 {
            let appID = "app-\(index)"
            let snapshot = Self.manualWindowLayerSnapshot(
                appID: appID,
                pid: pid_t(5_000 + index),
                presentationGeneration: index,
                projection: Self.manualWindowLayerProjection(
                    appID: appID,
                    pid: pid_t(5_000 + index),
                    windowIDs: ["window-\(index)"],
                    generation: RuntimeReadModelGeneration(
                        projection: UInt64(index)
                    ),
                    isCompleteForScope: false
                )
            )
            _ = owner.start(
                targetAppID: appID,
                targetPID: pid_t(5_000 + index),
                presentationGeneration: index,
                readback: { snapshot },
                onSettled: { _ in completionCount += 1 }
            )
        }

        XCTAssertTrue(owner.isObserving)
        owner.cancel()
        XCTAssertFalse(owner.isObserving)
        XCTAssertEqual(completionCount, 0)
    }

    private static func manualWindowLayerSnapshot(
        appID: String = "app-a",
        pid: pid_t = 4_201,
        selectedWindowIDs: [String] = ["normal", "fullscreen"],
        readModelGeneration: RuntimeReadModelGeneration? = nil,
        presentationGeneration: Int = 13,
        projection: ManualWindowLayerProjectionReadback?
    ) -> ManualWindowLayerEntrySnapshot {
        ManualWindowLayerEntrySnapshot(
            readModelGeneration:
                readModelGeneration
                    ?? projection?.sourceGeneration
                    ?? RuntimeReadModelGeneration(),
            presentationGeneration: presentationGeneration,
            selectedAppID: appID,
            selectedAppPID: pid,
            selectedWindowIDs: selectedWindowIDs,
            isPanelPresented: true,
            isAppLayer: true,
            isSearchActive: false,
            projection: projection
        )
    }

    private static func manualWindowLayerProjection(
        appID: String = "app-a",
        pid: pid_t = 4_201,
        windowIDs: [String],
        generation: RuntimeReadModelGeneration,
        isCompleteForScope: Bool
    ) -> ManualWindowLayerProjectionReadback {
        ManualWindowLayerProjectionReadback(
            appID: appID,
            processIdentifier: pid,
            windowIDs: windowIDs,
            sourceGeneration: generation,
            isCompleteForScope: isCompleteForScope
        )
    }
}
