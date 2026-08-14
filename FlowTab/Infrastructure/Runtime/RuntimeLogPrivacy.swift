import CryptoKit
import Foundation

struct RuntimeLogPrivacyFormatter {
    private struct Field {
        let key: String
        let value: String
    }

    private static let fieldExpression = try! NSRegularExpression(
        pattern: #"(?:^|\s)([A-Za-z][A-Za-z0-9_.-]{0,63})="#
    )

    private let key: SymmetricKey

    init(keyData: Data) {
        key = SymmetricKey(data: keyData)
    }

    func redact(_ message: String) -> String {
        let parsedMessage = parseMessage(message)
        let fields = parsedMessage.fields
        var tokens = [
            "message.type=structured",
            "message.length=\(message.count)",
            "message.fieldCount=\(fields.count)",
            "message.fingerprint=\(stableFingerprint(for: message))"
        ]

        if let firstFieldRange = parsedMessage.firstFieldRange {
            let eventText = String(message[..<firstFieldRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !eventText.isEmpty {
                tokens.append(contentsOf: metadataTokens(prefix: "event", value: eventText, type: "event"))
            }
        } else if !message.isEmpty {
            tokens.append(contentsOf: metadataTokens(prefix: "event", value: message, type: "event"))
        }

        for (index, field) in fields.enumerated() {
            let value = normalizedValue(field.value)
            let prefix = "field\(index)"
            tokens.append(contentsOf: metadataTokens(
                prefix: "\(prefix).name",
                value: field.key,
                type: "field-name"
            ))
            tokens.append(contentsOf: metadataTokens(
                prefix: "\(prefix).value",
                value: value,
                type: privacyType(for: field.key)
            ))
        }

        return tokens.joined(separator: " ")
    }

    private func parseMessage(
        _ message: String
    ) -> (fields: [Field], firstFieldRange: Range<String.Index>?) {
        let fullRange = NSRange(message.startIndex..<message.endIndex, in: message)
        let matches = Self.fieldExpression.matches(in: message, range: fullRange)
        guard !matches.isEmpty else { return ([], nil) }

        let fields: [Field] = matches.enumerated().compactMap { index, match in
            guard let keyRange = Range(match.range(at: 1), in: message) else { return nil }
            let valueStartOffset = match.range.location + match.range.length
            let valueEndOffset = index + 1 < matches.count
                ? matches[index + 1].range.location
                : fullRange.length
            let valueStart = String.Index(utf16Offset: valueStartOffset, in: message)
            let valueEnd = String.Index(utf16Offset: valueEndOffset, in: message)
            return Field(
                key: String(message[keyRange]),
                value: String(message[valueStart..<valueEnd])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return (fields, Range(matches[0].range, in: message))
    }

    private func normalizedValue(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }
        if (trimmed.first == "\"" && trimmed.last == "\"")
            || (trimmed.first == "'" && trimmed.last == "'") {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    private func privacyType(for key: String) -> String {
        let normalized = key.lowercased()
        if normalized.contains("query")
            || normalized.contains("search")
            || normalized.contains("term")
            || normalized.contains("compact") {
            return "search-text"
        }
        if normalized.contains("tab") && normalized.contains("title") {
            return "browser-tab-title"
        }
        if normalized.contains("title") {
            return "window-title"
        }
        if normalized.contains("path") || normalized.contains("executable") {
            return "file-path"
        }
        if normalized.contains("url") {
            return "url"
        }
        if normalized.contains("bundle") || normalized.hasSuffix("appid") {
            return "application-identifier"
        }
        if normalized.contains("tab") {
            return "browser-tab-title"
        }
        if normalized.contains("error") || normalized.contains("description") {
            return "error-text"
        }
        if normalized.contains("identifier")
            || normalized.contains("identity")
            || ["ax", "cg", "pid"].contains(normalized)
            || key == "id"
            || key.hasSuffix("ID")
            || key.hasSuffix("IDs") {
            return "identifier"
        }
        return "text"
    }

    private func metadataTokens(prefix: String, value: String, type: String) -> [String] {
        [
            "\(prefix).type=\(type)",
            "\(prefix).length=\(value.count)",
            "\(prefix).count=\(itemCount(in: value))",
            "\(prefix).fingerprint=\(stableFingerprint(for: value))"
        ]
    }

    private func itemCount(in value: String) -> Int {
        guard !value.isEmpty else { return 0 }
        return max(1, value.split(separator: ",", omittingEmptySubsequences: true).count)
    }

    func stableFingerprint(for value: String) -> String {
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: Data(value.utf8),
            using: key
        )
        return authenticationCode.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
