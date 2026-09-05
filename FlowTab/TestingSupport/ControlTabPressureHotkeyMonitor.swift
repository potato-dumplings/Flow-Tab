#if FLOWTAB_TESTING
import Foundation
import FlowTabCore

final class ControlTabPressureHotkeyMonitor: HotkeyMonitoring {
    let base: any HotkeyMonitoring
    let inputSourceID = HotkeyInputSourceID()
    var onHotkeyEvent: ((HotkeyInputEvent) -> Void)?
    private let originalHandler: ((HotkeyInputEvent) -> Void)?
    private let recorder: ControlTabPressureSpanRecorder
    private var sequence: UInt64 = 0
    private var isInstalled = true

    init(base: any HotkeyMonitoring, recorder: ControlTabPressureSpanRecorder) {
        self.base = base
        self.recorder = recorder
        originalHandler = base.onHotkeyEvent
        onHotkeyEvent = originalHandler
        base.onHotkeyEvent = { [weak self] event in
            self?.dispatch(phase: event.phase, isBackward: event.isBackward,
                           holdSetPressedEvidence: event.holdSetPressedEvidence)
        }
    }

    func start() { base.start() }
    func stop() { base.stop() }
    func requireChordEventMonitoring() { base.requireChordEventMonitoring() }

    func dispatch(phase: HotkeyInputEvent.Phase, isBackward: Bool, holdSetPressedEvidence: Bool? = nil) {
        guard isInstalled else { return }
        MainActor.assumeIsolated {
            sequence &+= 1
            let event = HotkeyInputEvent(identity: .init(sourceID: inputSourceID, sequence: sequence),
                phase: phase, isBackward: isBackward, holdSetPressedEvidence: holdSetPressedEvidence)
            let token = phase == .pressed
                ? recorder.beginComponent(.inputRouting, parent: nil, workUnits: 1) : nil
            defer { recorder.endComponent(token) }
            onHotkeyEvent?(event)
        }
    }

    func uninstall() {
        guard isInstalled else { return }
        isInstalled = false
        base.onHotkeyEvent = originalHandler
    }
}
#endif
