import Combine
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testHotkeyRegistrationObservationInstallsBeforeInitialReadback() async {
        let notificationCenter = NotificationCenter()
        let request = makeHotkeyRegistrationRequest(
            mainModifier: .command,
            mainKey: .tab
        )
        let initialEvidence = HotkeyRegistrationEvidence(
            generation: 1,
            request: request,
            commandTabTakeoverActive: false
        )
        let notificationEvidence = HotkeyRegistrationEvidence(
            generation: 2,
            request: request,
            commandTabTakeoverActive: true
        )
        var didPostDuringReadback = false
        let owner = HotkeyRegistrationObservationOwner(
            notificationCenter: notificationCenter,
            evidenceProvider: {
                if !didPostDuringReadback {
                    didPostDuringReadback = true
                    notificationCenter.post(
                        name: .flowTabHotkeyRegistrationEvidenceDidChange,
                        object: nil,
                        userInfo: notificationEvidence.notificationUserInfo
                    )
                }
                return initialEvidence
            }
        )
        let receivedNewerEvidence = expectation(
            description: "observer receives evidence posted during initial readback"
        )
        let observation = owner.$latestEvidence
            .compactMap { $0 }
            .filter { $0.generation == notificationEvidence.generation }
            .sink { _ in receivedNewerEvidence.fulfill() }

        owner.start()

        await fulfillment(of: [receivedNewerEvidence], timeout: 1)
        XCTAssertEqual(owner.latestEvidence, notificationEvidence)
        XCTAssertEqual(
            owner.takeoverState(matching: request),
            .active
        )
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testHotkeyRegistrationObservationUsesGenerationAndExactRequestEvidence() {
        var readbackEvidence: HotkeyRegistrationEvidence?
        let owner = HotkeyRegistrationObservationOwner(
            notificationCenter: NotificationCenter(),
            evidenceProvider: { readbackEvidence }
        )
        let firstRequest = makeHotkeyRegistrationRequest(
            mainModifier: .command,
            mainKey: .tab
        )

        owner.prepare(for: firstRequest)
        XCTAssertEqual(owner.takeoverState(matching: firstRequest), .pending)

        let firstResult = HotkeyRegistrationEvidence(
            generation: 4,
            request: firstRequest,
            commandTabTakeoverActive: true
        )
        readbackEvidence = firstResult
        owner.readback()

        XCTAssertNil(owner.pendingRequest)
        XCTAssertEqual(owner.latestEvidence, firstResult)
        XCTAssertEqual(owner.takeoverState(matching: firstRequest), .active)

        readbackEvidence = HotkeyRegistrationEvidence(
            generation: 3,
            request: firstRequest,
            commandTabTakeoverActive: false
        )
        owner.readback()
        XCTAssertEqual(owner.latestEvidence, firstResult)

        readbackEvidence = HotkeyRegistrationEvidence(
            generation: 4,
            request: firstRequest,
            commandTabTakeoverActive: false
        )
        owner.readback()
        XCTAssertEqual(owner.latestEvidence, firstResult)

        let secondRequest = makeHotkeyRegistrationRequest(
            mainModifier: .option,
            mainKey: .space,
            inAppModifier: .command,
            inAppKey: .tab
        )
        owner.prepare(for: secondRequest)
        readbackEvidence = HotkeyRegistrationEvidence(
            generation: 5,
            request: firstRequest,
            commandTabTakeoverActive: false
        )
        owner.readback()

        XCTAssertEqual(owner.pendingRequest, secondRequest)
        XCTAssertEqual(owner.takeoverState(matching: secondRequest), .pending)

        let secondResult = HotkeyRegistrationEvidence(
            generation: 6,
            request: secondRequest,
            commandTabTakeoverActive: false
        )
        readbackEvidence = secondResult
        owner.readback()

        XCTAssertNil(owner.pendingRequest)
        XCTAssertEqual(owner.latestEvidence, secondResult)
        XCTAssertEqual(owner.takeoverState(matching: secondRequest), .inactive)
    }

    @MainActor
    func testHotkeyRegistrationObservationMatchingReadbackAvoidsRedundantRequest() {
        let registeredRequest = makeHotkeyRegistrationRequest(
            mainModifier: .command,
            mainKey: .tab
        )
        let evidence = HotkeyRegistrationEvidence(
            generation: 7,
            request: registeredRequest,
            commandTabTakeoverActive: true,
            source:
                HotkeyRegistrationEvidence
                    .applicationLaunchSource
        )
        var readbackCount = 0
        let owner = HotkeyRegistrationObservationOwner(
            notificationCenter: NotificationCenter()
        ) {
            readbackCount += 1
            return evidence
        }
        let matchingRequest = makeHotkeyRegistrationRequest(
            mainModifier: .command,
            mainKey: .tab
        )
        let changedRequest = makeHotkeyRegistrationRequest(
            mainModifier: .option,
            mainKey: .space
        )

        XCTAssertTrue(
            owner.hasMatchingRegistration(
                for: matchingRequest
            )
        )
        XCTAssertEqual(owner.latestEvidence, evidence)
        XCTAssertGreaterThanOrEqual(readbackCount, 1)
        XCTAssertFalse(
            owner.hasMatchingRegistration(
                for: changedRequest
            )
        )
    }

    @MainActor
    func testHotkeyRegistrationObservationStopCancelsDeliveryAndClearsState() {
        let notificationCenter = NotificationCenter()
        let request = makeHotkeyRegistrationRequest(
            mainModifier: .command,
            mainKey: .tab
        )
        let evidence = HotkeyRegistrationEvidence(
            generation: 1,
            request: request,
            commandTabTakeoverActive: true
        )
        let owner = HotkeyRegistrationObservationOwner(
            notificationCenter: notificationCenter,
            evidenceProvider: { nil }
        )

        owner.prepare(for: request)
        notificationCenter.post(
            name: .flowTabHotkeyRegistrationEvidenceDidChange,
            object: nil,
            userInfo: evidence.notificationUserInfo
        )
        owner.stop()

        XCTAssertNil(owner.pendingRequest)
        XCTAssertNil(owner.latestEvidence)
        XCTAssertEqual(owner.takeoverState(matching: request), .pending)
    }

    @MainActor
    func testHotkeyRegistrationObservationSchedulingLatencyDoesNotChangeResult() async {
        let request = makeHotkeyRegistrationRequest(
            mainModifier: .command,
            mainKey: .tab
        )
        let result = HotkeyRegistrationEvidence(
            generation: 1,
            request: request,
            commandTabTakeoverActive: true
        )
        let immediateReadback: HotkeyRegistrationEvidence? = result
        let immediateOwner = HotkeyRegistrationObservationOwner(
            notificationCenter: NotificationCenter(),
            evidenceProvider: { immediateReadback }
        )
        immediateOwner.prepare(for: request)
        immediateOwner.readback()

        var delayedReadback: HotkeyRegistrationEvidence?
        let delayedOwner = HotkeyRegistrationObservationOwner(
            notificationCenter: NotificationCenter(),
            evidenceProvider: { delayedReadback }
        )
        delayedOwner.prepare(for: request)
        for _ in 0..<100 {
            await Task.yield()
        }
        delayedReadback = result
        delayedOwner.readback()

        XCTAssertEqual(
            delayedOwner.takeoverState(matching: request),
            immediateOwner.takeoverState(matching: request)
        )
        XCTAssertEqual(delayedOwner.latestEvidence, result)
    }

    @MainActor
    func testHotkeyRegistrationObservationPressureRetainsLatestGeneration() {
        var readbackEvidence: HotkeyRegistrationEvidence?
        let owner = HotkeyRegistrationObservationOwner(
            notificationCenter: NotificationCenter(),
            evidenceProvider: { readbackEvidence }
        )
        var lastRequest = makeHotkeyRegistrationRequest(
            mainModifier: .command,
            mainKey: .tab
        )

        for generation in 1...2_000 {
            let request = makeHotkeyRegistrationRequest(
                mainModifier: .command,
                mainKey: .tab
            )
            lastRequest = request
            owner.prepare(for: request)
            readbackEvidence = HotkeyRegistrationEvidence(
                generation: UInt64(generation),
                request: request,
                commandTabTakeoverActive: generation.isMultiple(of: 2)
            )
            owner.readback()
        }

        XCTAssertEqual(owner.latestEvidence?.generation, 2_000)
        XCTAssertEqual(owner.latestEvidence?.requestID, lastRequest.requestID)
        XCTAssertNil(owner.pendingRequest)
        XCTAssertEqual(owner.takeoverState(matching: lastRequest), .active)
    }

    private func makeHotkeyRegistrationRequest(
        mainModifier: SwitcherPrimaryModifier,
        mainKey: SwitcherHotkeyKey,
        inAppModifier: SwitcherPrimaryModifier = .option,
        inAppKey: SwitcherHotkeyKey = .grave
    ) -> HotkeyRegistrationRequest {
        HotkeyRegistrationRequest(
            mainConfiguration: SwitcherHotkeyConfiguration(
                primaryModifier: mainModifier,
                mainKey: mainKey,
                quitKey: .q
            ),
            inAppWindowConfiguration: SwitcherHotkeyConfiguration(
                primaryModifier: inAppModifier,
                mainKey: inAppKey,
                quitKey: .q
            )
        )
    }
}
