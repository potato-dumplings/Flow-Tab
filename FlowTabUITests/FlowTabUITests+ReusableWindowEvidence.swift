import Foundation

enum FlowTabUITestReusableWindowEvidence:
    String,
    CaseIterable,
    Equatable
{
    case stickyBinding
    case privateExactBridge

    var confidenceRawValue: String {
        switch self {
        case .stickyBinding:
            "sticky"
        case .privateExactBridge:
            "exact"
        }
    }

    var verifiedFocusConfidenceTransition: String {
        "\(confidenceRawValue)->exact"
    }

    var verifiedFocusSourceTransition: String {
        "\(rawValue)->verifiedFocusReadback"
    }

    static func parseCurrent(
        hasStickyBinding: Bool,
        source: String
    ) -> Self? {
        guard hasStickyBinding else { return nil }
        return Self(rawValue: source)
    }

    static func parseVerifiedFocusReadback(
        confidenceTransition: String,
        sourceTransition: String
    ) -> Self? {
        allCases.first {
            $0.verifiedFocusConfidenceTransition
                == confidenceTransition
                && $0.verifiedFocusSourceTransition
                    == sourceTransition
        }
    }

    static var currentSourceRegexPattern: String {
        regexAlternation(allCases.map(\.rawValue))
    }

    static var verifiedFocusReadbackRegexPattern: String {
        regexAlternation(
            allCases.map {
                "confidence=\($0.verifiedFocusConfidenceTransition) "
                    + "source=\($0.verifiedFocusSourceTransition)"
            }
        )
    }

    private static func regexAlternation(
        _ values: [String]
    ) -> String {
        let escapedValues = values.map {
            NSRegularExpression.escapedPattern(for: $0)
        }
        return "(?:\(escapedValues.joined(separator: "|")))"
    }
}
