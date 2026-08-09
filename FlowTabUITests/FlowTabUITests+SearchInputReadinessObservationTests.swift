import XCTest

private enum FlowTabUITestSearchInputReadinessObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSearchInputReadinessPolicyEnablesPersistedEvidenceChannel() {
        XCTAssertEqual(
            FlowTabUITestSearchInputReadinessPolicy
                .applicationEvidenceLaunchArguments,
            [
                "--flowtab-ui-runtime-log-level",
                "INFO",
                "--flowtab-ui-enable-verbose-logs"
            ]
        )
    }

    func testSearchInputReadinessUsesInitialKeyboardEvidenceReadback() {
        var registrationOrder: [String] = []
        let owner =
            FlowTabUITestSearchInputReadinessObservationOwner(
                observationRegistration: { _ in
                    registrationOrder.append("observer")
                    return FlowTabUITestObservationCancellation {
                        registrationOrder.append("cancel")
                    }
                },
                readback: {
                    registrationOrder.append("readback")
                    return self.searchInputReadinessSnapshot(
                        contents:
                            FlowTabUITestSearchInputReadinessEvidence
                                .keyboardReadyMarker
                    )
                }
            )

        owner.start()
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSearchInputReadinessObservationTestPolicy
                    .watchdog
        )

        XCTAssertEqual(
            registrationOrder,
            ["observer", "readback", "cancel"]
        )
        XCTAssertEqual(evidence?.source, .initialReadback)
        XCTAssertTrue(
            evidence?.value.contents.contains(
                FlowTabUITestSearchInputReadinessEvidence
                    .keyboardReadyMarker
            ) == true
        )
        owner.cancel()
    }

    func testSearchInputReadinessWaitsForKeyboardEvidenceEvent() {
        var eventHandler: (() -> Void)?
        var contents = "search input exists"
        let owner =
            FlowTabUITestSearchInputReadinessObservationOwner(
                observationRegistration: { callback in
                    eventHandler = {
                        callback(.notificationReadback)
                    }
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    self.searchInputReadinessSnapshot(
                        contents: contents
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        contents =
            FlowTabUITestSearchInputReadinessEvidence
                .keyboardReadyMarker
        eventHandler?()

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSearchInputReadinessObservationTestPolicy
                    .watchdog
        )
        XCTAssertEqual(evidence?.source, .notificationReadback)
    }

    func testSearchInputReadinessRejectsInexactKeyboardEvidence() {
        let inexactEvidence = [
            "keyboardReadiness ready=1 "
                + "identifier=other-input "
                + "responder=SearchSystemTextView "
                + "windowKey=1",
            "keyboardReadiness ready=1 "
                + "identifier=flowtab.switcher.search.input "
                + "responder=NSView "
                + "windowKey=1",
            "keyboardReadiness ready=1 "
                + "identifier=flowtab.switcher.search.input "
                + "responder=SearchSystemTextView "
                + "windowKey=0"
        ]

        for contents in inexactEvidence {
            let owner =
                FlowTabUITestSearchInputReadinessObservationOwner(
                    observationRegistration: nil,
                    readback: {
                        self.searchInputReadinessSnapshot(
                            contents: contents
                        )
                    }
                )
            owner.start()
            XCTAssertNil(owner.resolvedEvidence)
            owner.cancel()
        }
    }

    func testSearchInputReadinessRejectsCancelledAndDuplicateEvents() {
        for _ in
            0..<FlowTabUITestSearchInputReadinessObservationTestPolicy
                .pressureIterations
        {
            var eventHandlers: [() -> Void] = []
            var contents = ""
            let owner =
                FlowTabUITestSearchInputReadinessObservationOwner(
                    observationRegistration: { callback in
                        eventHandlers.append {
                            callback(.notificationReadback)
                        }
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: {
                        self.searchInputReadinessSnapshot(
                            contents: contents
                        )
                    }
                )

            owner.start()
            let staleHandler = eventHandlers[0]
            owner.cancel()
            owner.start()
            contents =
                FlowTabUITestSearchInputReadinessEvidence
                    .keyboardReadyMarker
            staleHandler()
            XCTAssertNil(owner.resolvedEvidence)

            let currentHandler = eventHandlers[1]
            currentHandler()
            currentHandler()
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            XCTAssertEqual(
                owner.resolvedEvidence?.source,
                .notificationReadback
            )
            owner.cancel()
        }
    }

    func testSearchInputReadinessWatchdogReportsLastEvidence() {
        let owner =
            FlowTabUITestSearchInputReadinessObservationOwner(
                observationRegistration: nil,
                readback: {
                    self.searchInputReadinessSnapshot(
                        contents:
                            "keyboardReadiness ready=0 "
                            + "identifier=flowtab.switcher.search.input"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSearchInputReadinessObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "missingMarkers="
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "keyboardReadiness ready=0"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
    }

    private func searchInputReadinessSnapshot(
        contents: String
    ) -> FlowTabUITestRuntimeLogSnapshot {
        FlowTabUITestRuntimeLogSnapshot(
            baselineFileEventGeneration: 4,
            fileEventGeneration: 5,
            contents: contents
        )
    }
}
