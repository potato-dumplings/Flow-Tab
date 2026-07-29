import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testUITestInitialPanelOcclusionStalenessReplacementPressure() {
        let scheduler =
            ManualInitialPanelOcclusionScheduler()
        let owner =
            FlowTabUITestInitialPanelOcclusionStalenessOwner(
                scheduler: scheduler
            )
        var evidence:
            [FlowTabUITestInitialPanelOcclusionStalenessEvidence]
                = []
        var releasedGenerations: [UInt64] = []

        for _ in 1...500 {
            var generation: UInt64 = 0
            generation = owner.start(
                policy:
                    FlowTabUITestInitialPanelOcclusionStalenessPolicy(
                        rawMilliseconds: 260
                    ),
                install: {
                    Self.panelOcclusionReadbackForPressure(
                        installed: true,
                        visible: false
                    )
                },
                release: {
                    releasedGenerations.append(
                        generation
                    )
                    return Self.panelOcclusionReadbackForPressure(
                        installed: true,
                        visible: true
                    )
                },
                cancelInjection: {
                    Self.panelOcclusionReadbackForPressure(
                        installed: false,
                        visible: false
                    )
                },
                onEvidence: {
                    evidence.append($0)
                }
            )
        }

        for index in 0..<499 {
            scheduler.fire(
                at: index,
                includingCancelled: true
            )
        }
        XCTAssertTrue(
            releasedGenerations.isEmpty
        )
        scheduler.fire(at: 499)

        XCTAssertEqual(
            releasedGenerations,
            [500]
        )
        XCTAssertEqual(
            evidence.filter {
                $0.phase == .installed
            }.count,
            500
        )
        XCTAssertEqual(
            evidence.filter {
                $0.phase == .cancelled
            }.count,
            499
        )
        XCTAssertEqual(
            evidence.filter {
                $0.phase == .released
            }.map(\.ownerGeneration),
            [500]
        )
        XCTAssertTrue(
            scheduler.tokens
                .allSatisfy(\.isCancelled)
        )
    }

    private static func panelOcclusionReadbackForPressure(
        installed: Bool,
        visible: Bool
    ) -> FlowTabUITestInitialPanelOcclusionReadback {
        FlowTabUITestInitialPanelOcclusionReadback(
            panelIsAvailable: true,
            overrideIsInstalled: installed,
            overrideContainsVisible: visible
        )
    }
}
