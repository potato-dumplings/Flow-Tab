import CoreGraphics
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testRuntimeWindowMappingStateDerivesReverseAXCGIndex() {
        let state = RuntimeWindowMappingState(
            currentAXToCG: [
                "ax:18405:0": 240_001,
                "ax:18405:1": 243_747
            ],
            validCGWindowIDs: Set<CGWindowID>([240_001, 243_747, 250_000]),
            lastAXWindowIDs: Set(["ax:18405:0", "ax:18405:1"])
        )

        XCTAssertEqual(state.currentCGToAX[240_001], "ax:18405:0")
        XCTAssertEqual(state.currentCGToAX[243_747], "ax:18405:1")
        XCTAssertNil(state.currentCGToAX[250_000])
        XCTAssertEqual(state.validCGWindowIDs, Set<CGWindowID>([240_001, 243_747, 250_000]))
        XCTAssertEqual(state.lastAXWindowIDs, Set(["ax:18405:0", "ax:18405:1"]))
    }
}
