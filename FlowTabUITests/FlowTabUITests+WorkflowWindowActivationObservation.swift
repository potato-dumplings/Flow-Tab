import AppKit
import ApplicationServices
import Foundation
import XCTest

enum FlowTabUITestWorkflowWindowActivationObservationPolicy {
    static let edgeInputsExactWindowWatchdog: TimeInterval = 10
    static let multiAppWindowSearchActivationWatchdog: TimeInterval = 10
    static let fullscreenMultiAppWindowSearchActivationWatchdog: TimeInterval = 12
}

struct FlowTabUITestWorkflowWindowActivationSnapshot: Equatable {
    let frontmostBundleIdentifier: String?
    let topmostCGWindow: WorkflowCGWindowObservation?
    let activeWindowTitle: String?
    let expectedTitleIsObservable: Bool

    func matches(
        bundleIdentifier: String,
        windowNumber: CGWindowID
    ) -> Bool {
        frontmostBundleIdentifier == bundleIdentifier
            && topmostCGWindow?.number == windowNumber
    }

    var diagnosticSummary: String {
        let windowSummary = topmostCGWindow.map {
            "\($0.number):\($0.title ?? "nil")@\(String(describing: $0.frame))"
        } ?? "nil"
        return "frontmostBundle=\(frontmostBundleIdentifier ?? "nil") "
            + "topmostCGWindow=\(windowSummary) "
            + "activeWindowTitle=\(activeWindowTitle ?? "nil") "
            + "expectedTitleIsObservable=\(expectedTitleIsObservable)"
    }
}

final class FlowTabUITestWorkflowWindowActivationObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestWorkflowWindowActivationSnapshot
        >

    init(
        expectedBundleIdentifier: String,
        expectedWindowNumber: CGWindowID,
        expectedTitle: String,
        acceptsEvidence: @escaping () -> Bool = {
            true
        },
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestWorkflowWindowActivationSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: { snapshot in
                acceptsEvidence()
                    && snapshot.matches(
                        bundleIdentifier: expectedBundleIdentifier,
                        windowNumber: expectedWindowNumber
                    )
            },
            describe: { snapshot in
                "acceptanceEnabled=\(acceptsEvidence()) "
                    + "expectedBundle=\(expectedBundleIdentifier) "
                    + "expectedWindowNumber=\(expectedWindowNumber) "
                    + "expectedTitle=\(expectedTitle) "
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestWorkflowWindowActivationSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestWorkflowWindowActivationSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestWorkflowWindowActivationSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

private final class FlowTabUITestWorkflowWindowAXEventSource {
    private final class Context {
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?

        init(
            readback: @escaping (
                FlowTabUITestConditionObservationSource
            ) -> Void
        ) {
            self.readback = readback
        }
    }

    private let observer: AXObserver
    private let applicationElement: AXUIElement
    private let context: Context
    private let registeredNotifications: [CFString]
    private var isCancelled = false

    init?(
        processIdentifier: pid_t,
        readback: @escaping (
            FlowTabUITestConditionObservationSource
        ) -> Void
    ) {
        let context = Context(readback: readback)
        var observerReference: AXObserver?
        let createResult = AXObserverCreate(
            processIdentifier,
            Self.callback,
            &observerReference
        )
        guard createResult == .success,
              let observerReference
        else {
            return nil
        }

        let applicationElement =
            AXUIElementCreateApplication(processIdentifier)
        let contextPointer = UnsafeMutableRawPointer(
            Unmanaged.passUnretained(context).toOpaque()
        )
        let watchedNotifications: [CFString] = [
            kAXFocusedWindowChangedNotification as CFString,
            kAXMainWindowChangedNotification as CFString
        ]
        let registeredNotifications = watchedNotifications.filter {
            notification in
            let result = AXObserverAddNotification(
                observerReference,
                applicationElement,
                notification,
                contextPointer
            )
            return result == .success
                || result == .notificationAlreadyRegistered
        }
        guard !registeredNotifications.isEmpty else {
            return nil
        }

        self.observer = observerReference
        self.applicationElement = applicationElement
        self.context = context
        self.registeredNotifications = registeredNotifications
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observerReference),
            .defaultMode
        )
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        context.readback = nil
        for notification in registeredNotifications {
            AXObserverRemoveNotification(
                observer,
                applicationElement,
                notification
            )
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }

    deinit {
        cancel()
    }

    private static let callback: AXObserverCallback = {
        _, _, _, refcon in
        guard let refcon else { return }
        let context = Unmanaged<Context>
            .fromOpaque(refcon)
            .takeUnretainedValue()
        context.readback?(.notificationReadback)
    }
}

private final class FlowTabUITestWorkflowWindowEventSources {
    private let notificationCenter: NotificationCenter
    private var workspaceActivationToken: NSObjectProtocol?
    private var axEventSource:
        FlowTabUITestWorkflowWindowAXEventSource?
    private var scheduledReadbackCancellation:
        FlowTabUITestObservationCancellation?
    private var isCancelled = false

    init(
        bundleIdentifier: String,
        notificationCenter: NotificationCenter =
            NSWorkspace.shared.notificationCenter,
        readback: @escaping (
            FlowTabUITestConditionObservationSource
        ) -> Void
    ) {
        self.notificationCenter = notificationCenter
        workspaceActivationToken = notificationCenter.addObserver(
            forName:
                NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            readback(.notificationReadback)
        }

        if let processIdentifier = NSRunningApplication
            .runningApplications(
                withBundleIdentifier: bundleIdentifier
            )
            .first(where: { !$0.isTerminated })?
            .processIdentifier
        {
            axEventSource =
                FlowTabUITestWorkflowWindowAXEventSource(
                    processIdentifier: processIdentifier,
                    readback: readback
                )
        }

        scheduledReadbackCancellation =
            FlowTabUITestConditionReadbackScheduler
                .mainRunLoopRegistration(
                    cadence:
                        FlowTabUITestConditionObservationPolicy
                            .xcuiReadbackCadence
                )(readback)
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        scheduledReadbackCancellation?.cancel()
        scheduledReadbackCancellation = nil
        axEventSource?.cancel()
        axEventSource = nil
        if let workspaceActivationToken {
            notificationCenter.removeObserver(
                workspaceActivationToken
            )
            self.workspaceActivationToken = nil
        }
    }

    deinit {
        cancel()
    }
}

enum FlowTabUITestWorkflowWindowActivationObservation {
    static func registration(
        bundleIdentifier: String
    ) -> FlowTabUITestConditionObservationRegistration {
        { readback in
            let eventSources =
                FlowTabUITestWorkflowWindowEventSources(
                    bundleIdentifier: bundleIdentifier,
                    readback: readback
                )
            return FlowTabUITestObservationCancellation {
                eventSources.cancel()
            }
        }
    }
}

extension FlowTabUITests {
    func triggerAndWaitForFrontmostWorkflowWindow(
        windowNumber: CGWindowID,
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App,
        timeout: TimeInterval,
        trigger: () -> Void
    ) -> Bool {
        var triggerCompleted = false
        let bundleIdentifier =
            workflowApp.identity.bundleIdentifier
        let owner =
            FlowTabUITestWorkflowWindowActivationObservationOwner(
                expectedBundleIdentifier: bundleIdentifier,
                expectedWindowNumber: windowNumber,
                expectedTitle: title,
                acceptsEvidence: {
                    triggerCompleted
                },
                observationRegistration:
                    FlowTabUITestWorkflowWindowActivationObservation
                        .registration(
                            bundleIdentifier: bundleIdentifier
                        ),
                readback: {
                    self.workflowWindowActivationSnapshot(
                        title: title,
                        app: workflowApp
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        trigger()
        triggerCompleted = true

        guard
            owner.waitForResolution(timeout: timeout) != nil
        else {
            XCTFail(
                "Expected exact frontmost workflow window "
                    + "\(workflowApp.appName) / \(title) / "
                    + "\(windowNumber). "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    func workflowWindowActivationSnapshot(
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> FlowTabUITestWorkflowWindowActivationSnapshot {
        let bundleIdentifier =
            workflowApp.identity.bundleIdentifier
        return FlowTabUITestWorkflowWindowActivationSnapshot(
            frontmostBundleIdentifier:
                NSWorkspace.shared
                    .frontmostApplication?
                    .bundleIdentifier,
            topmostCGWindow:
                topmostOnScreenCGWindow(
                    forBundleIdentifier:
                        bundleIdentifier
                ),
            activeWindowTitle:
                activeWindowTitle(
                    forBundleIdentifier:
                        bundleIdentifier
                ),
            expectedTitleIsObservable:
                workflowWindowTitleIsObservable(
                    title,
                    app: workflowApp
                )
        )
    }
}
