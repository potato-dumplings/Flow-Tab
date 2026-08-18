import AppKit
import Foundation
import XCTest

enum FlowTabUITestAverageLuminanceObservationPolicy {
    static let settingsThemeTransitionWatchdog: TimeInterval = 5
}

struct FlowTabUITestAverageLuminanceSnapshot: Equatable {
    let identifier: String
    let exists: Bool
    let luminance: CGFloat?

    var diagnosticSummary: String {
        "identifier=\(identifier) "
            + "exists=\(exists) "
            + "luminance="
            + "\(luminance.map(String.init) ?? "nil")"
    }
}

final class FlowTabUITestAverageLuminanceObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestAverageLuminanceSnapshot
        >

    init(
        expectedDescription: String,
        acceptsEvidence: @escaping () -> Bool = {
            true
        },
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestAverageLuminanceSnapshot,
        isSatisfied: @escaping (CGFloat) -> Bool
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: { snapshot in
                acceptsEvidence()
                    && snapshot.exists
                    && snapshot.luminance.map(isSatisfied) == true
            },
            describe: { snapshot in
                "acceptanceEnabled=\(acceptsEvidence()) "
                    + "expected{\(expectedDescription)} "
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func requestReadback(
        source: FlowTabUITestConditionObservationSource
    ) {
        conditionOwner.requestReadback(source: source)
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestAverageLuminanceSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestAverageLuminanceSnapshot
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

extension FlowTabUITests {
    func performAndWaitForAverageLuminance(
        of element: XCUIElement,
        expectedDescription: String,
        watchdog: TimeInterval,
        trigger: () -> Void,
        matching predicate: @escaping (CGFloat) -> Bool
    ) -> CGFloat? {
        var triggerCompleted = false
        let owner =
            FlowTabUITestAverageLuminanceObservationOwner(
                expectedDescription: expectedDescription,
                acceptsEvidence: {
                    triggerCompleted
                },
                readback: {
                    self.averageLuminanceSnapshot(
                        of: element
                    )
                },
                isSatisfied: predicate
            )
        owner.start()
        defer { owner.cancel() }

        trigger()
        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        guard
            let evidence = owner.waitForResolution(
                timeout: watchdog
            )
        else {
            XCTFail(
                "Average luminance did not satisfy "
                    + "\(expectedDescription). "
                    + owner.diagnosticSummary
            )
            return nil
        }
        return evidence.value.luminance
    }

    private func averageLuminanceSnapshot(
        of element: XCUIElement
    ) -> FlowTabUITestAverageLuminanceSnapshot {
        let exists = element.exists
        return FlowTabUITestAverageLuminanceSnapshot(
            identifier: element.identifier,
            exists: exists,
            luminance:
                exists
                    ? averageLuminance(of: element)
                    : nil
        )
    }

    private func averageLuminance(
        of element: XCUIElement
    ) -> CGFloat? {
        guard
            let bitmap = NSBitmapImageRep(
                data: element.screenshot().pngRepresentation
            ),
            bitmap.pixelsWide > 0,
            bitmap.pixelsHigh > 0
        else {
            return nil
        }

        let sampleStep = max(
            1,
            min(bitmap.pixelsWide, bitmap.pixelsHigh) / 80
        )
        var total: CGFloat = 0
        var samples = 0
        for y in stride(
            from: 0,
            to: bitmap.pixelsHigh,
            by: sampleStep
        ) {
            for x in stride(
                from: 0,
                to: bitmap.pixelsWide,
                by: sampleStep
            ) {
                guard
                    let color = bitmap.colorAt(
                        x: x,
                        y: y
                    )?.usingColorSpace(.sRGB)
                else {
                    continue
                }
                total +=
                    color.redComponent * 0.2126
                    + color.greenComponent * 0.7152
                    + color.blueComponent * 0.0722
                samples += 1
            }
        }
        return samples > 0
            ? total / CGFloat(samples)
            : nil
    }
}
