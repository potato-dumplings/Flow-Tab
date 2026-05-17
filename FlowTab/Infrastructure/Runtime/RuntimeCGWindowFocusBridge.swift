import AppKit
import CoreGraphics
import Darwin
import Foundation

enum RuntimeCGWindowFocusBridge {
    enum FocusResult: Equatable {
        case accepted
        case acceptedKeyEventFailed
        case symbolUnavailable
        case processLookupFailed(OSStatus)
        case setFrontFailed(Int32)

        var isAccepted: Bool {
            switch self {
            case .accepted, .acceptedKeyEventFailed:
                true
            case .symbolUnavailable, .processLookupFailed, .setFrontFailed:
                false
            }
        }

        var debugName: String {
            switch self {
            case .accepted:
                "accepted"
            case .acceptedKeyEventFailed:
                "acceptedKeyEventFailed"
            case .symbolUnavailable:
                "symbolUnavailable"
            case .processLookupFailed(let status):
                "processLookupFailed(\(status))"
            case .setFrontFailed(let error):
                "setFrontFailed(\(error))"
            }
        }
    }

    private typealias GetProcessForPIDFn = @convention(c) (
        pid_t,
        UnsafeMutablePointer<ProcessSerialNumber>
    ) -> OSStatus
    private typealias SetFrontProcessWithOptionsFn = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>,
        CGWindowID,
        UInt32
    ) -> CGError
    private typealias PostEventRecordToFn = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>,
        UnsafeMutablePointer<UInt8>
    ) -> CGError

    private struct API {
        let getProcessForPID: GetProcessForPIDFn
        let setFrontProcessWithOptions: SetFrontProcessWithOptionsFn
        let postEventRecordTo: PostEventRecordToFn
    }

    private static let userGeneratedFocusMode: UInt32 = 0x200
    private static let keyWindowEventByteCount = 0xF8
    private static let keyWindowIDOffset = 0x3C

    static func focusWindow(ownerPID: pid_t, cgWindowID: CGWindowID) -> Bool {
        focusWindowDetailed(ownerPID: ownerPID, cgWindowID: cgWindowID).isAccepted
    }

    static func focusWindowDetailed(ownerPID: pid_t, cgWindowID: CGWindowID) -> FocusResult {
        guard let api = runtimeAPI else {
            RuntimeLog.debug(
                .activation,
                "cg-window-focus bridge result=\(FocusResult.symbolUnavailable.debugName) pid=\(ownerPID) windowID=\(cgWindowID)"
            )
            return .symbolUnavailable
        }

        var processSerialNumber = ProcessSerialNumber()
        let processLookupStatus = api.getProcessForPID(ownerPID, &processSerialNumber)
        guard processLookupStatus == noErr else {
            let result = FocusResult.processLookupFailed(processLookupStatus)
            RuntimeLog.debug(
                .activation,
                "cg-window-focus bridge result=\(result.debugName) pid=\(ownerPID) windowID=\(cgWindowID)"
            )
            return result
        }

        let frontProcessResult = withUnsafeMutablePointer(to: &processSerialNumber) { pointer in
            api.setFrontProcessWithOptions(pointer, cgWindowID, userGeneratedFocusMode)
        }
        guard frontProcessResult == .success else {
            let result = FocusResult.setFrontFailed(frontProcessResult.rawValue)
            RuntimeLog.debug(
                .activation,
                "cg-window-focus bridge result=\(result.debugName) pid=\(ownerPID) windowID=\(cgWindowID)"
            )
            return result
        }

        let keyWindowResult = postKeyWindowEvent(
            processSerialNumber: &processSerialNumber,
            cgWindowID: cgWindowID,
            api: api
        )
        if !keyWindowResult {
            RuntimeLog.debug(
                .activation,
                "cg-window-focus bridge result=\(FocusResult.acceptedKeyEventFailed.debugName) pid=\(ownerPID) windowID=\(cgWindowID)"
            )
            return .acceptedKeyEventFailed
        }
        return .accepted
    }

    private static func postKeyWindowEvent(
        processSerialNumber: inout ProcessSerialNumber,
        cgWindowID: CGWindowID,
        api: API
    ) -> Bool {
        var eventBytes = [UInt8](repeating: 0, count: keyWindowEventByteCount)
        eventBytes[0x04] = UInt8(keyWindowEventByteCount)
        eventBytes[0x3A] = 0x10
        withUnsafeBytes(of: cgWindowID) { windowIDBytes in
            eventBytes.replaceSubrange(
                keyWindowIDOffset..<(keyWindowIDOffset + MemoryLayout<CGWindowID>.size),
                with: windowIDBytes
            )
        }
        for index in 0x20..<0x30 {
            eventBytes[index] = 0xFF
        }

        let firstResult = postEvent(
            bytes: &eventBytes,
            phase: 0x01,
            processSerialNumber: &processSerialNumber,
            api: api
        )
        let secondResult = postEvent(
            bytes: &eventBytes,
            phase: 0x02,
            processSerialNumber: &processSerialNumber,
            api: api
        )
        return firstResult == .success && secondResult == .success
    }

    private static func postEvent(
        bytes: inout [UInt8],
        phase: UInt8,
        processSerialNumber: inout ProcessSerialNumber,
        api: API
    ) -> CGError {
        bytes[0x08] = phase
        return withUnsafeMutablePointer(to: &processSerialNumber) { processPointer in
            bytes.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return .failure }
                return api.postEventRecordTo(processPointer, baseAddress)
            }
        }
    }

    private static func loadSymbol<T>(
        handles: [UnsafeMutableRawPointer?],
        name: String,
        as type: T.Type
    ) -> T? {
        for handle in handles {
            guard let handle else { continue }
            guard let symbol = dlsym(handle, name) else { continue }
            return unsafeBitCast(symbol, to: T.self)
        }
        return nil
    }

    private static let runtimeAPI: API? = {
        let currentProcess = UnsafeMutableRawPointer(bitPattern: -2)
        let skyLight = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY
        )
        let applicationServices = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            RTLD_LAZY
        )
        let hiServices = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
            RTLD_LAZY
        )
        let handles = [currentProcess, skyLight, applicationServices, hiServices]

        guard
            let getProcessForPID = loadSymbol(
                handles: handles,
                name: "GetProcessForPID",
                as: GetProcessForPIDFn.self
            ),
            let setFrontProcessWithOptions = loadSymbol(
                handles: handles,
                name: "_SLPSSetFrontProcessWithOptions",
                as: SetFrontProcessWithOptionsFn.self
            ),
            let postEventRecordTo = loadSymbol(
                handles: handles,
                name: "SLPSPostEventRecordTo",
                as: PostEventRecordToFn.self
            )
        else {
            return nil
        }

        return API(
            getProcessForPID: getProcessForPID,
            setFrontProcessWithOptions: setFrontProcessWithOptions,
            postEventRecordTo: postEventRecordTo
        )
    }()
}
