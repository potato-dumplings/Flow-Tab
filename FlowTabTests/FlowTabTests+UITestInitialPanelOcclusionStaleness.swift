import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testUITestInitialPanelOcclusionStalenessInstallsAndReleasesEvidence() {
        XCTAssertEqual(
            FlowTabUITestInitialPanelOcclusionStalenessPolicy(
                rawMilliseconds: 0
            ).milliseconds,
            1
        )
        XCTAssertEqual(
            FlowTabUITestInitialPanelOcclusionStalenessPolicy(
                rawMilliseconds: 8_000
            ).milliseconds,
            5_000
        )

        let scheduler =
            ManualInitialPanelOcclusionScheduler()
        let owner =
            FlowTabUITestInitialPanelOcclusionStalenessOwner(
                scheduler: scheduler
            )
        var override:
            FlowTabUITestInitialPanelOcclusionReadback =
                .unavailable
        var evidence:
            [FlowTabUITestInitialPanelOcclusionStalenessEvidence]
                = []

        let generation = owner.start(
            policy:
                FlowTabUITestInitialPanelOcclusionStalenessPolicy(
                    rawMilliseconds: 260
                ),
            install: {
                override = Self.panelOcclusionReadback(
                    installed: true,
                    visible: false
                )
                return override
            },
            release: {
                override = Self.panelOcclusionReadback(
                    installed: true,
                    visible: true
                )
                return override
            },
            cancelInjection: {
                override = Self.panelOcclusionReadback(
                    installed: false,
                    visible: false
                )
                return override
            },
            onEvidence: { evidence.append($0) }
        )

        XCTAssertEqual(generation, 1)
        XCTAssertTrue(owner.isActive)
        XCTAssertTrue(owner.hasPendingRelease)
        XCTAssertEqual(
            scheduler.intervals,
            [0.26]
        )
        XCTAssertEqual(
            evidence.map(\.phase),
            [.installed]
        )
        XCTAssertEqual(
            evidence.first?.readback,
            Self.panelOcclusionReadback(
                installed: true,
                visible: false
            )
        )

        scheduler.fire(at: 0)

        XCTAssertFalse(owner.isActive)
        XCTAssertFalse(owner.hasPendingRelease)
        XCTAssertEqual(
            evidence.map(\.phase),
            [.installed, .released]
        )
        XCTAssertEqual(
            evidence.last?.readback,
            Self.panelOcclusionReadback(
                installed: true,
                visible: true
            )
        )
        XCTAssertTrue(
            scheduler.tokens[0].isCancelled
        )
    }

    @MainActor
    func testUITestInitialPanelOcclusionStalenessReplacementRejectsStaleRelease() {
        let scheduler =
            ManualInitialPanelOcclusionScheduler()
        let owner =
            FlowTabUITestInitialPanelOcclusionStalenessOwner(
                scheduler: scheduler
            )
        var evidence:
            [FlowTabUITestInitialPanelOcclusionStalenessEvidence]
                = []
        var visible = false

        let start: () -> UInt64 = {
            owner.start(
                policy:
                    FlowTabUITestInitialPanelOcclusionStalenessPolicy(
                        rawMilliseconds: 260
                    ),
                install: {
                    visible = false
                    return Self.panelOcclusionReadback(
                        installed: true,
                        visible: false
                    )
                },
                release: {
                    visible = true
                    return Self.panelOcclusionReadback(
                        installed: true,
                        visible: true
                    )
                },
                cancelInjection: {
                    visible = false
                    return Self.panelOcclusionReadback(
                        installed: false,
                        visible: false
                    )
                },
                onEvidence: {
                    evidence.append($0)
                }
            )
        }

        let firstGeneration = start()
        let secondGeneration = start()
        XCTAssertEqual(
            secondGeneration,
            firstGeneration &+ 1
        )
        XCTAssertEqual(
            evidence.map(\.phase),
            [.installed, .cancelled, .installed]
        )

        scheduler.fire(
            at: 0,
            includingCancelled: true
        )
        XCTAssertFalse(visible)
        XCTAssertEqual(
            evidence.map(\.phase),
            [.installed, .cancelled, .installed]
        )

        owner.cancel()
        XCTAssertFalse(owner.isActive)
        XCTAssertFalse(visible)
        XCTAssertEqual(
            evidence.map(\.phase),
            [
                .installed,
                .cancelled,
                .installed,
                .cancelled
            ]
        )
        XCTAssertEqual(
            evidence.map(\.ownerGeneration),
            [
                firstGeneration,
                firstGeneration,
                secondGeneration,
                secondGeneration
            ]
        )
    }

    @MainActor
    func testUITestInitialPanelOcclusionStalenessSupportsSynchronousRelease() {
        let scheduler =
            SynchronousInitialPanelOcclusionScheduler()
        let owner =
            FlowTabUITestInitialPanelOcclusionStalenessOwner(
                scheduler: scheduler
            )
        var phases:
            [FlowTabUITestInitialPanelOcclusionStalenessPhase]
                = []

        owner.start(
            policy:
                FlowTabUITestInitialPanelOcclusionStalenessPolicy(
                    rawMilliseconds: 260
                ),
            install: {
                Self.panelOcclusionReadback(
                    installed: true,
                    visible: false
                )
            },
            release: {
                Self.panelOcclusionReadback(
                    installed: true,
                    visible: true
                )
            },
            cancelInjection: {
                Self.panelOcclusionReadback(
                    installed: false,
                    visible: false
                )
            },
            onEvidence: {
                phases.append($0.phase)
            }
        )

        XCTAssertEqual(
            phases,
            [.installed, .released]
        )
        XCTAssertFalse(owner.isActive)
        XCTAssertTrue(
            scheduler.token.isCancelled
        )
    }

    @MainActor
    func testUITestInitialPanelOcclusionStalenessDeinitCleansUpInjection() async {
        let scheduler =
            ManualInitialPanelOcclusionScheduler()
        var owner:
            FlowTabUITestInitialPanelOcclusionStalenessOwner? =
                FlowTabUITestInitialPanelOcclusionStalenessOwner(
                    scheduler: scheduler
                )
        weak var retainedOwner = owner
        var injectionIsInstalled = false
        var phases:
            [FlowTabUITestInitialPanelOcclusionStalenessPhase]
                = []
        let injectionCancelled = expectation(
            description:
                "deinit removes the stale occlusion injection"
        )

        owner?.start(
            policy:
                FlowTabUITestInitialPanelOcclusionStalenessPolicy(
                    rawMilliseconds: 260
                ),
            install: {
                injectionIsInstalled = true
                return Self.panelOcclusionReadback(
                    installed: true,
                    visible: false
                )
            },
            release: {
                Self.panelOcclusionReadback(
                    installed: true,
                    visible: true
                )
            },
            cancelInjection: {
                injectionIsInstalled = false
                injectionCancelled.fulfill()
                return Self.panelOcclusionReadback(
                    installed: false,
                    visible: false
                )
            },
            onEvidence: {
                phases.append($0.phase)
            }
        )
        XCTAssertTrue(injectionIsInstalled)

        owner = nil

        await fulfillment(
            of: [injectionCancelled],
            timeout: 1
        )
        XCTAssertNil(retainedOwner)
        XCTAssertFalse(injectionIsInstalled)
        XCTAssertEqual(phases, [.installed])
        XCTAssertTrue(
            scheduler.tokens[0].isCancelled
        )
    }

    private static func panelOcclusionReadback(
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

@MainActor
final class ManualInitialPanelOcclusionScheduler:
    FlowTabUITestInitialPanelOcclusionScheduling
{
    final class Token:
        FlowTabUITestInitialPanelOcclusionCancellable
    {
        let action: @MainActor @Sendable () -> Void
        private(set) var isCancelled = false

        init(
            action:
                @escaping @MainActor @Sendable () -> Void
        ) {
            self.action = action
        }

        func cancel() {
            isCancelled = true
        }
    }

    private(set) var intervals: [TimeInterval] = []
    private(set) var tokens: [Token] = []

    func schedule(
        after interval: TimeInterval,
        _ action:
            @escaping @MainActor @Sendable () -> Void
    ) -> any FlowTabUITestInitialPanelOcclusionCancellable {
        intervals.append(interval)
        let token = Token(action: action)
        tokens.append(token)
        return token
    }

    func fire(
        at index: Int,
        includingCancelled: Bool = false
    ) {
        let token = tokens[index]
        guard includingCancelled
                || !token.isCancelled
        else {
            return
        }
        token.action()
    }
}

@MainActor
private final class SynchronousInitialPanelOcclusionScheduler:
    FlowTabUITestInitialPanelOcclusionScheduling
{
    final class Token:
        FlowTabUITestInitialPanelOcclusionCancellable
    {
        private(set) var isCancelled = false

        func cancel() {
            isCancelled = true
        }
    }

    let token = Token()

    func schedule(
        after _: TimeInterval,
        _ action:
            @escaping @MainActor @Sendable () -> Void
    ) -> any FlowTabUITestInitialPanelOcclusionCancellable {
        action()
        return token
    }
}
