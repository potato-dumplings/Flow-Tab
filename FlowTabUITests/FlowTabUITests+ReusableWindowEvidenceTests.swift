import Foundation
import XCTest

private func reusableWindowEvidenceRegexMatches(
    _ value: String,
    pattern: String
) -> Bool {
    let expression = try? NSRegularExpression(
        pattern: "^(?:\(pattern))$"
    )
    let range = NSRange(
        location: 0,
        length: (value as NSString).length
    )
    return expression?.firstMatch(
        in: value,
        range: range
    )?.range == range
}

extension FlowTabUITests {
    func testReusableWindowEvidenceParsesCurrentSourceMatrix() {
        XCTAssertEqual(
            FlowTabUITestReusableWindowEvidence.parseCurrent(
                hasStickyBinding: true,
                source: "stickyBinding"
            ),
            .stickyBinding
        )
        XCTAssertEqual(
            FlowTabUITestReusableWindowEvidence.parseCurrent(
                hasStickyBinding: true,
                source: "privateExactBridge"
            ),
            .privateExactBridge
        )

        for source in [
            "stickyBinding",
            "privateExactBridge"
        ] {
            XCTAssertNil(
                FlowTabUITestReusableWindowEvidence.parseCurrent(
                    hasStickyBinding: false,
                    source: source
                )
            )
        }
        for source in [
            "publicExactMatch",
            "verifiedFocusReadback",
            "unknown"
        ] {
            XCTAssertNil(
                FlowTabUITestReusableWindowEvidence.parseCurrent(
                    hasStickyBinding: true,
                    source: source
                )
            )
        }
    }

    func testReusableWindowEvidenceRequiresPairedVerifiedFocusTransition() {
        XCTAssertEqual(
            FlowTabUITestReusableWindowEvidence
                .parseVerifiedFocusReadback(
                    confidenceTransition: "sticky->exact",
                    sourceTransition:
                        "stickyBinding->verifiedFocusReadback"
                ),
            .stickyBinding
        )
        XCTAssertEqual(
            FlowTabUITestReusableWindowEvidence
                .parseVerifiedFocusReadback(
                    confidenceTransition: "exact->exact",
                    sourceTransition:
                        "privateExactBridge->verifiedFocusReadback"
                ),
            .privateExactBridge
        )

        let invalidTransitions = [
            (
                "sticky->exact",
                "privateExactBridge->verifiedFocusReadback"
            ),
            (
                "exact->exact",
                "stickyBinding->verifiedFocusReadback"
            ),
            (
                "exact->exact",
                "publicExactMatch->verifiedFocusReadback"
            ),
            (
                "exact->sticky",
                "verifiedFocusReadback->stickyBinding"
            )
        ]
        for (confidence, source) in invalidTransitions {
            XCTAssertNil(
                FlowTabUITestReusableWindowEvidence
                    .parseVerifiedFocusReadback(
                        confidenceTransition: confidence,
                        sourceTransition: source
                    )
            )
        }
    }

    func testReusableWindowEvidenceRegexPatternsMatchStructuredRule() {
        let currentPattern =
            FlowTabUITestReusableWindowEvidence
                .currentSourceRegexPattern
        let transitionPattern =
            FlowTabUITestReusableWindowEvidence
                .verifiedFocusReadbackRegexPattern

        for evidence in
            FlowTabUITestReusableWindowEvidence.allCases
        {
            XCTAssertTrue(
                reusableWindowEvidenceRegexMatches(
                    evidence.rawValue,
                    pattern: currentPattern
                )
            )
            XCTAssertTrue(
                reusableWindowEvidenceRegexMatches(
                    "confidence="
                        + evidence
                            .verifiedFocusConfidenceTransition
                        + " source="
                        + evidence.verifiedFocusSourceTransition,
                    pattern: transitionPattern
                )
            )
        }

        for source in [
            "publicExactMatch",
            "verifiedFocusReadback",
            "unknown"
        ] {
            XCTAssertFalse(
                reusableWindowEvidenceRegexMatches(
                    source,
                    pattern: currentPattern
                )
            )
        }
        for transition in [
            "confidence=sticky->exact "
                + "source=privateExactBridge->verifiedFocusReadback",
            "confidence=exact->exact "
                + "source=stickyBinding->verifiedFocusReadback",
            "confidence=exact->exact "
                + "source=publicExactMatch->verifiedFocusReadback"
        ] {
            XCTAssertFalse(
                reusableWindowEvidenceRegexMatches(
                    transition,
                    pattern: transitionPattern
                )
            )
        }
    }
}
