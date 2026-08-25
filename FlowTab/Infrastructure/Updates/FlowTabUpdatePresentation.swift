import Combine
import Foundation

struct FlowTabAvailableUpdate: Equatable, Sendable {
    let displayVersion: String
    let buildVersion: String
}

enum FlowTabUpdateAvailability: Equatable, Sendable {
    case idle
    case available(FlowTabAvailableUpdate)

    var availableUpdate: FlowTabAvailableUpdate? {
        guard case let .available(update) = self else { return nil }
        return update
    }
}

enum FlowTabUpdatePresentationEvent: Equatable, Sendable {
    case updateFound(FlowTabAvailableUpdate)
    case currentVersionIsLatest
    case userDismissed
    case userSkipped
    case installConfirmed
    case transientFailure
}

enum FlowTabUpdatePresentationReducer {
    static func reduce(
        _ availability: FlowTabUpdateAvailability,
        event: FlowTabUpdatePresentationEvent
    ) -> FlowTabUpdateAvailability {
        switch event {
        case let .updateFound(update):
            return .available(update)
        case .currentVersionIsLatest, .userSkipped, .installConfirmed:
            return .idle
        case .userDismissed, .transientFailure:
            return availability
        }
    }
}

enum FlowTabUpdateChannelPolicy {
    static let prereleaseChannel = "prerelease"

    static func allowedChannels(for displayVersion: String) -> Set<String> {
        let normalized = displayVersion.lowercased()
        let prereleaseMarkers = ["-alpha", "-beta", "-rc"]
        guard prereleaseMarkers.contains(where: normalized.contains) else {
            return []
        }
        return [prereleaseChannel]
    }
}

enum FlowTabReleaseVersionPolicy {
    static func isValidBuild(_ build: String) -> Bool {
        guard let value = Int(build) else { return false }
        return value > 0
    }

    static func isCandidateBuild(
        _ candidate: String,
        newerThan baseline: String
    ) -> Bool {
        guard let candidateValue = Int(candidate),
              let baselineValue = Int(baseline),
              isValidBuild(candidate),
              isValidBuild(baseline)
        else {
            return false
        }
        return candidateValue > baselineValue
    }
}

@MainActor
protocol FlowTabUpdateCoordinating: AnyObject {
    func startIfNeeded()
    func checkForUpdates()
}

@MainActor
final class FlowTabUpdatePresentationStore: ObservableObject {
    static let shared = FlowTabUpdatePresentationStore()

    @Published private(set) var availability: FlowTabUpdateAvailability
    private var presentationAction: (@MainActor () -> Void)?

    init(availability: FlowTabUpdateAvailability = .idle) {
        self.availability = availability
    }

    func apply(_ event: FlowTabUpdatePresentationEvent) {
        availability = FlowTabUpdatePresentationReducer.reduce(
            availability,
            event: event
        )
    }

    func configurePresentationAction(
        _ action: (@MainActor () -> Void)?
    ) {
        presentationAction = action
    }

    func showAvailableUpdate() {
        presentationAction?()
    }
}
