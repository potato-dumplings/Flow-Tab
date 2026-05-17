import XCTest
@testable import FlowTabCore

final class SearchTextMatcherTests: XCTestCase {
    func testSearchTextMatcherMatchesEnglishPartialName() {
        let query = SearchTextMatcher.buildKey(from: "fari")
        let index = SearchTextMatcher.buildIndex(for: "Safari", identifier: "com.apple.Safari")

        XCTAssertNotNil(SearchTextMatcher.matchScore(query: query, in: index))
    }

    func testSearchTextMatcherMatchesEnglishAbbreviation() {
        let query = SearchTextMatcher.buildKey(from: "vsc")
        let index = SearchTextMatcher.buildIndex(
            for: "Visual Studio Code",
            identifier: "com.microsoft.VSCode"
        )

        XCTAssertNotNil(SearchTextMatcher.matchScore(query: query, in: index))
    }

    func testSearchTextMatcherMatchesCodeLikeSubsequenceBehindExactAbbreviation() {
        let index = SearchTextMatcher.buildIndex(
            for: "Visual Studio Code",
            identifier: "com.microsoft.VSCode"
        )

        let abbreviationScore = SearchTextMatcher.matchScore(
            query: SearchTextMatcher.buildKey(from: "vsc"),
            in: index
        )
        let shortSubsequenceScore = SearchTextMatcher.matchScore(
            query: SearchTextMatcher.buildKey(from: "vce"),
            in: index
        )
        let longSubsequenceScore = SearchTextMatcher.matchScore(
            query: SearchTextMatcher.buildKey(from: "vcode"),
            in: index
        )

        XCTAssertNotNil(shortSubsequenceScore)
        XCTAssertNotNil(longSubsequenceScore)
        XCTAssertLessThan(abbreviationScore ?? Int.max, shortSubsequenceScore ?? Int.min)
        XCTAssertNil(SearchTextMatcher.matchScore(query: SearchTextMatcher.buildKey(from: "vcx"), in: index))
    }

    func testSearchTextMatcherMatchesChinesePinyinSpellingAndInitials() {
        let index = SearchTextMatcher.buildIndex(
            for: "微信",
            identifier: "com.tencent.xinWeChat"
        )

        XCTAssertNotNil(SearchTextMatcher.matchScore(query: SearchTextMatcher.buildKey(from: "wx"), in: index))
        XCTAssertNotNil(SearchTextMatcher.matchScore(query: SearchTextMatcher.buildKey(from: "weixin"), in: index))
    }

    func testSearchTextMatcherMatchesBundleIDTermsButIgnoresGenericPrefix() {
        let index = SearchTextMatcher.buildIndex(
            for: "微信",
            identifier: "com.tencent.xinWeChat"
        )

        XCTAssertNotNil(SearchTextMatcher.matchScore(query: SearchTextMatcher.buildKey(from: "wechat"), in: index))
        XCTAssertNil(SearchTextMatcher.matchScore(query: SearchTextMatcher.buildKey(from: "com"), in: index))
    }
}
