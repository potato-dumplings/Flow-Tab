import XCTest
@testable import FlowTab

@MainActor
final class ManualHotkeyInputSource {
    let sourceID: HotkeyInputSourceID
    private(set) var sequence: UInt64 = 0

    init(sourceID: HotkeyInputSourceID = HotkeyInputSourceID()) {
        self.sourceID = sourceID
    }

    func register(
        on controller: SwitcherPanelController,
        for sessionKind: SwitcherPanelController.HotkeySessionKind
    ) {
        controller.registerHotkeyInputSource(sourceID, for: sessionKind)
    }

    @discardableResult
    func emit(
        phase: HotkeyInputEvent.Phase,
        isBackward: Bool = false,
        to controller: SwitcherPanelController,
        for sessionKind: SwitcherPanelController.HotkeySessionKind
    ) -> HotkeyInputEvent {
        sequence &+= 1
        let event = makeEvent(
            sequence: sequence,
            phase: phase,
            isBackward: isBackward
        )
        deliver(event, to: controller, for: sessionKind)
        return event
    }

    func makeEvent(
        sequence: UInt64,
        phase: HotkeyInputEvent.Phase,
        isBackward: Bool = false
    ) -> HotkeyInputEvent {
        HotkeyInputEvent(
            identity: HotkeyInputEventIdentity(
                sourceID: sourceID,
                sequence: sequence
            ),
            phase: phase,
            isBackward: isBackward
        )
    }

    func deliver(
        _ event: HotkeyInputEvent,
        to controller: SwitcherPanelController,
        for sessionKind: SwitcherPanelController.HotkeySessionKind
    ) {
        switch sessionKind {
        case .globalAppSwitcher:
            controller.handleGlobalHotkeyInput(event)
        case .inAppWindowSwitcher:
            controller.handleInAppWindowHotkeyInput(event)
        }
    }
}

extension FlowTabTests {
    @MainActor
    func testHotkeyInputOwnerAcceptsIdentityOnceAndRecordsGenerations() {
        let owner = SwitcherHotkeyInputOwner()
        let sourceID = HotkeyInputSourceID()
        let registrationGeneration = owner.register(
            sourceID: sourceID,
            for: .globalAppSwitcher
        )
        let event = HotkeyInputEvent(
            identity: HotkeyInputEventIdentity(
                sourceID: sourceID,
                sequence: 7
            ),
            phase: .pressed,
            isBackward: false
        )

        XCTAssertEqual(
            owner.observe(
                event,
                route: .globalAppSwitcher,
                presentationSessionGeneration: 11
            ),
            .accepted(
                SwitcherHotkeyInputReceipt(
                    route: .globalAppSwitcher,
                    event: event,
                    inputGeneration: 1,
                    sourceRegistrationGeneration: registrationGeneration,
                    presentationSessionGeneration: 11
                )
            )
        )
        XCTAssertEqual(
            owner.observe(
                event,
                route: .globalAppSwitcher,
                presentationSessionGeneration: 12
            ),
            .rejected(.duplicate(sequence: 7))
        )
        XCTAssertEqual(
            owner.latestPhase(for: .globalAppSwitcher),
            .pressed
        )
    }

    @MainActor
    func testHotkeyInputOwnerRejectsOutOfOrderAndUnexpectedSources() {
        let owner = SwitcherHotkeyInputOwner()
        let sourceID = HotkeyInputSourceID()
        let otherSourceID = HotkeyInputSourceID()
        owner.register(sourceID: sourceID, for: .inAppWindowSwitcher)

        let latest = HotkeyInputEvent(
            identity: HotkeyInputEventIdentity(
                sourceID: sourceID,
                sequence: 9
            ),
            phase: .released,
            isBackward: true
        )
        _ = owner.observe(
            latest,
            route: .inAppWindowSwitcher,
            presentationSessionGeneration: 3
        )
        let outOfOrder = HotkeyInputEvent(
            identity: HotkeyInputEventIdentity(
                sourceID: sourceID,
                sequence: 8
            ),
            phase: .pressed,
            isBackward: false
        )
        XCTAssertEqual(
            owner.observe(
                outOfOrder,
                route: .inAppWindowSwitcher,
                presentationSessionGeneration: 3
            ),
            .rejected(.outOfOrder(sequence: 8, latestSequence: 9))
        )

        let unexpected = HotkeyInputEvent(
            identity: HotkeyInputEventIdentity(
                sourceID: otherSourceID,
                sequence: 10
            ),
            phase: .pressed,
            isBackward: false
        )
        XCTAssertEqual(
            owner.observe(
                unexpected,
                route: .inAppWindowSwitcher,
                presentationSessionGeneration: 3
            ),
            .rejected(
                .unexpectedSource(
                    expected: sourceID,
                    observed: otherSourceID
                )
            )
        )
        XCTAssertEqual(owner.inputGeneration, 1)
    }

    @MainActor
    func testHotkeyInputOwnerRetainsExplicitHoldEvidenceUntilUpdated() {
        let owner = SwitcherHotkeyInputOwner()
        let sourceID = HotkeyInputSourceID()
        owner.register(
            sourceID: sourceID,
            for: .globalAppSwitcher
        )
        let pressed = HotkeyInputEvent(
            identity: HotkeyInputEventIdentity(
                sourceID: sourceID,
                sequence: 1
            ),
            phase: .pressed,
            isBackward: false,
            holdSetPressedEvidence: true
        )
        let mainKeyReleased = HotkeyInputEvent(
            identity: HotkeyInputEventIdentity(
                sourceID: sourceID,
                sequence: 2
            ),
            phase: .released,
            isBackward: false
        )

        _ = owner.observe(
            pressed,
            route: .globalAppSwitcher,
            presentationSessionGeneration: 1
        )
        _ = owner.observe(
            mainKeyReleased,
            route: .globalAppSwitcher,
            presentationSessionGeneration: 1
        )

        XCTAssertEqual(
            owner.latestHoldSetPressedEvidence(
                for: .globalAppSwitcher
            ),
            true
        )

        owner.updateHoldSetPressedEvidence(
            false,
            for: .globalAppSwitcher
        )
        XCTAssertEqual(
            owner.latestHoldSetPressedEvidence(
                for: .globalAppSwitcher
            ),
            false
        )

        owner.register(
            sourceID: HotkeyInputSourceID(),
            for: .globalAppSwitcher
        )
        XCTAssertNil(
            owner.latestHoldSetPressedEvidence(
                for: .globalAppSwitcher
            )
        )
    }

    @MainActor
    func testHotkeyInputOwnerSourceReplacementRejectsQueuedOldSource() {
        let owner = SwitcherHotkeyInputOwner()
        let firstSourceID = HotkeyInputSourceID()
        let secondSourceID = HotkeyInputSourceID()
        let firstRegistration = owner.register(
            sourceID: firstSourceID,
            for: .globalAppSwitcher
        )
        let secondRegistration = owner.register(
            sourceID: secondSourceID,
            for: .globalAppSwitcher
        )

        XCTAssertGreaterThan(secondRegistration, firstRegistration)
        let queuedOldEvent = HotkeyInputEvent(
            identity: HotkeyInputEventIdentity(
                sourceID: firstSourceID,
                sequence: 1
            ),
            phase: .pressed,
            isBackward: false
        )
        XCTAssertEqual(
            owner.observe(
                queuedOldEvent,
                route: .globalAppSwitcher,
                presentationSessionGeneration: 0
            ),
            .rejected(
                .unexpectedSource(
                    expected: secondSourceID,
                    observed: firstSourceID
                )
            )
        )

        owner.unregister(route: .globalAppSwitcher)
        XCTAssertEqual(
            owner.observe(
                queuedOldEvent,
                route: .globalAppSwitcher,
                presentationSessionGeneration: 0
            ),
            .rejected(.sourceNotRegistered)
        )
    }

    @MainActor
    func testHotkeyInputOwnerPressureCountsDistinctEventsExactlyOnce() {
        let owner = SwitcherHotkeyInputOwner()
        let sourceID = HotkeyInputSourceID()
        owner.register(sourceID: sourceID, for: .globalAppSwitcher)

        for sequence in UInt64(1)...2_000 {
            let event = HotkeyInputEvent(
                identity: HotkeyInputEventIdentity(
                    sourceID: sourceID,
                    sequence: sequence
                ),
                phase: sequence.isMultiple(of: 2) ? .released : .pressed,
                isBackward: sequence.isMultiple(of: 3)
            )
            guard case .accepted = owner.observe(
                event,
                route: .globalAppSwitcher,
                presentationSessionGeneration: Int(sequence % 17)
            ) else {
                XCTFail("Expected sequence \(sequence) to be accepted.")
                return
            }
            XCTAssertEqual(
                owner.observe(
                    event,
                    route: .globalAppSwitcher,
                    presentationSessionGeneration: Int(sequence % 17)
                ),
                .rejected(.duplicate(sequence: sequence))
            )
        }

        XCTAssertEqual(owner.inputGeneration, 2_000)
        XCTAssertEqual(owner.latestPhase(for: .globalAppSwitcher), .released)
    }

    func testInAppHotkeyAdvanceApplicationEvidencePublishesExactTransition() {
        let sourceID = HotkeyInputSourceID(
            rawValue: UUID(
                uuidString:
                    "7A9D58C2-46B3-43EF-935B-6E6C050E4D53"
            )!
        )
        let receipt = SwitcherHotkeyInputReceipt(
            route: .inAppWindowSwitcher,
            event: HotkeyInputEvent(
                identity: HotkeyInputEventIdentity(
                    sourceID: sourceID,
                    sequence: 17
                ),
                phase: .pressed,
                isBackward: false
            ),
            inputGeneration: 23,
            sourceRegistrationGeneration: 5,
            presentationSessionGeneration: 11
        )

        let evidence = InAppHotkeyAdvanceApplicationEvidence(
            receipt: receipt,
            previousWindowID: "cg:420:7001",
            selectedWindowID: "cg:420:7002"
        )

        XCTAssertEqual(evidence?.direction, "forward")
        XCTAssertEqual(evidence?.key, "tabForward")
        XCTAssertEqual(
            evidence?.logMessage,
            "inAppHotkeyAdvance result=applied "
                + "dir=forward key=tabForward "
                + "route=inAppWindowSwitcher "
                + "source=7A9D58C2-46B3-43EF-935B-6E6C050E4D53 "
                + "sequence=17 inputGeneration=23 "
                + "sourceRegistrationGeneration=5 "
                + "sessionGeneration=11 "
                + "previousWindowID=cg:420:7001 "
                + "selectedWindowID=cg:420:7002"
        )
    }

    func testInAppHotkeyAdvanceApplicationEvidenceRequiresAcceptedChangedWindow() {
        let sourceID = HotkeyInputSourceID()
        func receipt(
            route: SwitcherHotkeyInputRoute,
            phase: HotkeyInputEvent.Phase
        ) -> SwitcherHotkeyInputReceipt {
            SwitcherHotkeyInputReceipt(
                route: route,
                event: HotkeyInputEvent(
                    identity: HotkeyInputEventIdentity(
                        sourceID: sourceID,
                        sequence: 1
                    ),
                    phase: phase,
                    isBackward: false
                ),
                inputGeneration: 1,
                sourceRegistrationGeneration: 1,
                presentationSessionGeneration: 1
            )
        }

        XCTAssertNil(
            InAppHotkeyAdvanceApplicationEvidence(
                receipt: receipt(
                    route: .globalAppSwitcher,
                    phase: .pressed
                ),
                previousWindowID: "cg:420:7001",
                selectedWindowID: "cg:420:7002"
            )
        )
        XCTAssertNil(
            InAppHotkeyAdvanceApplicationEvidence(
                receipt: receipt(
                    route: .inAppWindowSwitcher,
                    phase: .released
                ),
                previousWindowID: "cg:420:7001",
                selectedWindowID: "cg:420:7002"
            )
        )
        XCTAssertNil(
            InAppHotkeyAdvanceApplicationEvidence(
                receipt: receipt(
                    route: .inAppWindowSwitcher,
                    phase: .pressed
                ),
                previousWindowID: "cg:420:7001",
                selectedWindowID: "cg:420:7001"
            )
        )
        XCTAssertNil(
            InAppHotkeyAdvanceApplicationEvidence(
                receipt: receipt(
                    route: .inAppWindowSwitcher,
                    phase: .pressed
                ),
                previousWindowID: nil,
                selectedWindowID: "cg:420:7002"
            )
        )
    }
}
