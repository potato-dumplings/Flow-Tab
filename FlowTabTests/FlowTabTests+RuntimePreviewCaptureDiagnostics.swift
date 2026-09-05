import AppKit
import Foundation
import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testRuntimePreviewCaptureCollectorKeepsEachScreenshotStage() {
        let collector = RuntimeWindowPreviewCaptureDiagnosticCollector()
        let lookup = collector.begin(
            .shareableContentLookup,
            workUnits: 4
        )
        collector.end(lookup, workUnits: 12)
        collector.recordUnexecutedAfterShareableContentLookup(
            outcome: .notRequired,
            workUnits: 4
        )

        let spans = collector.spans()
        XCTAssertEqual(
            Set(spans.map(\.stage)),
            Set(RuntimeWindowPreviewCaptureDiagnosticStage.allCases)
        )
        XCTAssertEqual(
            spans.first {
                $0.stage == .shareableContentLookup
            }?.workUnits,
            12
        )
        XCTAssertTrue(
            spans.allSatisfy {
                $0.completedAtNanoseconds
                    >= $0.startedAtNanoseconds
                    && $0.startedCPU.isValid
                    && $0.completedCPU.isValid
            }
        )
    }

    func testRuntimePreviewImageProcessingRecordsTrimAndScale() {
        let width = 1_300
        let height = 650
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        XCTAssertNotNil(context)
        context?.setFillColor(NSColor.systemBlue.cgColor)
        context?.fill(
            CGRect(x: 0, y: 0, width: width, height: height)
        )
        guard let image = context?.makeImage() else {
            XCTFail("Expected a synthetic preview image")
            return
        }
        let collector = RuntimeWindowPreviewCaptureDiagnosticCollector()

        let result = RuntimeWindowPreviewCaptureDiagnosticContext.$current.withValue(collector) {
            let trimmed = RuntimeWindowPreviewProvider.trimmedTransparentPaddingIfNeededForTesting(image)
            return RuntimeWindowPreviewProvider.scaledPreviewImageIfNeededForTesting(trimmed)
        }

        XCTAssertEqual(result?.width, 1_200)
        XCTAssertEqual(result?.height, 600)
        let spans = collector.spans()
        XCTAssertEqual(
            spans.filter { $0.stage == .transparentTrim }.count,
            1
        )
        XCTAssertEqual(
            spans.filter { $0.stage == .imageScale }.count,
            1
        )
        XCTAssertTrue(
            spans.allSatisfy { $0.outcome == .completed }
        )
    }







    @MainActor
    func testControlTabOpenRequiresImportedScreenshotStages() {
        let clock = IncrementingRuntimePreviewDiagnosticCPUClock()
        let recorder = ControlTabPressureSpanRecorder(clock: clock)
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let token = makeRuntimePreviewDiagnosticToken(
            startedAt: startedAt
        )
        recorder.beginPhase(token)
        let screenshotComponents = Set([
            SwitcherInteractionComponent
                .previewShareableContentLookup,
            .previewScreenshotManagerCapture,
            .previewCoreGraphicsCapture,
            .previewTransparentTrim,
            .previewImageScale,
            .previewTitleBarInference
        ])
        for component in ControlTabPressureSpanRequirements.components(
            for: .open
        ) where !screenshotComponents.contains(component) {
            recorder.recordUnexecutedComponent(
                component,
                outcome: .notRequired
            )
        }
        for (index, component) in screenshotComponents.enumerated() {
            let start = startedAt
                + UInt64(index + 1) * 100_000
            recorder.recordPremeasuredComponent(
                SwitcherInteractionPremeasuredComponentSpan(
                    component: component,
                    parent: .previewCapture,
                    startedAtNanoseconds: start,
                    completedAtNanoseconds: start + 50_000,
                    startedCPUUserNanoseconds:
                        UInt64(index + 1) * 100,
                    startedCPUSystemNanoseconds: 0,
                    startedCPUIsValid: true,
                    completedCPUUserNanoseconds:
                        UInt64(index + 1) * 100 + 50,
                    completedCPUSystemNanoseconds: 0,
                    completedCPUIsValid: true,
                    outcome: .completed,
                    workUnits: index + 1
                )
            )
        }

        let completedAt = max(
            DispatchTime.now().uptimeNanoseconds,
            startedAt + 1_000_000
        )
        let evidence = recorder.finishPhase(
            completedAtNanoseconds: completedAt,
            completedCPU: ControlTabProcessCPUSnapshot(
                userNanoseconds: 10_000,
                systemNanoseconds: 0
            )
        )

        XCTAssertTrue(evidence.requiredComponentsPresent)
        XCTAssertTrue(evidence.timelineReconciled)
        XCTAssertTrue(evidence.componentTimingValid)
        for component in screenshotComponents {
            XCTAssertTrue(
                evidence.spans.contains {
                    $0.name == component.rawValue
                        && $0.parent == "preview_capture"
                        && $0.scope == .componentInclusive
                }
            )
        }
    }

    private func makeRuntimePreviewDiagnosticToken(
        startedAt: UInt64
    ) -> ControlTabPressureMeasurementToken {
        ControlTabPressureMeasurementToken(
            sequence: 42,
            phase: .open,
            startedAtNanoseconds: startedAt,
            startedCPU: ControlTabProcessCPUSnapshot(
                userNanoseconds: 0,
                systemNanoseconds: 0
            ),
            panelWasPresented: false,
            selectedAppIDBefore: nil,
            selectedWindowIDBefore: nil,
            selectedWindowCountBefore: 0,
            activationRequestGenerationBefore: 0,
            activationVerificationGenerationBefore: 0,
            completeProjectionUpdateGenerationBefore: 0,
            focusedSessionDiagnosticGenerationBefore: 0,
            windowContentRenderGenerationBefore: 0,
            reusableShellPreparationGenerationBefore: 0,
            panelHiddenGenerationBefore: 0,
            cleanupCompleteGenerationBefore: 0,
            presentationCleanupRequiredBefore: false
        )
    }
}

private final class IncrementingRuntimePreviewDiagnosticCPUClock:
    ControlTabProcessCPUClock
{
    private var totalNanoseconds: UInt64 = 1_000

    func snapshot() -> ControlTabProcessCPUSnapshot {
        totalNanoseconds &+= 1_000
        return ControlTabProcessCPUSnapshot(
            userNanoseconds: totalNanoseconds,
            systemNanoseconds: 0
        )
    }
}
