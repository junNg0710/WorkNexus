import XCTest
@testable import CoreDomain

/// What a typed search asks for and where a text answers it.
final class SearchTermsTests: XCTestCase {
    func testWordsAreApartAndQuotedOnesStayTogether() {
        XCTAssertEqual(SearchTerms.parse("  release   v2 "), ["release", "v2"])
        XCTAssertEqual(SearchTerms.parse("release \"phát hành\" v2"), ["release", "phát hành", "v2"])
        XCTAssertEqual(SearchTerms.parse("“build xong” rồi"), ["build xong", "rồi"])
        XCTAssertEqual(SearchTerms.parse("\"left open"), ["left open"])
        XCTAssertEqual(SearchTerms.parse("\"\"  "), [])
    }

    func testFiltersAreTakenOutOfTheWordsSearched() {
        let keys: Set<String> = ["from", "in", "has"]
        let f = SearchTerms.filters(in: "from:an in:\"đội wallet\" build xong has:file", keys: keys)
        XCTAssertEqual(f.text, "build xong")
        XCTAssertEqual(f.filters, ["from": ["an"], "in": ["đội wallet"], "has": ["file"]])
        XCTAssertEqual(f.typing?.key, "has", "nothing follows it yet: still being typed")
        // Not a filter: an address, an unknown key.
        XCTAssertEqual(SearchTerms.filters(in: "https://a.b/c note:x", keys: keys), SearchTerms.Filtered(text: "https://a.b/c note:x", filters: [:]))
        // Keys in any case; twice the same key keeps both.
        XCTAssertEqual(SearchTerms.filters(in: "FROM:an from:binh", keys: keys).filters, ["from": ["an", "binh"]])
    }

    func testTheFilterBeingTypedIsKnownAndCompleted() {
        let keys: Set<String> = ["from", "in"]
        let typing = SearchTerms.filters(in: "build from:mi", keys: keys).typing
        XCTAssertEqual(typing?.key, "from"); XCTAssertEqual(typing?.value, "mi")
        XCTAssertEqual(SearchTerms.filters(in: "build from:", keys: keys).typing?.value, "")
        XCTAssertNil(SearchTerms.filters(in: "build from:mi ", keys: keys).typing)
        XCTAssertNil(SearchTerms.filters(in: "build", keys: keys).typing)
        XCTAssertEqual(SearchTerms.completing("build from:mi", key: "from", with: "Minh Anh"), "build from:\"Minh Anh\" ")
        XCTAssertEqual(SearchTerms.completing("in:wal", key: "in", with: "Wallet"), "in:Wallet ")
    }

    func testItIsFoundWithoutCaseOrDiacritics() {
        let text = "Anh Quốc đi Đường Láng"
        XCTAssertEqual(SearchTerms.ranges(of: ["quoc"], in: text).map { String(text[$0]) }, ["Quốc"])
        XCTAssertEqual(SearchTerms.ranges(of: ["DUONG", "láng"], in: text).map { String(text[$0]) }, ["Đường", "Láng"])
        XCTAssertTrue(SearchTerms.ranges(of: ["xyz"], in: text).isEmpty)
        XCTAssertTrue(SearchTerms.ranges(of: [], in: text).isEmpty)
    }

    func testPlacesThatTouchAreJoinedAndStayInOrder() {
        let text = "abcabc def"
        XCTAssertEqual(SearchTerms.ranges(of: ["def", "bca"], in: text).map { String(text[$0]) }, ["bca", "def"])
        XCTAssertEqual(SearchTerms.ranges(of: ["ab", "bc"], in: "x abc").map { String("x abc"[$0]) }, ["abc"])
    }

    func testAWordIsShownWhereItStartsOneRatherThanInsideOthers() {
        let text = "thanh toán thành công, phát hành nhanh"
        XCTAssertEqual(SearchTerms.ranges(of: ["phat", "hanh"], in: text).map { String(text[$0]) }, ["phát", "hành"])
        // Found only inside words: shown there.
        XCTAssertEqual(SearchTerms.ranges(of: ["anh"], in: "thanh nhanh").map { String("thanh nhanh"[$0]) }, ["anh", "anh"])
        // After punctuation is the start of a word too.
        XCTAssertEqual(SearchTerms.ranges(of: ["flutter"], in: "@Thanh-VN-Flutter (dev)").count, 1)
    }

    func testTheWordsAsTypedRankFirstThenWholeWordsThenTheRest() {
        XCTAssertEqual(SearchTerms.rank(["phat", "hanh"], in: "bản phát hành tối nay"), 0)
        XCTAssertEqual(SearchTerms.rank(["phat", "hanh"], in: "hành động rồi mới phát"), 1)
        XCTAssertEqual(SearchTerms.rank(["phat", "hanh"], in: "thanh toán đã phát sinh"), 2)
        XCTAssertEqual(SearchTerms.rank(["hanh"], in: "phát hành"), 0)
        XCTAssertEqual(SearchTerms.rank(["hanh"], in: "thành công"), 2)
    }

    func testEveryWordHasToBeThereInAnyOrder() {
        XCTAssertTrue(SearchTerms.allFound(["build", "wallet"], in: "Wallet: bản build mới"))
        XCTAssertFalse(SearchTerms.allFound(["build", "release"], in: "Wallet: bản build mới"))
        XCTAssertTrue(SearchTerms.allFound(["ban build"], in: "Wallet: bản build mới"), "a phrase, as a whole")
        XCTAssertFalse(SearchTerms.allFound(["build ban"], in: "Wallet: bản build mới"))
        XCTAssertTrue(SearchTerms.allFound([], in: "anything"))
    }

    func testASnippetShowsThePlaceItWasFound() {
        let long = String(repeating: "mở đầu dài dòng ", count: 12) + "đây là chỗ cần TÌM thấy " + String(repeating: "phần sau ", count: 20)
        let s = SearchTerms.snippet(long, terms: ["tim"], length: 60)
        XCTAssertTrue(s.hasPrefix("…") && s.hasSuffix("…"))
        XCTAssertTrue(s.contains("TÌM"))
        XCTAssertLessThanOrEqual(s.count, 62)
        XCTAssertEqual(SearchTerms.snippet("ngắn thôi", terms: ["thoi"], length: 60), "ngắn thôi")
        // Found near the end: the room goes before it, with nothing cut after.
        let tail = String(repeating: "x ", count: 80) + "cuối"
        let t = SearchTerms.snippet(tail, terms: ["cuoi"], length: 40)
        XCTAssertTrue(t.hasPrefix("…") && t.hasSuffix("cuối"))
        // Nothing found (the match was in the sender's name): the start.
        XCTAssertTrue(SearchTerms.snippet(long, terms: ["zzz"], length: 60).hasPrefix("mở đầu"))
    }
}
