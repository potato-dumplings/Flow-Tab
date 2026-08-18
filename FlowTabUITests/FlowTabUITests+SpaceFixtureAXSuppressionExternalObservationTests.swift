import ApplicationServices
import Darwin
import XCTest

private enum
    SpaceFixtureAXSuppressionExternalObservationTestPolicy
{
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testAXSuppressionObservationPolicyPreservesCompatibleResolutionWatchdog() {
        XCTAssertEqual(
            SpaceFixtureAXSuppressionObservationPolicy
                .resolutionWatchdog,
            20
        )
    }

    func testAXSuppressionConsumerRegistersBothObserversBeforeAcceptingSynchronousEvidence() {
        let route = Self.axSuppressionTestRoute()
        var order: [String] = []
        let owner =
            SpaceFixtureAXSuppressionRouteObservationOwner(
                route: route,
                completionRegistration: { callback in
                    order.append("completionObserver")
                    callback(
                        Self.axSuppressionTestCompletion()
                    )
                    return
                        FlowTabUITestObservationCancellation {
                            order.append(
                                "completionCancel"
                            )
                        }
                },
                verificationRegistration: { callback in
                    order.append("verificationObserver")
                    callback(
                        Self.axSuppressionTestVerification()
                    )
                    return
                        FlowTabUITestObservationCancellation {
                            order.append(
                                "verificationCancel"
                            )
                        }
                }
            )

        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .notificationReadback
        )
        XCTAssertEqual(
            order,
            [
                "completionObserver",
                "verificationObserver",
                "completionCancel",
                "verificationCancel",
            ]
        )
    }

    func testAXSuppressionConsumerAcceptsOutOfOrderEvidenceOnlyAfterExactAuthorizedReadback() {
        let route = Self.axSuppressionTestRoute()
        var completionCallback:
            ((SpaceFixtureAXSuppressionCompletion) -> Void)?
        var verificationCallback:
            ((
                SpaceFixtureAXSuppressionReadbackVerification
            ) -> Void)?
        let owner =
            SpaceFixtureAXSuppressionRouteObservationOwner(
                route: route,
                completionRegistration: {
                    completionCallback = $0
                    return
                        FlowTabUITestObservationCancellation {}
                },
                verificationRegistration: {
                    verificationCallback = $0
                    return
                        FlowTabUITestObservationCancellation {}
                }
            )
        owner.start()
        defer { owner.cancel() }

        verificationCallback?(
            Self.axSuppressionTestVerification(
                externalWindowCount: 1
            )
        )
        completionCallback?(
            Self.axSuppressionTestCompletion()
        )
        XCTAssertNil(owner.resolvedEvidence)

        verificationCallback?(
            Self.axSuppressionTestVerification(
                verificationGeneration: 2
            )
        )

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .notificationReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value
                .verification?
                .externalWindowsCount,
            0
        )
    }

    func testAXSuppressionConsumerRejectsCancelledStaleDuplicateAndRegressedEvidenceUnderPressure() {
        for iteration in
            0..<SpaceFixtureAXSuppressionExternalObservationTestPolicy
                .pressureIterations
        {
            let route = Self.axSuppressionTestRoute(
                suffix: "\(iteration)"
            )
            var completionCallbacks: [
                (SpaceFixtureAXSuppressionCompletion) -> Void
            ] = []
            var verificationCallbacks: [
                (
                    SpaceFixtureAXSuppressionReadbackVerification
                ) -> Void
            ] = []
            var completionCancellationCount = 0
            var verificationCancellationCount = 0
            let owner =
                SpaceFixtureAXSuppressionRouteObservationOwner(
                    route: route,
                    completionRegistration: { callback in
                        completionCallbacks.append(callback)
                        return
                            FlowTabUITestObservationCancellation {
                                completionCancellationCount += 1
                            }
                    },
                    verificationRegistration: {
                        callback in
                        verificationCallbacks.append(
                            callback
                        )
                        return
                            FlowTabUITestObservationCancellation {
                                verificationCancellationCount += 1
                            }
                    }
                )

            owner.start()
            let staleCompletion = completionCallbacks[0]
            let staleVerification =
                verificationCallbacks[0]
            owner.cancel()
            owner.start()

            staleCompletion(
                Self.axSuppressionTestCompletion(
                    suppressionGeneration: 100
                )
            )
            staleVerification(
                Self.axSuppressionTestVerification(
                    verificationGeneration: 100,
                    suppressionGeneration: 100
                )
            )
            XCTAssertNil(owner.resolvedEvidence)

            let currentCompletion = completionCallbacks[1]
            let currentVerification =
                verificationCallbacks[1]
            currentCompletion(
                Self.axSuppressionTestCompletion(
                    suppressionGeneration: 2
                )
            )
            currentCompletion(
                Self.axSuppressionTestCompletion(
                    suppressionGeneration: 2
                )
            )
            currentCompletion(
                Self.axSuppressionTestCompletion(
                    suppressionGeneration: 1
                )
            )
            currentVerification(
                Self.axSuppressionTestVerification(
                    verificationGeneration: 3,
                    suppressionGeneration: 1
                )
            )
            currentVerification(
                Self.axSuppressionTestVerification(
                    verificationGeneration: 2
                )
            )
            XCTAssertNil(owner.resolvedEvidence)

            currentVerification(
                Self.axSuppressionTestVerification(
                    verificationGeneration: 4
                )
            )
            XCTAssertEqual(
                owner.resolvedEvidence?.value
                    .completion?
                    .suppressionGeneration,
                2
            )
            owner.cancel()
            XCTAssertEqual(
                completionCancellationCount,
                2
            )
            XCTAssertEqual(
                verificationCancellationCount,
                2
            )
        }
    }

    func testAXSuppressionConsumerWatchdogReportsLastAuthorizedReadbackEvidence() {
        var completionCallback:
            ((SpaceFixtureAXSuppressionCompletion) -> Void)?
        var verificationCallback:
            ((
                SpaceFixtureAXSuppressionReadbackVerification
            ) -> Void)?
        let owner =
            SpaceFixtureAXSuppressionRouteObservationOwner(
                route: Self.axSuppressionTestRoute(),
                completionRegistration: {
                    completionCallback = $0
                    return
                        FlowTabUITestObservationCancellation {}
                },
                verificationRegistration: {
                    verificationCallback = $0
                    return
                        FlowTabUITestObservationCancellation {}
                }
            )
        owner.start()
        defer { owner.cancel() }
        completionCallback?(
            Self.axSuppressionTestCompletion()
        )
        verificationCallback?(
            Self.axSuppressionTestVerification(
                externalChildrenError:
                    AXError.apiDisabled.rawValue,
                externalChildrenCount: -1
            )
        )

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    SpaceFixtureAXSuppressionExternalObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "pid=4567"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "externalChildren={error=-25211 count=-1}"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "externalWindows={error=0 count=0}"
            )
        )
    }

    private static func axSuppressionTestRoute(
        suffix: String = "route"
    ) -> SpaceFixtureAXSuppressionUITestRoute {
        SpaceFixtureAXSuppressionUITestRoute(
            workflowAppID: "chrome-\(suffix)",
            bundleIdentifier:
                "com.example.fixture.chrome",
            expectedWindowCount: 4,
            projectionAcknowledgementNotificationName:
                .init("test.ax.projection.\(suffix)"),
            suppressionCompletionNotificationName:
                .init("test.ax.suppression.\(suffix)"),
            externalReadbackNotificationName:
                .init("test.ax.external.\(suffix)")
        )
    }

    private static func axSuppressionTestCompletion(
        suppressionGeneration: UInt64 = 2
    ) -> SpaceFixtureAXSuppressionCompletion {
        SpaceFixtureAXSuppressionCompletion(
            suppressionGeneration: suppressionGeneration,
            acknowledgementGeneration: 1,
            bundleIdentifier:
                "com.example.fixture.chrome",
            processIdentifier: pid_t(4_567),
            windowCount: 4,
            sourceGeneration: "source-1",
            childWindowCount: 0,
            windowsAttributeCount: 0
        )
    }

    private static func axSuppressionTestVerification(
        verificationGeneration: UInt64 = 1,
        suppressionGeneration: UInt64 = 2,
        externalChildrenError: AXError.RawValue =
            AXError.success.rawValue,
        externalChildrenCount: Int = 0,
        externalWindowCount: Int = 0
    ) -> SpaceFixtureAXSuppressionReadbackVerification {
        SpaceFixtureAXSuppressionReadbackVerification(
            verificationGeneration:
                verificationGeneration,
            suppressionGeneration: suppressionGeneration,
            acknowledgementGeneration: 1,
            bundleIdentifier:
                "com.example.fixture.chrome",
            processIdentifier: pid_t(4_567),
            windowCount: 4,
            sourceGeneration: "source-1",
            childWindowCount: 0,
            windowsAttributeCount: 0,
            externalProcessIsRunning: true,
            externalChildrenError:
                externalChildrenError,
            externalChildrenCount:
                externalChildrenCount,
            externalWindowsError:
                AXError.success.rawValue,
            externalWindowsCount:
                externalWindowCount
        )
    }
}
