import Foundation

extension String {
    var flowTabAccessibilitySlug: String {
        let replaced = trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return replaced.isEmpty ? "item" : replaced
    }
}
