import Carbon
import XCTest

extension FlowTabUITests {
    func assertPhysicalControlTabPressureGate(
        in app: XCUIApplication,
        observer: ControlTabPressureUITestObserver,
        scenario: ControlTabPressureUITestScenario
    ) throws -> [ControlTabPressureUITestEvidence] {
        let openSequence = try XCTUnwrap(
            observer.post("physicalOpen")
        )
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [],
            modifierFlags: .control,
            requiresActiveProcess: false
        )
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [CGKeyCode(kVK_Tab)],
            modifierFlags: .control,
            requiresActiveProcess: false
        )
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [],
            modifierFlags: .control,
            requiresActiveProcess: false
        )
        let opened = try XCTUnwrap(
            observer.wait(sequence: openSequence, phase: "open"),
            "Physical Control+Tab open readback expired"
        )
        assertControlTabPressureEvidence(
            opened,
            scenario: scenario,
            expectsVisiblePanel: true
        )

        let forwardSequence = try XCTUnwrap(
            observer.post("physicalForward")
        )
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [CGKeyCode(kVK_Tab)],
            modifierFlags: .control,
            requiresActiveProcess: false
        )
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [],
            modifierFlags: .control,
            requiresActiveProcess: false
        )
        let forward = try XCTUnwrap(
            observer.wait(
                sequence: forwardSequence,
                phase: "forward"
            ),
            "Physical Control+Tab forward readback expired"
        )

        let reverseSequence = try XCTUnwrap(
            observer.post("physicalReverse")
        )
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [CGKeyCode(kVK_Tab)],
            modifierFlags: [.control, .shift],
            requiresActiveProcess: false
        )
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [],
            modifierFlags: .control,
            requiresActiveProcess: false
        )
        let reverse = try XCTUnwrap(
            observer.wait(
                sequence: reverseSequence,
                phase: "reverse"
            ),
            "Physical Control+Shift+Tab reverse readback expired"
        )

        XCTAssertEqual(
            forward.selectedWindowIDBefore,
            opened.selectedWindowIDAfter
        )
        XCTAssertNotEqual(
            forward.selectedWindowIDAfter,
            opened.selectedWindowIDAfter
        )
        XCTAssertEqual(
            reverse.selectedWindowIDBefore,
            forward.selectedWindowIDAfter
        )
        XCTAssertEqual(
            reverse.selectedWindowIDAfter,
            opened.selectedWindowIDAfter
        )

        let commitSequence = try XCTUnwrap(
            observer.post("physicalCommit")
        )
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [],
            modifierFlags: [],
            requiresActiveProcess: false
        )
        let commit = try XCTUnwrap(
            observer.wait(
                sequence: commitSequence,
                phase: "commit"
            ),
            "Physical Control release readback expired"
        )
        XCTAssertTrue(commit.satisfied)
        XCTAssertFalse(commit.panelPresented)
        XCTAssertTrue(commit.activationRequestIssued)
        let evidence = [opened, forward, reverse, commit]
        for item in evidence {
            assertControlTabStructuredSpanEvidence(item)
            XCTAssertTrue(item.timingValid)
            XCTAssertFalse(item.latePresentationObserved)
            XCTAssertFalse(item.watchdogExpired)
        }
        return evidence
    }
}
