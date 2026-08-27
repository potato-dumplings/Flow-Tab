import Foundation

struct RuntimeLogPrivacyLineHeaderCodec {
    private static let base36Digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)
    private static let millisecondsPerDay = 86_400_000

    func compactHeader(
        timestamp: String,
        level: RuntimeLogLevel,
        category: String
    ) -> String {
        "[\(compactTimestamp(timestamp))]"
            + "[\(compactLevel(level))]"
            + "[\(compactCategory(category))]"
    }

    func expand(_ header: Substring) -> String? {
        guard header.first == "[", header.last == "]" else { return nil }
        let groups = header.dropFirst().dropLast().components(separatedBy: "][")
        guard groups.count == 3,
              let timestamp = expandedTimestamp(Substring(groups[0])),
              let level = expandedLevel(Substring(groups[1]))
        else {
            return nil
        }
        let category = expandedCategory(
            Substring(groups[2]),
            usesBase36Timestamp: timestamp.usesBase36
        )
        return "[\(timestamp.value)] [\(level.rawValue)] [\(category)] "
    }

    private func compactTimestamp(_ timestamp: String) -> String {
        let bytes = Array(timestamp.utf8)
        guard bytes.count == 12,
              bytes[2] == 0x3A,
              bytes[5] == 0x3A,
              bytes[8] == 0x2E,
              bytes.enumerated().allSatisfy({ offset, byte in
                  offset == 2 || offset == 5 || offset == 8
                      || (byte >= 0x30 && byte <= 0x39)
              })
        else {
            return timestamp
        }

        let hour = decimalPair(bytes[0], bytes[1])
        let minute = decimalPair(bytes[3], bytes[4])
        let second = decimalPair(bytes[6], bytes[7])
        let millisecond = decimalPair(bytes[9], bytes[10]) * 10
            + Int(bytes[11] - 0x30)
        guard hour < 24, minute < 60, second < 60 else { return timestamp }
        let milliseconds = ((hour * 60 + minute) * 60 + second) * 1_000
            + millisecond
        return base36(milliseconds, width: 6)
    }

    private func expandedTimestamp(
        _ timestamp: Substring
    ) -> (value: String, usesBase36: Bool)? {
        if timestamp.utf8.count == 9,
           timestamp.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) {
            let digits = Array(timestamp)
            return (
                String(digits[0...1])
                    + ":" + String(digits[2...3])
                    + ":" + String(digits[4...5])
                    + "." + String(digits[6...8]),
                false
            )
        }

        guard timestamp.utf8.count == 6,
              let milliseconds = decodeBase36(timestamp),
              milliseconds < Self.millisecondsPerDay
        else {
            return nil
        }
        return (renderTimestamp(milliseconds), true)
    }

    private func compactLevel(_ level: RuntimeLogLevel) -> Character {
        switch level {
        case .debug: return "D"
        case .info: return "I"
        case .warning: return "W"
        case .error: return "E"
        }
    }

    private func expandedLevel(_ level: Substring) -> RuntimeLogLevel? {
        if let fullLevel = RuntimeLogLevel(rawValue: String(level)) {
            return fullLevel
        }
        guard level.count == 1, let code = level.first else { return nil }
        switch code {
        case "D": return .debug
        case "I": return .info
        case "W": return .warning
        case "E": return .error
        default: return nil
        }
    }

    private func compactCategory(_ category: String) -> String {
        if let knownCategory = RuntimeLogCategory.resolve(category) {
            return String(categoryCode(knownCategory))
        }
        return "~" + category
    }

    private func expandedCategory(
        _ category: Substring,
        usesBase36Timestamp: Bool
    ) -> String {
        if usesBase36Timestamp {
            if category.count == 1,
               let code = category.first,
               let knownCategory = self.category(for: code) {
                return knownCategory.rawValue
            }
            return category.first == "~"
                ? String(category.dropFirst())
                : String(category)
        }

        if category.hasPrefix("~~") {
            return String(category.dropFirst())
        }
        if category.count == 2,
           category.first == "~",
           let code = category.last,
           let knownCategory = self.category(for: code) {
            return knownCategory.rawValue
        }
        return String(category)
    }

    private func decimalPair(_ first: UInt8, _ second: UInt8) -> Int {
        Int(first - 0x30) * 10 + Int(second - 0x30)
    }

    private func base36(_ value: Int, width: Int) -> String {
        var remainder = value
        var bytes = [UInt8](repeating: 0x30, count: width)
        for index in stride(from: width - 1, through: 0, by: -1) {
            bytes[index] = Self.base36Digits[remainder % 36]
            remainder /= 36
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func decodeBase36(_ value: Substring) -> Int? {
        var result = 0
        for byte in value.utf8 {
            let digit: Int
            switch byte {
            case 0x30...0x39: digit = Int(byte - 0x30)
            case 0x41...0x5A: digit = Int(byte - 0x41) + 10
            default: return nil
            }
            result = result * 36 + digit
        }
        return result
    }

    private func renderTimestamp(_ milliseconds: Int) -> String {
        let totalSeconds = milliseconds / 1_000
        let millisecond = milliseconds % 1_000
        let hour = totalSeconds / 3_600
        let minute = totalSeconds / 60 % 60
        let second = totalSeconds % 60
        let bytes: [UInt8] = [
            decimalDigit(hour / 10), decimalDigit(hour % 10), 0x3A,
            decimalDigit(minute / 10), decimalDigit(minute % 10), 0x3A,
            decimalDigit(second / 10), decimalDigit(second % 10), 0x2E,
            decimalDigit(millisecond / 100),
            decimalDigit(millisecond / 10 % 10),
            decimalDigit(millisecond % 10)
        ]
        return String(decoding: bytes, as: UTF8.self)
    }

    private func decimalDigit(_ value: Int) -> UInt8 {
        UInt8(value) + 0x30
    }

    private func categoryCode(_ category: RuntimeLogCategory) -> Character {
        switch category {
        case .activation: return "0"
        case .app: return "1"
        case .autoEnter: return "2"
        case .ax: return "3"
        case .axMatch: return "4"
        case .axObserver: return "5"
        case .hotKey: return "6"
        case .inputTrace: return "7"
        case .manual: return "8"
        case .permission: return "9"
        case .preview: return "A"
        case .projection: return "B"
        case .recency: return "C"
        case .runtimeFacts: return "D"
        case .search: return "E"
        case .searchInput: return "F"
        case .searchModel: return "G"
        case .searchTrace: return "H"
        case .session: return "I"
        case .switcherLayout: return "J"
        case .uiTest: return "K"
        }
    }

    private func category(for code: Character) -> RuntimeLogCategory? {
        switch code {
        case "0": return .activation
        case "1": return .app
        case "2": return .autoEnter
        case "3": return .ax
        case "4": return .axMatch
        case "5": return .axObserver
        case "6": return .hotKey
        case "7": return .inputTrace
        case "8": return .manual
        case "9": return .permission
        case "A": return .preview
        case "B": return .projection
        case "C": return .recency
        case "D": return .runtimeFacts
        case "E": return .search
        case "F": return .searchInput
        case "G": return .searchModel
        case "H": return .searchTrace
        case "I": return .session
        case "J": return .switcherLayout
        case "K": return .uiTest
        default: return nil
        }
    }
}
