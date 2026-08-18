import AppKit
import FlowTabCore
import SwiftUI
import XCTest
@testable import FlowTab

enum SettingsPresentationObservationPolicy {
    static let watchdogTimeout: TimeInterval = 1
}

struct SettingsPresentationUpdateEvidence: Equatable {
    let generation: UInt64
    let context: FlowPresentationContext

    var diagnosticSummary: String {
        [
            "generation=\(generation)",
            "theme=\(context.themeMode.rawValue)",
            "language=\(context.appLanguage.rawValue)",
            "system=\(context.systemColorScheme)",
            "resolved=\(context.resolvedColorScheme)",
            "target=\(context.targetNSAppearanceName.rawValue)"
        ].joined(separator: " ")
    }
}

@MainActor
final class SettingsPresentationUpdateObservation {
    private var cancellation: (@MainActor () -> Void)?

    init(cancellation: @escaping @MainActor () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        guard let cancellation else { return }
        self.cancellation = nil
        cancellation()
    }
}

@MainActor
final class SettingsPresentationUpdateRecorder {
    typealias Handler = @MainActor (SettingsPresentationUpdateEvidence) -> Void

    private var nextGeneration: UInt64 = 1
    private var observers: [UUID: (UInt64, Handler)] = [:]
    private(set) var latestEvidence: SettingsPresentationUpdateEvidence?

    func record(_ context: FlowPresentationContext) {
        let evidence = SettingsPresentationUpdateEvidence(
            generation: nextGeneration,
            context: context
        )
        nextGeneration &+= 1
        latestEvidence = evidence
        for (baselineGeneration, handler) in Array(observers.values)
        where evidence.generation > baselineGeneration {
            handler(evidence)
        }
    }

    func observe(
        after baselineGeneration: UInt64,
        handler: @escaping Handler
    ) -> SettingsPresentationUpdateObservation {
        let id = UUID()
        observers[id] = (baselineGeneration, handler)
        return SettingsPresentationUpdateObservation { [weak self] in
            self?.observers[id] = nil
        }
    }
}

@MainActor
struct SettingsPresentationObservedContent<Content: View>: View {
    @ObservedObject private var presentation = FlowPresentationState.shared

    let content: Content
    let recorder: SettingsPresentationUpdateRecorder

    var body: some View {
        content.overlay(alignment: .topLeading) {
            SettingsPresentationUpdateProbe(
                presentationContext: presentation.context,
                recorder: recorder
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

@MainActor
private struct SettingsPresentationUpdateProbe: NSViewRepresentable {
    let presentationContext: FlowPresentationContext
    let recorder: SettingsPresentationUpdateRecorder

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        recorder.record(presentationContext)
    }
}

extension FlowTabTests {
    @MainActor
    func awaitSettingsPresentationUpdate(
        recorder: SettingsPresentationUpdateRecorder,
        after baselineGeneration: UInt64,
        description: String,
        trigger: () -> Void,
        matches: @escaping @MainActor (SettingsPresentationUpdateEvidence) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> SettingsPresentationUpdateEvidence? {
        let updateArrived = expectation(description: description)
        var matchingEvidence: SettingsPresentationUpdateEvidence?
        var lastEvidence = recorder.latestEvidence
        let observation = recorder.observe(after: baselineGeneration) { evidence in
            lastEvidence = evidence
            guard matchingEvidence == nil, matches(evidence) else { return }
            matchingEvidence = evidence
            updateArrived.fulfill()
        }
        defer { observation.cancel() }

        trigger()
        await fulfillment(
            of: [updateArrived],
            timeout: SettingsPresentationObservationPolicy.watchdogTimeout
        )

        guard let matchingEvidence else {
            let baseline = "baselineGeneration=\(baselineGeneration)"
            let last = lastEvidence?.diagnosticSummary ?? "last=none"
            XCTFail(
                "\(description) watchdog expired: \(baseline) \(last)",
                file: file,
                line: line
            )
            return nil
        }
        return matchingEvidence
    }

    @MainActor
    func testSettingsPresentationUpdateRecorderUsesGenerationAndCancellation() {
        let recorder = SettingsPresentationUpdateRecorder()
        let light = FlowPresentationResolver.resolve(
            themeRaw: ThemeMode.light.rawValue,
            languageRaw: AppLanguage.english.rawValue,
            systemColorScheme: .light
        ).context
        let dark = FlowPresentationResolver.resolve(
            themeRaw: ThemeMode.dark.rawValue,
            languageRaw: AppLanguage.english.rawValue,
            systemColorScheme: .light
        ).context
        recorder.record(light)
        let baselineGeneration = recorder.latestEvidence?.generation ?? 0
        var deliveredGenerations: [UInt64] = []
        let observation = recorder.observe(after: baselineGeneration) { evidence in
            guard evidence.context == dark else { return }
            deliveredGenerations.append(evidence.generation)
        }

        recorder.record(light)
        recorder.record(dark)
        observation.cancel()
        recorder.record(dark)

        XCTAssertEqual(deliveredGenerations, [baselineGeneration + 2])
        XCTAssertEqual(
            recorder.latestEvidence?.generation,
            baselineGeneration + 3
        )
    }
}
