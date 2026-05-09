import AppKit
import CoreGraphics
import Darwin
import Foundation

enum RuntimeCGWindowFocusBridge {
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
        guard let api = runtimeAPI else { return false }

        var processSerialNumber = ProcessSerialNumber()
        guard api.getProcessForPID(ownerPID, &processSerialNumber) == noErr else {
            return false
        }

        let frontProcessResult = withUnsafeMutablePointer(to: &processSerialNumber) { pointer in
            api.setFrontProcessWithOptions(pointer, cgWindowID, userGeneratedFocusMode)
        }
        guard frontProcessResult == .success else {
            RuntimeLog.info(
                "Activation",
                "cg-window-focus set-front failed pid=\(ownerPID) windowID=\(cgWindowID) error=\(frontProcessResult.rawValue)"
            )
            return false
        }

        let keyWindowResult = postKeyWindowEvent(
            processSerialNumber: &processSerialNumber,
            cgWindowID: cgWindowID,
            api: api
        )
        if !keyWindowResult {
            RuntimeLog.info(
                "Activation",
                "cg-window-focus key-event failed pid=\(ownerPID) windowID=\(cgWindowID)"
            )
        }
        return true
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
