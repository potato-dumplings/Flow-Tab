import Combine
import Foundation

enum CommandTabTakeoverRegistrationState: Equatable, Sendable {
    case pending
    case active
    case inactive
}

@MainActor
final class HotkeyRegistrationObservationOwner: ObservableObject {
    typealias EvidenceProvider = @MainActor () -> HotkeyRegistrationEvidence?

    @Published private(set) var latestEvidence: HotkeyRegistrationEvidence?
    @Published private(set) var pendingRequest: HotkeyRegistrationRequest?

    private let notificationCenter: NotificationCenter
    private let evidenceProvider: EvidenceProvider
    private var observer: NSObjectProtocol?
    private var observationGeneration: UInt64 = 0
    private var latestObservedEvidenceGeneration: UInt64 = 0

    init(
        notificationCenter: NotificationCenter = .default,
        evidenceProvider: EvidenceProvider? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.evidenceProvider = evidenceProvider ?? {
            AppDelegate.shared?.latestHotkeyRegistrationEvidence
        }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    func start() {
        guard observer == nil else {
            readback()
            return
        }

        observationGeneration &+= 1
        let generation = observationGeneration
        observer = notificationCenter.addObserver(
            forName: .flowTabHotkeyRegistrationEvidenceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard
                    let self,
                    generation == self.observationGeneration,
                    self.observer != nil,
                    let evidence =
                        HotkeyRegistrationEvidence(
                            notification: notification
                        )
                else {
                    return
                }
                self.accept(evidence)
            }
        }

        readback()
    }

    func suspend() {
        observationGeneration &+= 1
        if let observer {
            notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        if pendingRequest != nil {
            pendingRequest = nil
        }
    }

    func stop() {
        suspend()
        if latestEvidence != nil {
            latestEvidence = nil
        }
        latestObservedEvidenceGeneration = 0
    }

    func prepare(for request: HotkeyRegistrationRequest) {
        start()
        pendingRequest = latestEvidence?.requestID == request.requestID ? nil : request
    }

    func readback() {
        guard let evidence = evidenceProvider() else { return }
        accept(evidence)
    }

    func hasMatchingRegistration(
        for request: HotkeyRegistrationRequest
    ) -> Bool {
        start()
        return latestEvidence?
            .matchesConfiguration(of: request) == true
    }

    func takeoverState(
        matching request: HotkeyRegistrationRequest
    ) -> CommandTabTakeoverRegistrationState {
        if let pendingRequest,
           pendingRequest.requestID == request.requestID
            || (
                pendingRequest.mainConfiguration == request.mainConfiguration
                    && pendingRequest.inAppWindowConfiguration == request.inAppWindowConfiguration
            )
        {
            return .pending
        }

        guard
            let latestEvidence,
            latestEvidence.matchesConfiguration(of: request)
        else {
            return .pending
        }
        return latestEvidence.commandTabTakeoverActive ? .active : .inactive
    }

    private func accept(_ evidence: HotkeyRegistrationEvidence) {
        guard evidence.generation > latestObservedEvidenceGeneration else { return }
        latestObservedEvidenceGeneration = evidence.generation
        latestEvidence = evidence

        guard let pendingRequest else { return }
        if evidence.requestID == pendingRequest.requestID
            || evidence.matchesConfiguration(of: pendingRequest)
        {
            self.pendingRequest = nil
        }
    }
}
