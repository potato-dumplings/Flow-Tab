import XCTest

private enum FlowTabUITestSettingsDropdownOptionObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 200
}

extension FlowTabUITests {
    func testSettingsDropdownOptionWatchdogPolicyPreservesCombinedCompatibilityBound() {
        XCTAssertEqual(
            FlowTabUITestSettingsDropdownOptionWatchdogPolicy.projection,
            5
        )
        XCTAssertTrue(
            FlowTabUITestSettingsDropdownOptionWatchdogPolicy
                .projection.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSettingsDropdownOptionWatchdogPolicy.projection,
            0
        )
    }

    func testSettingsDropdownOptionObservationUsesPostTriggerScopedPriority() {
        var scheduledRegistrationCount = 0
        let snapshot = FlowTabUITestSettingsDropdownOptionSnapshot(
            scopedElement: "scoped",
            rawElement: "raw"
        )
        let owner =
            FlowTabUITestSettingsDropdownOptionObservationOwner(
                scopedIdentifier: "control.option.space",
                rawIdentifier: "space",
                scheduledRegistration: { _ in
                    scheduledRegistrationCount += 1
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)

        owner.markTriggerCompleted()
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsDropdownOptionObservationTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value.selectedIdentity, .scoped)
        XCTAssertEqual(evidence?.value.selectedElement, "scoped")
        XCTAssertEqual(scheduledRegistrationCount, 0)
    }

    func testSettingsDropdownOptionObservationPreservesRawIdentityFallback() {
        var snapshot = FlowTabUITestSettingsDropdownOptionSnapshot<String>(
            scopedElement: nil,
            rawElement: nil
        )
        let owner =
            FlowTabUITestSettingsDropdownOptionObservationOwner(
                scopedIdentifier: "control.option.space",
                rawIdentifier: "space",
                scheduledRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        snapshot = FlowTabUITestSettingsDropdownOptionSnapshot(
            scopedElement: nil,
            rawElement: "raw"
        )
        owner.markTriggerCompleted()

        XCTAssertEqual(
            owner.resolvedEvidence?.value.selectedIdentity,
            .raw
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.selectedElement,
            "raw"
        )
    }

    func testSettingsDropdownOptionObservationUsesDelayedEvidenceWithoutChangingPriority() {
        var snapshot = FlowTabUITestSettingsDropdownOptionSnapshot<String>(
            scopedElement: nil,
            rawElement: nil
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsDropdownOptionObservationOwner(
                scopedIdentifier: "control.option.space",
                rawIdentifier: "space",
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        owner.markTriggerCompleted()
        XCTAssertNotNil(scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = FlowTabUITestSettingsDropdownOptionSnapshot(
            scopedElement: "scoped",
            rawElement: "raw"
        )
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.selectedIdentity,
            .scoped
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSettingsDropdownOptionObservationCancellationRejectsLateEvidence() {
        var snapshot = FlowTabUITestSettingsDropdownOptionSnapshot<String>(
            scopedElement: nil,
            rawElement: nil
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsDropdownOptionObservationOwner(
                scopedIdentifier: "control.option.space",
                rawIdentifier: "space",
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        owner.markTriggerCompleted()
        owner.cancel()

        snapshot = FlowTabUITestSettingsDropdownOptionSnapshot(
            scopedElement: "scoped",
            rawElement: "raw"
        )
        scheduledReadback?(.scheduledReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSettingsDropdownOptionObservationWatchdogReportsFinalReadback() {
        var readbackCount = 0
        let owner =
            FlowTabUITestSettingsDropdownOptionObservationOwner(
                scopedIdentifier: "control.option.space",
                rawIdentifier: "space",
                scheduledRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                },
                readback: {
                    defer { readbackCount += 1 }
                    let scopedElement =
                        readbackCount >= 2 ? "scoped" : nil
                    return FlowTabUITestSettingsDropdownOptionSnapshot(
                        scopedElement: scopedElement,
                        rawElement: nil
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markTriggerCompleted()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsDropdownOptionObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("scopedExists=1")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "selectedIdentity=scoped"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("waitResult=")
        )
    }

    func testSettingsDropdownOptionObservationRejectsReplacedEvidenceUnderPressure() {
        for _ in 0..<FlowTabUITestSettingsDropdownOptionObservationTestPolicy
            .pressureIterations
        {
            var snapshot =
                FlowTabUITestSettingsDropdownOptionSnapshot<String>(
                    scopedElement: nil,
                    rawElement: nil
                )
            var scheduledReadbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner =
                FlowTabUITestSettingsDropdownOptionObservationOwner(
                    scopedIdentifier: "control.option.space",
                    rawIdentifier: "space",
                    scheduledRegistration: { callback in
                        scheduledReadbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: { snapshot }
                )

            owner.start()
            owner.markTriggerCompleted()
            owner.markTriggerCompleted()
            XCTAssertEqual(scheduledReadbacks.count, 1)
            let staleReadback = scheduledReadbacks[0]

            owner.cancel()
            owner.start()
            owner.markTriggerCompleted()
            XCTAssertEqual(scheduledReadbacks.count, 2)
            let currentReadback = scheduledReadbacks[1]

            snapshot = FlowTabUITestSettingsDropdownOptionSnapshot(
                scopedElement: "scoped",
                rawElement: "raw"
            )
            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            currentReadback(.scheduledReadback)
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            XCTAssertEqual(
                owner.resolvedEvidence?.value.selectedIdentity,
                .scoped
            )
            owner.cancel()
        }
    }
}
