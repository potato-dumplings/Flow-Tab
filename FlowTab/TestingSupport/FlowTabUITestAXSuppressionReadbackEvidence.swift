#if FLOWTAB_TESTING
import ApplicationServices
import AppKit
import Foundation

struct FlowTabUITestAXSuppressionReadbackRoute:
    Equatable
{
    let completionNotificationName: Notification.Name
    let verificationNotificationName: Notification.Name
    let bundleIdentifier: String
    let expectedWindowCount: Int

    var key: String {
        completionNotificationName.rawValue
    }
}

struct FlowTabUITestAXSuppressionCompletion: Equatable {
    let suppressionGeneration: UInt64
    let acknowledgementGeneration: UInt64
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let windowCount: Int
    let sourceGeneration: String
    let childWindowCount: Int
    let windowsAttributeCount: Int
}

struct FlowTabUITestAXAttributeReadback: Equatable {
    let errorCode: AXError.RawValue
    let elementCount: Int?
}

struct FlowTabUITestAXSuppressionApplicationReadback:
    Equatable
{
    let exactProcessIsRunning: Bool
    let children: FlowTabUITestAXAttributeReadback
    let windows: FlowTabUITestAXAttributeReadback

    var isSuppressed: Bool {
        exactProcessIsRunning
            && children.errorCode == AXError.success.rawValue
            && children.elementCount == 0
            && windows.errorCode == AXError.success.rawValue
            && windows.elementCount == 0
    }

    static func live(
        completion: FlowTabUITestAXSuppressionCompletion
    ) -> Self {
        let isRunning = NSRunningApplication
            .runningApplications(
                withBundleIdentifier:
                    completion.bundleIdentifier
            )
            .contains {
                !$0.isTerminated
                    && $0.processIdentifier
                        == completion.processIdentifier
            }
        let applicationElement =
            AXUIElementCreateApplication(
                completion.processIdentifier
            )
        return Self(
            exactProcessIsRunning: isRunning,
            children: read(
                applicationElement,
                attribute: kAXChildrenAttribute as CFString
            ),
            windows: read(
                applicationElement,
                attribute: kAXWindowsAttribute as CFString
            )
        )
    }

    private static func read(
        _ element: AXUIElement,
        attribute: CFString
    ) -> FlowTabUITestAXAttributeReadback {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            attribute,
            &value
        )
        let count: Int?
        if error == .success,
           let value,
           CFGetTypeID(value) == CFArrayGetTypeID()
        {
            count = CFArrayGetCount(value as! CFArray)
        } else {
            count = nil
        }
        return FlowTabUITestAXAttributeReadback(
            errorCode: error.rawValue,
            elementCount: count
        )
    }
}

enum FlowTabUITestAXSuppressionReadbackSource:
    String,
    Equatable
{
    case completionNotification
    case scheduledReadback
}

struct FlowTabUITestAXSuppressionReadbackEvidence:
    Equatable
{
    let observationGeneration: UInt64
    let verificationGeneration: UInt64
    let source: FlowTabUITestAXSuppressionReadbackSource
    let route: FlowTabUITestAXSuppressionReadbackRoute
    let completion: FlowTabUITestAXSuppressionCompletion
    let readback:
        FlowTabUITestAXSuppressionApplicationReadback
}

enum FlowTabUITestAXSuppressionReadbackPolicy {
    static let propagationReadbackCadence:
        TimeInterval = 0.1
}

enum FlowTabUITestAXSuppressionReadbackTransport {
    static func post(
        _ evidence:
            FlowTabUITestAXSuppressionReadbackEvidence
    ) {
        let completion = evidence.completion
        let readback = evidence.readback
        DistributedNotificationCenter.default()
            .postNotificationName(
                evidence.route.verificationNotificationName,
                object: nil,
                userInfo: [
                    "verificationGeneration":
                        NSNumber(
                            value:
                                evidence
                                    .verificationGeneration
                        ),
                    "suppressionGeneration":
                        NSNumber(
                            value:
                                completion
                                    .suppressionGeneration
                        ),
                    "acknowledgementGeneration":
                        NSNumber(
                            value:
                                completion
                                    .acknowledgementGeneration
                        ),
                    "bundleIdentifier":
                        completion.bundleIdentifier,
                    "processIdentifier":
                        NSNumber(
                            value:
                                completion.processIdentifier
                        ),
                    "windowCount":
                        NSNumber(
                            value: completion.windowCount
                        ),
                    "sourceGeneration":
                        completion.sourceGeneration,
                    "childWindowCount":
                        NSNumber(
                            value:
                                completion.childWindowCount
                        ),
                    "windowsAttributeCount":
                        NSNumber(
                            value:
                                completion
                                    .windowsAttributeCount
                        ),
                    "externalProcessIsRunning":
                        NSNumber(
                            value:
                                readback
                                    .exactProcessIsRunning
                        ),
                    "externalChildrenError":
                        NSNumber(
                            value:
                                readback.children.errorCode
                        ),
                    "externalChildrenCount":
                        NSNumber(
                            value:
                                readback.children.elementCount
                                    ?? -1
                        ),
                    "externalWindowsError":
                        NSNumber(
                            value:
                                readback.windows.errorCode
                        ),
                    "externalWindowsCount":
                        NSNumber(
                            value:
                                readback.windows.elementCount
                                    ?? -1
                        ),
                ],
                deliverImmediately: true
            )
        RuntimeLog.info(
            "UITest",
            "external application AX suppression readback "
                + "generation="
                + "\(evidence.verificationGeneration) "
                + "bundleID=\(completion.bundleIdentifier) "
                + "pid=\(completion.processIdentifier) "
                + "source=\(evidence.source.rawValue)"
        )
    }
}
#endif
