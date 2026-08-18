import CoreGraphics
import Foundation
import XCTest

private enum FlowTabUITestInAppConfirmationObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testInAppConfirmationPolicyPreservesCompatibleWatchdogs() {
        XCTAssertEqual(
            FlowTabUITestInAppConfirmationObservationPolicy
                .panelDismissalWatchdog,
            4
        )
        XCTAssertEqual(
            FlowTabUITestInAppConfirmationObservationPolicy
                .exactWindowActivationWatchdog,
            12
        )
    }

    func testInAppConfirmationRejectsInitiallyActiveSelectedWindow() {
        var panelExists = true
        var activation = inAppConfirmationActivationSnapshot(
            bundleIdentifier: "com.example.target",
            windowNumber: 42,
            title: "Draft"
        )
        var panelReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var activationReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner = FlowTabUITestInAppConfirmationObservationOwner(
            expectedBundleIdentifier: "com.example.target",
            expectedWindowNumber: 42,
            expectedTitle: "Draft",
            panelElementIdentifier: "switcher-summary",
            panelScheduledRegistration: { callback in
                panelReadback = callback
                return FlowTabUITestObservationCancellation {}
            },
            activationObservationRegistration: { callback in
                activationReadback = callback
                return FlowTabUITestObservationCancellation {}
            },
            panelReadback: { panelExists },
            activationReadback: { activation }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.baselineIssue,
            .selectedWindowAlreadyActive
        )
        panelExists = false
        owner.markTriggerCompleted()
        panelReadback?(.scheduledReadback)
        activationReadback?(.notificationReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "baselineIssue=selectedWindowAlreadyActive"
            )
        )

        activation = inAppConfirmationActivationSnapshot(
            bundleIdentifier: "com.example.other",
            windowNumber: 41,
            title: "Other"
        )
        activationReadback?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)
    }

    func testInAppConfirmationRejectsInitiallyDismissedPanel() {
        let owner = FlowTabUITestInAppConfirmationObservationOwner(
            expectedBundleIdentifier: "com.example.target",
            expectedWindowNumber: 42,
            expectedTitle: "Draft",
            panelElementIdentifier: "switcher-summary",
            panelScheduledRegistration: { _ in
                FlowTabUITestObservationCancellation {}
            },
            activationObservationRegistration: nil,
            panelReadback: { false },
            activationReadback: {
                self.inAppConfirmationActivationSnapshot(
                    bundleIdentifier: "com.example.other",
                    windowNumber: 41,
                    title: "Other"
                )
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.baselineIssue,
            .panelAlreadyDismissed
        )
        owner.markTriggerCompleted()
        XCTAssertNil(owner.resolvedEvidence)
    }

    func testInAppConfirmationRequiresBothEvidenceObjectsAcrossEventOrder() {
        var panelExists = true
        var activation = inAppConfirmationActivationSnapshot(
            bundleIdentifier: "com.example.other",
            windowNumber: 41,
            title: "Other"
        )
        var panelReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var activationReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var panelCancellationCount = 0
        var activationCancellationCount = 0
        let owner = FlowTabUITestInAppConfirmationObservationOwner(
            expectedBundleIdentifier: "com.example.target",
            expectedWindowNumber: 42,
            expectedTitle: "Draft",
            panelElementIdentifier: "switcher-summary",
            panelScheduledRegistration: { callback in
                panelReadback = callback
                return FlowTabUITestObservationCancellation {
                    panelCancellationCount += 1
                }
            },
            activationObservationRegistration: { callback in
                activationReadback = callback
                return FlowTabUITestObservationCancellation {
                    activationCancellationCount += 1
                }
            },
            panelReadback: { panelExists },
            activationReadback: { activation }
        )
        owner.start()
        defer { owner.cancel() }
        XCTAssertNil(owner.baselineIssue)
        owner.markTriggerCompleted()

        activation = inAppConfirmationActivationSnapshot(
            bundleIdentifier: "com.example.other",
            windowNumber: 42,
            title: "Draft"
        )
        activationReadback?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)
        activation = inAppConfirmationActivationSnapshot(
            bundleIdentifier: "com.example.target",
            windowNumber: 41,
            title: "Draft"
        )
        activationReadback?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)

        activation = inAppConfirmationActivationSnapshot(
            bundleIdentifier: "com.example.target",
            windowNumber: 42,
            title: "Draft"
        )
        activationReadback?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(activationCancellationCount, 1)

        panelExists = false
        panelReadback?(.scheduledReadback)
        let evidence = owner.resolvedEvidence

        XCTAssertEqual(
            evidence?.activation.source,
            .notificationReadback
        )
        XCTAssertEqual(
            evidence?.dismissal.source,
            .scheduledReadback
        )
        XCTAssertEqual(panelCancellationCount, 1)
        activationReadback?(.notificationReadback)
        panelReadback?(.scheduledReadback)
        XCTAssertEqual(panelCancellationCount, 1)
        XCTAssertEqual(activationCancellationCount, 1)
    }

    func testInAppConfirmationTriggerReadbackClosesDeliveryRace() {
        var panelExists = true
        var activation = inAppConfirmationActivationSnapshot(
            bundleIdentifier: "com.example.other",
            windowNumber: 41,
            title: "Other"
        )
        var panelRegistrationCount = 0
        let owner = FlowTabUITestInAppConfirmationObservationOwner(
            expectedBundleIdentifier: "com.example.target",
            expectedWindowNumber: 42,
            expectedTitle: "Draft",
            panelElementIdentifier: "switcher-summary",
            panelScheduledRegistration: { _ in
                panelRegistrationCount += 1
                return FlowTabUITestObservationCancellation {}
            },
            activationObservationRegistration: { _ in
                FlowTabUITestObservationCancellation {}
            },
            panelReadback: { panelExists },
            activationReadback: { activation }
        )
        owner.start()
        defer { owner.cancel() }

        panelExists = false
        activation = inAppConfirmationActivationSnapshot(
            bundleIdentifier: "com.example.target",
            windowNumber: 42,
            title: "Draft"
        )
        owner.markTriggerCompleted()

        XCTAssertEqual(
            owner.resolvedEvidence?.dismissal.source,
            .triggerReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.activation.source,
            .triggerReadback
        )
        XCTAssertEqual(panelRegistrationCount, 0)
    }

    func testInAppConfirmationCancellationRejectsLateEvidence() {
        var panelExists = true
        var activation = inAppConfirmationActivationSnapshot(
            bundleIdentifier: "com.example.other",
            windowNumber: 41,
            title: "Other"
        )
        var panelReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var activationReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var panelCancellationCount = 0
        var activationCancellationCount = 0
        let owner = FlowTabUITestInAppConfirmationObservationOwner(
            expectedBundleIdentifier: "com.example.target",
            expectedWindowNumber: 42,
            expectedTitle: "Draft",
            panelElementIdentifier: "switcher-summary",
            panelScheduledRegistration: { callback in
                panelReadback = callback
                return FlowTabUITestObservationCancellation {
                    panelCancellationCount += 1
                }
            },
            activationObservationRegistration: { callback in
                activationReadback = callback
                return FlowTabUITestObservationCancellation {
                    activationCancellationCount += 1
                }
            },
            panelReadback: { panelExists },
            activationReadback: { activation }
        )
        owner.start()
        owner.markTriggerCompleted()
        owner.markTriggerCompleted()
        owner.cancel()

        panelExists = false
        activation = inAppConfirmationActivationSnapshot(
            bundleIdentifier: "com.example.target",
            windowNumber: 42,
            title: "Draft"
        )
        panelReadback?(.scheduledReadback)
        activationReadback?(.notificationReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(panelCancellationCount, 1)
        XCTAssertEqual(activationCancellationCount, 1)
        owner.cancel()
        XCTAssertEqual(panelCancellationCount, 1)
        XCTAssertEqual(activationCancellationCount, 1)
    }

    func testInAppConfirmationWatchdogReportsBothLastReadbacks() {
        var panelCancellationCount = 0
        var activationCancellationCount = 0
        let owner = FlowTabUITestInAppConfirmationObservationOwner(
            expectedBundleIdentifier: "com.example.target",
            expectedWindowNumber: 42,
            expectedTitle: "Draft",
            panelElementIdentifier: "switcher-summary",
            panelScheduledRegistration: { _ in
                FlowTabUITestObservationCancellation {
                    panelCancellationCount += 1
                }
            },
            activationObservationRegistration: { _ in
                FlowTabUITestObservationCancellation {
                    activationCancellationCount += 1
                }
            },
            panelReadback: { true },
            activationReadback: {
                self.inAppConfirmationActivationSnapshot(
                    bundleIdentifier: "com.example.other",
                    windowNumber: 41,
                    title: "Other"
                )
            }
        )
        owner.start()
        defer { owner.cancel() }
        owner.markTriggerCompleted()

        XCTAssertNil(
            owner.waitForResolution(
                panelDismissalTimeout:
                    FlowTabUITestInAppConfirmationObservationTestPolicy
                        .watchdog,
                exactWindowActivationTimeout:
                    FlowTabUITestInAppConfirmationObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "dismissal{elementIdentifier=switcher-summary"
            ),
            owner.diagnosticSummary
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("exists=1"),
            owner.diagnosticSummary
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "activation{generation="
            ),
            owner.diagnosticSummary
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "expectedWindowNumber=42"
            ),
            owner.diagnosticSummary
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "topmostCGWindow=41:"
            ),
            owner.diagnosticSummary
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "waitResult=timedOut"
            ),
            owner.diagnosticSummary
        )
        XCTAssertEqual(panelCancellationCount, 1)
        XCTAssertEqual(activationCancellationCount, 1)
    }

    func testInAppConfirmationLifecycleAndEventOrderUnderPressure() {
        for iteration in
            0..<FlowTabUITestInAppConfirmationObservationTestPolicy
                .pressureIterations
        {
            var panelExists = true
            var activation = inAppConfirmationActivationSnapshot(
                bundleIdentifier: "com.example.other",
                windowNumber: 41,
                title: "Other"
            )
            var panelReadbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var activationReadbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var panelCancellationCount = 0
            var activationCancellationCount = 0
            let owner =
                FlowTabUITestInAppConfirmationObservationOwner(
                    expectedBundleIdentifier:
                        "com.example.target",
                    expectedWindowNumber: 42,
                    expectedTitle: "Draft",
                    panelElementIdentifier:
                        "switcher-summary",
                    panelScheduledRegistration: { callback in
                        panelReadbacks.append(callback)
                        return FlowTabUITestObservationCancellation {
                            panelCancellationCount += 1
                        }
                    },
                    activationObservationRegistration: { callback in
                        activationReadbacks.append(callback)
                        return FlowTabUITestObservationCancellation {
                            activationCancellationCount += 1
                        }
                    },
                    panelReadback: { panelExists },
                    activationReadback: { activation }
                )

            owner.start()
            owner.markTriggerCompleted()
            let stalePanelReadback = panelReadbacks[0]
            let staleActivationReadback = activationReadbacks[0]
            owner.cancel()

            panelExists = true
            activation = inAppConfirmationActivationSnapshot(
                bundleIdentifier: "com.example.other",
                windowNumber: 41,
                title: "Other"
            )
            owner.start()
            owner.markTriggerCompleted()
            let currentPanelReadback = panelReadbacks[1]
            let currentActivationReadback =
                activationReadbacks[1]

            panelExists = false
            activation = inAppConfirmationActivationSnapshot(
                bundleIdentifier: "com.example.target",
                windowNumber: 42,
                title: "Draft"
            )
            stalePanelReadback(.scheduledReadback)
            staleActivationReadback(.notificationReadback)
            XCTAssertNil(owner.resolvedEvidence)

            if iteration.isMultiple(of: 2) {
                currentActivationReadback(.notificationReadback)
                XCTAssertNil(owner.resolvedEvidence)
                currentPanelReadback(.scheduledReadback)
            } else {
                currentPanelReadback(.scheduledReadback)
                XCTAssertNil(owner.resolvedEvidence)
                currentActivationReadback(.notificationReadback)
            }
            currentPanelReadback(.scheduledReadback)
            currentActivationReadback(.notificationReadback)

            XCTAssertNotNil(owner.resolvedEvidence)
            XCTAssertEqual(panelCancellationCount, 2)
            XCTAssertEqual(activationCancellationCount, 2)
            owner.cancel()
            stalePanelReadback(.scheduledReadback)
            staleActivationReadback(.notificationReadback)
            XCTAssertEqual(panelCancellationCount, 2)
            XCTAssertEqual(activationCancellationCount, 2)
        }
    }

    private func inAppConfirmationActivationSnapshot(
        bundleIdentifier: String?,
        windowNumber: CGWindowID?,
        title: String?
    ) -> FlowTabUITestWorkflowWindowActivationSnapshot {
        FlowTabUITestWorkflowWindowActivationSnapshot(
            frontmostBundleIdentifier: bundleIdentifier,
            topmostCGWindow: windowNumber.map {
                WorkflowCGWindowObservation(
                    number: $0,
                    title: title,
                    frame: CGRect(
                        x: 0,
                        y: 0,
                        width: 1_200,
                        height: 800
                    )
                )
            },
            activeWindowTitle: title,
            expectedTitleIsObservable: title != nil
        )
    }
}
