import XCTest
@testable import FlowTab

private enum FlowTabUITestSearchTriggerPresentationTestPolicy {
    static let pressureIterations = 100
}

@MainActor
private final class ManualSearchTriggerPresentationRegistration {
    @MainActor
    final class Token:
        FlowTabUITestInitialPresentationCancellable
    {
        private(set) var isCancelled = false

        func cancel() {
            isCancelled = true
        }
    }

    private(set) var callbacks: [
        @MainActor (
            FlowTabUITestSearchTriggerPresentationEvidenceSource
        ) -> Void
    ] = []
    private(set) var tokens: [Token] = []

    func register(
        _ callback:
            @escaping @MainActor (
                FlowTabUITestSearchTriggerPresentationEvidenceSource
            ) -> Void
    ) -> any FlowTabUITestInitialPresentationCancellable {
        let token = Token()
        callbacks.append(callback)
        tokens.append(token)
        return token
    }
}

extension FlowTabTests {
    @MainActor
    func testSearchTriggerPresentationAcceptsSatisfiedInitialReadback() {
        let registration =
            ManualSearchTriggerPresentationRegistration()
        var resolution:
            FlowTabUITestSearchTriggerPresentationEvidence?
        let owner =
            FlowTabUITestSearchTriggerPresentationObservationOwner(
                observationRegistration: registration.register,
                readback: {
                    XCTAssertEqual(
                        registration.callbacks.count,
                        1,
                        "Observation must precede initial readback"
                    )
                    return self.searchTriggerPresentationSnapshot(
                        panelIsPresented: true,
                        panelIsKey: true,
                        searchIsActive: true
                    )
                }
            )

        let generation = owner.start {
            resolution = $0
        }

        XCTAssertEqual(generation, 1)
        XCTAssertEqual(resolution?.source, .initialReadback)
        XCTAssertEqual(resolution?.evidenceGeneration, 0)
        XCTAssertTrue(registration.tokens[0].isCancelled)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testSearchTriggerPresentationAcceptsSynchronousTriggerReadback() {
        let registration =
            ManualSearchTriggerPresentationRegistration()
        var snapshot = searchTriggerPresentationSnapshot()
        var resolution:
            FlowTabUITestSearchTriggerPresentationEvidence?
        let owner =
            FlowTabUITestSearchTriggerPresentationObservationOwner(
                observationRegistration: registration.register,
                readback: { snapshot }
            )
        let generation = owner.start {
            resolution = $0
        }

        snapshot = searchTriggerPresentationSnapshot(
            panelIsPresented: true,
            panelIsKey: true,
            searchIsActive: true
        )

        XCTAssertTrue(
            owner.observe(
                .triggerReadback,
                generation: generation
            )
        )
        XCTAssertEqual(resolution?.source, .triggerReadback)
        XCTAssertEqual(resolution?.evidenceGeneration, 1)
        XCTAssertTrue(registration.tokens[0].isCancelled)
    }

    @MainActor
    func testSearchTriggerPresentationResolvesDeferredPanelThenSearchEvents() {
        let registration =
            ManualSearchTriggerPresentationRegistration()
        var snapshot = searchTriggerPresentationSnapshot()
        var resolution:
            FlowTabUITestSearchTriggerPresentationEvidence?
        let owner =
            FlowTabUITestSearchTriggerPresentationObservationOwner(
                observationRegistration: registration.register,
                readback: { snapshot }
            )
        let generation = owner.start {
            resolution = $0
        }

        snapshot = searchTriggerPresentationSnapshot(
            searchActivationIsPending: true
        )
        XCTAssertFalse(
            owner.observe(
                .triggerReadback,
                generation: generation
            )
        )
        XCTAssertTrue(
            owner.lastEvidence?.logFields.contains(
                "searchPending=1"
            ) == true
        )

        snapshot = searchTriggerPresentationSnapshot(
            panelIsPresented: true,
            panelIsKey: true,
            searchActivationIsPending: true
        )
        registration.callbacks[0](.panelDidBecomeKey)
        XCTAssertNil(resolution)

        snapshot = searchTriggerPresentationSnapshot(
            panelIsPresented: true,
            panelIsKey: true,
            searchIsActive: true
        )
        registration.callbacks[0](.searchStateDidChange)

        XCTAssertEqual(
            resolution?.source,
            .searchStateDidChange
        )
        XCTAssertEqual(resolution?.evidenceGeneration, 3)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testSearchTriggerPresentationResolvesDeferredSearchThenPanelEvents() {
        let registration =
            ManualSearchTriggerPresentationRegistration()
        var snapshot = searchTriggerPresentationSnapshot(
            searchActivationIsPending: true
        )
        var resolution:
            FlowTabUITestSearchTriggerPresentationEvidence?
        let owner =
            FlowTabUITestSearchTriggerPresentationObservationOwner(
                observationRegistration: registration.register,
                readback: { snapshot }
            )
        owner.start {
            resolution = $0
        }

        snapshot = searchTriggerPresentationSnapshot(
            searchIsActive: true
        )
        registration.callbacks[0](.searchStateDidChange)
        XCTAssertNil(resolution)

        snapshot = searchTriggerPresentationSnapshot(
            panelIsPresented: true,
            panelIsKey: true,
            searchIsActive: true
        )
        registration.callbacks[0](.panelDidExpose)

        XCTAssertEqual(resolution?.source, .panelDidExpose)
        XCTAssertEqual(
            resolution?.snapshot.panelIsPresented,
            true
        )
        XCTAssertEqual(resolution?.snapshot.panelIsKey, true)
    }

    @MainActor
    func testSearchTriggerPresentationRejectsStaleAndDuplicateEventsUnderPressure() {
        let registration =
            ManualSearchTriggerPresentationRegistration()
        var snapshot = searchTriggerPresentationSnapshot()
        var readbackCount = 0
        var resolutionCount = 0
        let owner =
            FlowTabUITestSearchTriggerPresentationObservationOwner(
                observationRegistration: registration.register,
                readback: {
                    readbackCount += 1
                    return snapshot
                }
            )

        for iteration in
            0..<FlowTabUITestSearchTriggerPresentationTestPolicy
                .pressureIterations
        {
            owner.start { _ in
                XCTFail(
                    "Cancelled generation resolved iteration=\(iteration)"
                )
            }
            let staleCallback = registration.callbacks.last!
            let staleToken = registration.tokens.last!
            owner.cancel()
            XCTAssertTrue(staleToken.isCancelled)

            owner.start { _ in
                resolutionCount += 1
            }
            let currentCallback = registration.callbacks.last!
            let currentToken = registration.tokens.last!
            snapshot = self.searchTriggerPresentationSnapshot(
                panelIsPresented: true,
                panelIsKey: true,
                searchIsActive: true
            )
            let readbackBaseline = readbackCount
            staleCallback(.panelDidBecomeKey)
            XCTAssertEqual(
                readbackCount,
                readbackBaseline,
                "iteration=\(iteration)"
            )

            currentCallback(.panelDidBecomeKey)
            XCTAssertEqual(
                resolutionCount,
                iteration + 1
            )
            XCTAssertTrue(currentToken.isCancelled)
            let resolvedReadbackCount = readbackCount
            currentCallback(.searchStateDidChange)
            XCTAssertEqual(
                readbackCount,
                resolvedReadbackCount,
                "iteration=\(iteration)"
            )
            snapshot = self.searchTriggerPresentationSnapshot()
        }
    }

    private func searchTriggerPresentationSnapshot(
        panelIsPresented: Bool = false,
        panelIsKey: Bool = false,
        searchIsActive: Bool = false,
        searchActivationIsPending: Bool = false
    ) -> FlowTabUITestSearchTriggerPresentationSnapshot {
        FlowTabUITestSearchTriggerPresentationSnapshot(
            panelIsPresented: panelIsPresented,
            panelIsKey: panelIsKey,
            searchIsActive: searchIsActive,
            searchActivationIsPending:
                searchActivationIsPending
        )
    }
}
