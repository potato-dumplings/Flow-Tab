import ApplicationServices
import CoreGraphics
import Darwin

enum FlowTabUITestAXWindowBridge {
    private static let symbolName = "_AXUIElementGetWindow"
    private typealias Function = @convention(c) (
        AXUIElement,
        UnsafeMutablePointer<CGWindowID>
    ) -> AXError

    static func windowNumber(
        for window: AXUIElement
    ) -> CGWindowID? {
        guard let function else { return nil }
        var windowNumber: CGWindowID = 0
        guard function(window, &windowNumber) == .success,
              windowNumber != 0
        else {
            return nil
        }
        return windowNumber
    }

    private static let function: Function? = {
        let handles = [
            UnsafeMutableRawPointer(bitPattern: -2),
            dlopen(
                "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
                RTLD_LAZY
            ),
            dlopen(
                "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
                RTLD_LAZY
            )
        ]
        for handle in handles {
            guard let handle,
                  let symbol = dlsym(handle, symbolName)
            else {
                continue
            }
            return unsafeBitCast(symbol, to: Function.self)
        }
        return nil
    }()
}
