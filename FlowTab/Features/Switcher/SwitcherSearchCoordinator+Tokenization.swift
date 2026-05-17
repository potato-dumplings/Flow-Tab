import Foundation
import FlowTabCore

extension SwitcherSearchCoordinator {
    static func buildSearchKey(from value: String) -> SearchKey {
        SearchTextMatcher.buildKey(from: value)
    }

    static func buildSearchIndex(for value: String, identifier: String? = nil) -> SearchIndex {
        SearchTextMatcher.buildIndex(for: value, identifier: identifier)
    }

    static func compactToken(_ value: String) -> String {
        SearchTextMatcher.compactToken(value)
    }

    static func bigrams(of value: String) -> [String] {
        SearchTextMatcher.bigrams(of: value)
    }

    static func wrappedIndex(current: Int, count: Int, delta: Int) -> Int {
        guard count > 0 else { return 0 }
        let raw = (current + delta) % count
        return raw >= 0 ? raw : raw + count
    }

    static func clampedCursorPosition(_ cursorPosition: Int, in query: String) -> Int {
        min(max(cursorPosition, 0), query.count)
    }

    static func stringIndex(in value: String, characterOffset: Int) -> String.Index {
        let offset = min(max(characterOffset, 0), value.count)
        return value.index(value.startIndex, offsetBy: offset)
    }
}
