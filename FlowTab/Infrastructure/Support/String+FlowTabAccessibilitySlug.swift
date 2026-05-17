import Foundation

extension String {
    var flowTabAccessibilitySlug: String {
        let replaced = flowTabAccessibilityStableSource
            .lowercased()
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return replaced.isEmpty ? "item" : replaced
    }

    var flowTabAccessibilityIdentifierComponent: String {
        "\(flowTabAccessibilitySlug).id-\(Self.flowTabAccessibilityDigest(flowTabAccessibilityStableSource))"
    }

    private var flowTabAccessibilityStableSource: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "item" : trimmed
    }

    private static func flowTabAccessibilityDigest(_ value: String) -> String {
        let digest = flowTabAccessibilityHash64(value) & 0xffff_ffff
        return String(format: "%08llx", digest)
    }

    private static func flowTabAccessibilityHash64(_ value: String) -> UInt64 {
        let prime: UInt64 = 1_099_511_628_211
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
