import CoreGraphics
import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testSwitcherPointerSelectionGateIgnoresInitialHoverUntilPointerMoves() {
        var gate = SwitcherPointerSelectionGate(movementThreshold: 1)
        let target =
            SwitcherPointerSelectionTarget.application(appID: "mail")

        gate.reset(currentLocation: CGPoint(x: 10, y: 10))

        XCTAssertEqual(gate.generation, 1)
        XCTAssertFalse(gate.isArmed)
        XCTAssertEqual(
            gate.evaluateSelection(
                of: target,
                at: CGPoint(x: 10.5, y: 10.5)
            ),
            .blocked(
                SwitcherPointerSelectionGateBlockedEvidence(
                    generation: 1,
                    target: target
                )
            )
        )
        XCTAssertFalse(gate.isArmed)
        XCTAssertEqual(
            gate.evaluateSelection(
                of: target,
                at: CGPoint(x: 10.5, y: 10.5)
            ),
            .duplicateBlocked
        )

        XCTAssertEqual(
            gate.evaluateSelection(
                of: target,
                at: CGPoint(x: 11, y: 10)
            ),
            .allowed
        )
        XCTAssertTrue(gate.isArmed)
    }

    func testSwitcherPointerSelectionGateResetRequiresFreshMovement() {
        var gate = SwitcherPointerSelectionGate(movementThreshold: 1)

        gate.reset(currentLocation: CGPoint(x: 0, y: 0))
        XCTAssertTrue(
            gate.recordPointerMoved(to: CGPoint(x: 2, y: 0))
        )
        XCTAssertTrue(gate.isArmed)

        gate.reset(currentLocation: CGPoint(x: 2, y: 0))

        XCTAssertEqual(gate.generation, 2)
        XCTAssertFalse(gate.isArmed)
        XCTAssertFalse(
            gate.recordPointerMoved(to: CGPoint(x: 2.5, y: 0))
        )
        XCTAssertTrue(
            gate.recordPointerMoved(to: CGPoint(x: 3.1, y: 0))
        )
    }

    func testSwitcherPointerSelectionGatePublishesEachBlockedTargetOncePerGeneration() {
        var gate = SwitcherPointerSelectionGate(movementThreshold: 1)
        let application =
            SwitcherPointerSelectionTarget.application(appID: "mail")
        let window = SwitcherPointerSelectionTarget.window(
            appID: "browser",
            windowID: "secondary"
        )

        gate.reset(currentLocation: .zero)

        XCTAssertNotNil(
            gate.evaluateSelection(
                of: application,
                at: .zero
            ).newBlockedEvidence
        )
        XCTAssertEqual(
            gate.evaluateSelection(
                of: application,
                at: .zero
            ),
            .duplicateBlocked
        )
        XCTAssertEqual(
            gate.evaluateSelection(
                of: window,
                at: .zero
            ).newBlockedEvidence?.generation,
            1
        )

        gate.reset(currentLocation: .zero)

        XCTAssertEqual(
            gate.evaluateSelection(
                of: application,
                at: .zero
            ).newBlockedEvidence?.generation,
            2
        )
    }

    func testSwitcherPointerSelectionGateLifecycleUnderPressure() {
        var gate = SwitcherPointerSelectionGate(movementThreshold: 1)
        let target =
            SwitcherPointerSelectionTarget.searchResult(
                resultID: "app:browser"
            )

        for generation in UInt64(1)...2_000 {
            gate.reset(currentLocation: .zero)

            XCTAssertEqual(
                gate.evaluateSelection(
                    of: target,
                    at: .zero
                ).newBlockedEvidence?.generation,
                generation
            )
            for _ in 0..<8 {
                XCTAssertEqual(
                    gate.evaluateSelection(
                        of: target,
                        at: .zero
                    ),
                    .duplicateBlocked
                )
            }
            XCTAssertEqual(
                gate.evaluateSelection(
                    of: target,
                    at: CGPoint(x: 1, y: 0)
                ),
                .allowed
            )
        }
    }

    func testSwitcherPointerSelectionGateDiagnosticFieldsAreStableAndEscaped() {
        XCTAssertEqual(
            SwitcherPointerSelectionTarget.application(
                appID: "com.example mail"
            ).diagnosticSummary,
            "targetKind=application targetID=com.example%20mail"
        )
        XCTAssertEqual(
            SwitcherPointerSelectionTarget.window(
                appID: "com.example.browser",
                windowID: "window:2"
            ).diagnosticSummary,
            "targetKind=window targetID=window%3A2 "
                + "targetAppID=com.example.browser"
        )
        XCTAssertEqual(
            SwitcherPointerSelectionTarget.searchResult(
                resultID: "app:com.example.browser"
            ).diagnosticSummary,
            "targetKind=searchResult "
                + "targetID=app%3Acom.example.browser"
        )
    }
}
