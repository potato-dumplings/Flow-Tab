import CryptoKit
import Foundation

struct RuntimeLogPrivacyEnvelope: Equatable {
    struct ValueMetadata: Equatable {
        let length: Int
        let count: Int
        let fingerprint: Data
    }

    struct Field: Equatable {
        let name: ValueMetadata
        let valueType: ValueType
        let value: ValueMetadata
    }

    enum ValueType: String, CaseIterable {
        case text
        case searchText = "search-text"
        case browserTabTitle = "browser-tab-title"
        case windowTitle = "window-title"
        case filePath = "file-path"
        case url
        case applicationIdentifier = "application-identifier"
        case errorText = "error-text"
        case identifier

        var code: Character {
            switch self {
            case .text: return "t"
            case .searchText: return "s"
            case .browserTabTitle: return "b"
            case .windowTitle: return "w"
            case .filePath: return "p"
            case .url: return "u"
            case .applicationIdentifier: return "a"
            case .errorText: return "e"
            case .identifier: return "i"
            }
        }

        init?(code: Substring) {
            guard code.count == 1, let character = code.first else { return nil }
            switch character {
            case "t": self = .text
            case "s": self = .searchText
            case "b": self = .browserTabTitle
            case "w": self = .windowTitle
            case "p": self = .filePath
            case "u": self = .url
            case "a": self = .applicationIdentifier
            case "e": self = .errorText
            case "i": self = .identifier
            default: return nil
            }
        }
    }

    let message: ValueMetadata
    let event: ValueMetadata?
    let fields: [Field]
}

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

    func makeEnvelope(for message: String) -> RuntimeLogPrivacyEnvelope {
        let parsedMessage = parseMessage(message)
        let fields = parsedMessage.fields
        let event: RuntimeLogPrivacyEnvelope.ValueMetadata?
        if let firstFieldRange = parsedMessage.firstFieldRange {
            let eventText = String(message[..<firstFieldRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !eventText.isEmpty {
                event = metadata(for: eventText)
            } else {
                event = nil
            }
        } else if !message.isEmpty {
            event = metadata(for: message)
        } else {
            event = nil
        }

        let protectedFields = fields.map { field in
            let value = normalizedValue(field.value)
            return RuntimeLogPrivacyEnvelope.Field(
                name: metadata(for: field.key),
                valueType: privacyType(for: field.key),
                value: metadata(for: value)
            )
        }

        return RuntimeLogPrivacyEnvelope(
            message: RuntimeLogPrivacyEnvelope.ValueMetadata(
                length: message.count,
                count: protectedFields.count,
                fingerprint: stableFingerprintData(for: message)
            ),
            event: event,
            fields: protectedFields
        )
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

    private func privacyType(
        for key: String
    ) -> RuntimeLogPrivacyEnvelope.ValueType {
        let normalized = key.lowercased()
        if normalized.contains("query")
            || normalized.contains("search")
            || normalized.contains("term")
            || normalized.contains("compact") {
            return .searchText
        }
        if normalized.contains("tab") && normalized.contains("title") {
            return .browserTabTitle
        }
        if normalized.contains("title") {
            return .windowTitle
        }
        if normalized.contains("path") || normalized.contains("executable") {
            return .filePath
        }
        if normalized.contains("url") {
            return .url
        }
        if normalized.contains("bundle") || normalized.hasSuffix("appid") {
            return .applicationIdentifier
        }
        if normalized.contains("tab") {
            return .browserTabTitle
        }
        if normalized.contains("error") || normalized.contains("description") {
            return .errorText
        }
        if normalized.contains("identifier")
            || normalized.contains("identity")
            || ["ax", "cg", "pid"].contains(normalized)
            || key == "id"
            || key.hasSuffix("ID")
            || key.hasSuffix("IDs") {
            return .identifier
        }
        return .text
    }

    private func metadata(
        for value: String
    ) -> RuntimeLogPrivacyEnvelope.ValueMetadata {
        RuntimeLogPrivacyEnvelope.ValueMetadata(
            length: value.count,
            count: itemCount(in: value),
            fingerprint: stableFingerprintData(for: value)
        )
    }

    private func itemCount(in value: String) -> Int {
        guard !value.isEmpty else { return 0 }
        return max(1, value.split(separator: ",", omittingEmptySubsequences: true).count)
    }

    func stableFingerprint(for value: String) -> String {
        stableFingerprintData(for: value).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private func stableFingerprintData(for value: String) -> Data {
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: Data(value.utf8),
            using: key
        )
        return Data(authenticationCode.prefix(12))
    }
}
