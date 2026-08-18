#if FLOWTAB_TESTING
import Foundation

@MainActor
final class FlowTabUITestAXSuppressionReadbackOwner {
    private struct RouteState {
        let route: FlowTabUITestAXSuppressionReadbackRoute
        var completionToken:
            (any FlowTabUITestAXSuppressionReadbackCancellable)?
        var retryToken:
            (any FlowTabUITestAXSuppressionReadbackCancellable)?
        var latestCompletion:
            FlowTabUITestAXSuppressionCompletion?
        var lastReadback:
            FlowTabUITestAXSuppressionApplicationReadback?
        var publishedSuppressionGeneration: UInt64?
    }

    let routes: [FlowTabUITestAXSuppressionReadbackRoute]

    private let completionRegistration:
        FlowTabUITestAXSuppressionCompletionRegistration
    private let scheduler:
        any FlowTabUITestAXSuppressionReadbackScheduling
    private let readback: @MainActor (
        FlowTabUITestAXSuppressionCompletion
    ) -> FlowTabUITestAXSuppressionApplicationReadback
    private let publisher: @MainActor (
        FlowTabUITestAXSuppressionReadbackEvidence
    ) -> Void
    private var states: [String: RouteState] = [:]
    private var activeObservationGeneration: UInt64?

    private(set) var observationGeneration: UInt64 = 0
    private(set) var verificationGeneration: UInt64 = 0

    init(
        routes: [FlowTabUITestAXSuppressionReadbackRoute],
        completionRegistration:
            FlowTabUITestAXSuppressionCompletionRegistration? =
                nil,
        scheduler:
            (any
                FlowTabUITestAXSuppressionReadbackScheduling)? =
                nil,
        readback: @escaping @MainActor (
            FlowTabUITestAXSuppressionCompletion
        ) -> FlowTabUITestAXSuppressionApplicationReadback = {
            FlowTabUITestAXSuppressionApplicationReadback
                .live(completion: $0)
        },
        publisher: @escaping @MainActor (
            FlowTabUITestAXSuppressionReadbackEvidence
        ) -> Void
    ) {
        self.routes = routes
        self.completionRegistration =
            completionRegistration
            ?? Self.distributedCompletionRegistration
        self.scheduler = scheduler
            ?? FlowTabUITestAXSuppressionReadbackScheduler()
        self.readback = readback
        self.publisher = publisher
    }

    var isObserving: Bool {
        activeObservationGeneration != nil
            && states.values.allSatisfy {
                $0.completionToken != nil
            }
    }

    @discardableResult
    func start() -> UInt64 {
        cancel(invalidate: false)
        observationGeneration &+= 1
        let generation = observationGeneration
        activeObservationGeneration = generation
        states = Dictionary(
            uniqueKeysWithValues: routes.map {
                (
                    $0.key,
                    RouteState(
                        route: $0,
                        completionToken: nil,
                        retryToken: nil,
                        latestCompletion: nil,
                        lastReadback: nil,
                        publishedSuppressionGeneration: nil
                    )
                )
            }
        )
        for route in routes {
            let token = completionRegistration(route) {
                [weak self] completion in
                self?.observe(
                    completion,
                    routeKey: route.key,
                    observationGeneration: generation
                )
            }
            guard activeObservationGeneration == generation,
                  var state = states[route.key]
            else {
                token.cancel()
                continue
            }
            state.completionToken = token
            states[route.key] = state
        }
        return generation
    }

    func cancel() {
        cancel(invalidate: true)
    }

    private func observe(
        _ completion: FlowTabUITestAXSuppressionCompletion,
        routeKey: String,
        observationGeneration: UInt64
    ) {
        guard activeObservationGeneration
                == observationGeneration,
              var state = states[routeKey],
              completion.bundleIdentifier
                == state.route.bundleIdentifier,
              completion.windowCount
                == state.route.expectedWindowCount,
              completion.childWindowCount == 0,
              completion.windowsAttributeCount == 0,
              completion.suppressionGeneration
                > (
                    state.latestCompletion?
                        .suppressionGeneration ?? 0
                )
        else {
            return
        }
        state.retryToken?.cancel()
        state.retryToken = nil
        state.latestCompletion = completion
        state.lastReadback = nil
        states[routeKey] = state
        resolve(
            routeKey: routeKey,
            completion: completion,
            source: .completionNotification,
            observationGeneration:
                observationGeneration
        )
    }

    private func resolve(
        routeKey: String,
        completion: FlowTabUITestAXSuppressionCompletion,
        source: FlowTabUITestAXSuppressionReadbackSource,
        observationGeneration: UInt64
    ) {
        guard activeObservationGeneration
                == observationGeneration,
              var state = states[routeKey],
              state.latestCompletion?
                .suppressionGeneration
                == completion.suppressionGeneration
        else {
            return
        }
        let currentReadback = readback(completion)
        state.lastReadback = currentReadback
        if currentReadback.isSuppressed {
            guard state.publishedSuppressionGeneration
                    != completion.suppressionGeneration
            else {
                states[routeKey] = state
                return
            }
            state.retryToken?.cancel()
            state.retryToken = nil
            state.publishedSuppressionGeneration =
                completion.suppressionGeneration
            verificationGeneration &+= 1
            let evidence =
                FlowTabUITestAXSuppressionReadbackEvidence(
                    observationGeneration:
                        observationGeneration,
                    verificationGeneration:
                        verificationGeneration,
                    source: source,
                    route: state.route,
                    completion: completion,
                    readback: currentReadback
                )
            states[routeKey] = state
            publisher(evidence)
            return
        }
        state.retryToken?.cancel()
        state.retryToken = scheduler.schedule(
            after:
                FlowTabUITestAXSuppressionReadbackPolicy
                    .propagationReadbackCadence
        ) { [weak self] in
            self?.retry(
                routeKey: routeKey,
                suppressionGeneration:
                    completion.suppressionGeneration,
                observationGeneration:
                    observationGeneration
            )
        }
        states[routeKey] = state
    }

    private func retry(
        routeKey: String,
        suppressionGeneration: UInt64,
        observationGeneration: UInt64
    ) {
        guard activeObservationGeneration
                == observationGeneration,
              var state = states[routeKey],
              let completion = state.latestCompletion,
              completion.suppressionGeneration
                == suppressionGeneration
        else {
            return
        }
        state.retryToken = nil
        states[routeKey] = state
        resolve(
            routeKey: routeKey,
            completion: completion,
            source: .scheduledReadback,
            observationGeneration:
                observationGeneration
        )
    }

    private func cancel(invalidate: Bool) {
        activeObservationGeneration = nil
        for state in states.values {
            state.completionToken?.cancel()
            state.retryToken?.cancel()
        }
        states.removeAll()
        if invalidate {
            observationGeneration &+= 1
        }
    }

    private static func distributedCompletionRegistration(
        route: FlowTabUITestAXSuppressionReadbackRoute,
        completion: @escaping @MainActor (
            FlowTabUITestAXSuppressionCompletion
        ) -> Void
    ) -> any FlowTabUITestAXSuppressionReadbackCancellable {
        let center = DistributedNotificationCenter.default()
        let token = center.addObserver(
            forName: route.completionNotificationName,
            object: nil,
            queue: .main
        ) { notification in
            guard let parsed = parse(notification) else {
                return
            }
            MainActor.assumeIsolated {
                completion(parsed)
            }
        }
        return FlowTabUITestAXSuppressionNotificationToken(
            center: center,
            token: token
        )
    }

    private static func parse(
        _ notification: Notification
    ) -> FlowTabUITestAXSuppressionCompletion? {
        let userInfo = notification.userInfo
        guard let suppressionGeneration =
                (
                    userInfo?["suppressionGeneration"]
                        as? NSNumber
                )?.uint64Value,
              suppressionGeneration > 0,
              let acknowledgementGeneration =
                (
                    userInfo?["acknowledgementGeneration"]
                        as? NSNumber
                )?.uint64Value,
              acknowledgementGeneration > 0,
              let bundleIdentifier =
                userInfo?["bundleIdentifier"] as? String,
              !bundleIdentifier.isEmpty,
              let processIdentifier =
                (
                    userInfo?["processIdentifier"]
                        as? NSNumber
                )?.int32Value,
              processIdentifier > 0,
              let windowCount =
                (
                    userInfo?["windowCount"] as? NSNumber
                )?.intValue,
              windowCount > 0,
              let sourceGeneration =
                userInfo?["sourceGeneration"] as? String,
              !sourceGeneration.isEmpty,
              let childWindowCount =
                (
                    userInfo?["childWindowCount"]
                        as? NSNumber
                )?.intValue,
              let windowsAttributeCount =
                (
                    userInfo?["windowsAttributeCount"]
                        as? NSNumber
                )?.intValue
        else {
            return nil
        }
        return FlowTabUITestAXSuppressionCompletion(
            suppressionGeneration: suppressionGeneration,
            acknowledgementGeneration:
                acknowledgementGeneration,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            windowCount: windowCount,
            sourceGeneration: sourceGeneration,
            childWindowCount: childWindowCount,
            windowsAttributeCount: windowsAttributeCount
        )
    }
}

@MainActor
enum FlowTabUITestAXSuppressionReadbackBootstrap {
    private static var owner:
        FlowTabUITestAXSuppressionReadbackOwner?

    static func prepareIfNeeded() {
        let routes =
            FlowTabTestLaunchOptions
                .axSuppressionReadbackRoutes
        guard !routes.isEmpty else {
            stop()
            return
        }
        guard owner?.routes != routes else { return }

        owner?.cancel()
        let nextOwner =
            FlowTabUITestAXSuppressionReadbackOwner(
                routes: routes,
                publisher: {
                    FlowTabUITestAXSuppressionReadbackTransport
                        .post($0)
                }
            )
        owner = nextOwner
        nextOwner.start()
    }

    static func stop() {
        owner?.cancel()
        owner = nil
    }
}
#endif
