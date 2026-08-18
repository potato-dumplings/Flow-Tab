import ApplicationServices
import Foundation

struct SpaceFixtureAXSuppressionReadbackVerification:
    Equatable
{
    let verificationGeneration: UInt64
    let suppressionGeneration: UInt64
    let acknowledgementGeneration: UInt64
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let windowCount: Int
    let sourceGeneration: String
    let childWindowCount: Int
    let windowsAttributeCount: Int
    let externalProcessIsRunning: Bool
    let externalChildrenError: AXError.RawValue
    let externalChildrenCount: Int
    let externalWindowsError: AXError.RawValue
    let externalWindowsCount: Int

    var isSuppressed: Bool {
        childWindowCount == 0
            && windowsAttributeCount == 0
            && externalProcessIsRunning
            && externalChildrenError
                == AXError.success.rawValue
            && externalChildrenCount == 0
            && externalWindowsError
                == AXError.success.rawValue
            && externalWindowsCount == 0
    }

    var diagnosticSummary: String {
        "verificationGeneration=\(verificationGeneration) "
            + "suppressionGeneration="
            + "\(suppressionGeneration) "
            + "ackGeneration="
            + "\(acknowledgementGeneration) "
            + "bundleID=\(bundleIdentifier) "
            + "pid=\(processIdentifier) "
            + "windows=\(windowCount) "
            + "sourceGeneration=\(sourceGeneration) "
            + "producerChildren=\(childWindowCount) "
            + "producerWindows=\(windowsAttributeCount) "
            + "externalRunning="
            + "\(externalProcessIsRunning) "
            + "externalChildren={error="
            + "\(externalChildrenError) count="
            + "\(externalChildrenCount)} "
            + "externalWindows={error="
            + "\(externalWindowsError) count="
            + "\(externalWindowsCount)}"
    }
}

struct SpaceFixtureAXSuppressionConsumerSnapshot:
    Equatable
{
    let completion: SpaceFixtureAXSuppressionCompletion?
    let verification:
        SpaceFixtureAXSuppressionReadbackVerification?

    var isSuppressed: Bool {
        guard let completion,
              let verification,
              verification.isSuppressed
        else {
            return false
        }
        return verification.suppressionGeneration
                == completion.suppressionGeneration
            && verification.acknowledgementGeneration
                == completion.acknowledgementGeneration
            && verification.bundleIdentifier
                == completion.bundleIdentifier
            && verification.processIdentifier
                == completion.processIdentifier
            && verification.windowCount
                == completion.windowCount
            && verification.sourceGeneration
                == completion.sourceGeneration
            && verification.childWindowCount
                == completion.childWindowCount
            && verification.windowsAttributeCount
                == completion.windowsAttributeCount
    }

    var diagnosticSummary: String {
        "completion={"
            + (completion?.diagnosticSummary ?? "unobserved")
            + "} authorizedExternalAX={"
            + (
                verification?.diagnosticSummary
                    ?? "unobserved"
            )
            + "}"
    }
}

typealias SpaceFixtureAXSuppressionCompletionRegistration =
    (
        @escaping (SpaceFixtureAXSuppressionCompletion) -> Void
    ) -> FlowTabUITestObservationCancellation?

typealias SpaceFixtureAXSuppressionVerificationRegistration =
    (
        @escaping (
            SpaceFixtureAXSuppressionReadbackVerification
        ) -> Void
    ) -> FlowTabUITestObservationCancellation?

private final class
    SpaceFixtureAXSuppressionRouteObservationState
{
    private var nextGeneration: UInt64 = 1
    private(set) var currentGeneration: UInt64?
    private(set) var latestCompletion:
        SpaceFixtureAXSuppressionCompletion?
    private(set) var latestVerification:
        SpaceFixtureAXSuppressionReadbackVerification?

    func begin() {
        currentGeneration = nextGeneration
        nextGeneration &+= 1
        latestCompletion = nil
        latestVerification = nil
    }

    func cancel() {
        currentGeneration = nil
    }

    func observe(
        _ completion: SpaceFixtureAXSuppressionCompletion,
        route: SpaceFixtureAXSuppressionUITestRoute,
        generation: UInt64
    ) -> Bool {
        guard currentGeneration == generation,
              completion.bundleIdentifier
                == route.bundleIdentifier,
              completion.windowCount
                == route.expectedWindowCount,
              completion.childWindowCount == 0,
              completion.windowsAttributeCount == 0,
              completion.suppressionGeneration
                > (
                    latestCompletion?
                        .suppressionGeneration ?? 0
                )
        else {
            return false
        }
        latestCompletion = completion
        return true
    }

    func observe(
        _ verification:
            SpaceFixtureAXSuppressionReadbackVerification,
        route: SpaceFixtureAXSuppressionUITestRoute,
        generation: UInt64
    ) -> Bool {
        guard currentGeneration == generation,
              verification.bundleIdentifier
                == route.bundleIdentifier,
              verification.windowCount
                == route.expectedWindowCount,
              verification.verificationGeneration
                > (
                    latestVerification?
                        .verificationGeneration ?? 0
                )
        else {
            return false
        }
        latestVerification = verification
        return true
    }
}

final class
    SpaceFixtureAXSuppressionRouteObservationOwner
{
    private let state =
        SpaceFixtureAXSuppressionRouteObservationState()
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            SpaceFixtureAXSuppressionConsumerSnapshot
        >

    init(
        route: SpaceFixtureAXSuppressionUITestRoute,
        completionRegistration:
            @escaping
            SpaceFixtureAXSuppressionCompletionRegistration,
        verificationRegistration:
            SpaceFixtureAXSuppressionVerificationRegistration? =
                nil
    ) {
        let state = self.state
        let resolvedVerificationRegistration =
            verificationRegistration
            ?? Self.distributedVerificationRegistration(
                route: route
            )
        conditionOwner =
            FlowTabUITestConditionObservationOwner(
                observationRegistration: { readback in
                    guard let generation =
                            state.currentGeneration
                    else {
                        return nil
                    }
                    let completionCancellation =
                        completionRegistration {
                            completion in
                            guard state.observe(
                                completion,
                                route: route,
                                generation: generation
                            ) else {
                                return
                            }
                            readback(.notificationReadback)
                        }
                    let verificationCancellation =
                        resolvedVerificationRegistration {
                            verification in
                            guard state.observe(
                                verification,
                                route: route,
                                generation: generation
                            ) else {
                                return
                            }
                            readback(.notificationReadback)
                        }
                    return FlowTabUITestObservationCancellation {
                        completionCancellation?.cancel()
                        verificationCancellation?.cancel()
                    }
                },
                readback: {
                    SpaceFixtureAXSuppressionConsumerSnapshot(
                        completion: state.latestCompletion,
                        verification:
                            state.latestVerification
                    )
                },
                isSatisfied: \.isSuppressed,
                describe: \.diagnosticSummary
            )
    }

    func start() {
        cancel()
        state.begin()
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        SpaceFixtureAXSuppressionConsumerSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        SpaceFixtureAXSuppressionConsumerSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        state.cancel()
        conditionOwner.cancel()
    }

    deinit {
        cancel()
    }

    private static func distributedVerificationRegistration(
        route: SpaceFixtureAXSuppressionUITestRoute
    ) -> SpaceFixtureAXSuppressionVerificationRegistration {
        { callback in
            let center =
                DistributedNotificationCenter.default()
            let token = center.addObserver(
                forName:
                    route.externalReadbackNotificationName,
                object: nil,
                queue: .main
            ) { notification in
                guard let verification =
                        parseVerification(notification)
                else {
                    return
                }
                callback(verification)
            }
            return FlowTabUITestObservationCancellation {
                center.removeObserver(token)
            }
        }
    }

    private static func parseVerification(
        _ notification: Notification
    ) -> SpaceFixtureAXSuppressionReadbackVerification? {
        let userInfo = notification.userInfo
        guard let verificationGeneration =
                number(userInfo, "verificationGeneration")?
                    .uint64Value,
              verificationGeneration > 0,
              let suppressionGeneration =
                number(userInfo, "suppressionGeneration")?
                    .uint64Value,
              suppressionGeneration > 0,
              let acknowledgementGeneration =
                number(userInfo, "acknowledgementGeneration")?
                    .uint64Value,
              acknowledgementGeneration > 0,
              let bundleIdentifier =
                userInfo?["bundleIdentifier"] as? String,
              !bundleIdentifier.isEmpty,
              let processIdentifier =
                number(userInfo, "processIdentifier")?
                    .int32Value,
              processIdentifier > 0,
              let windowCount =
                number(userInfo, "windowCount")?.intValue,
              windowCount > 0,
              let sourceGeneration =
                userInfo?["sourceGeneration"] as? String,
              !sourceGeneration.isEmpty,
              let childWindowCount =
                number(userInfo, "childWindowCount")?
                    .intValue,
              let windowsAttributeCount =
                number(userInfo, "windowsAttributeCount")?
                    .intValue,
              let externalProcessIsRunning =
                number(userInfo, "externalProcessIsRunning")?
                    .boolValue,
              let externalChildrenError =
                number(userInfo, "externalChildrenError")?
                    .int32Value,
              let externalChildrenCount =
                number(userInfo, "externalChildrenCount")?
                    .intValue,
              let externalWindowsError =
                number(userInfo, "externalWindowsError")?
                    .int32Value,
              let externalWindowsCount =
                number(userInfo, "externalWindowsCount")?
                    .intValue
        else {
            return nil
        }
        return SpaceFixtureAXSuppressionReadbackVerification(
            verificationGeneration: verificationGeneration,
            suppressionGeneration: suppressionGeneration,
            acknowledgementGeneration:
                acknowledgementGeneration,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            windowCount: windowCount,
            sourceGeneration: sourceGeneration,
            childWindowCount: childWindowCount,
            windowsAttributeCount: windowsAttributeCount,
            externalProcessIsRunning:
                externalProcessIsRunning,
            externalChildrenError:
                externalChildrenError,
            externalChildrenCount:
                externalChildrenCount,
            externalWindowsError:
                externalWindowsError,
            externalWindowsCount:
                externalWindowsCount
        )
    }

    private static func number(
        _ userInfo: [AnyHashable: Any]?,
        _ key: String
    ) -> NSNumber? {
        userInfo?[key] as? NSNumber
    }
}
