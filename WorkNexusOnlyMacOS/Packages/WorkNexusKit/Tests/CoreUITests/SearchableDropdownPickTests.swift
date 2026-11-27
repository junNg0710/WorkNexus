/// Return in a searchable dropdown picks a match of what is typed, never a row of an earlier search.
import XCTest
@testable import CoreUI

final class SearchableDropdownPickTests: XCTestCase {
    private let people = ["Adrian", "ViPham-VN-go", "Victor_Tran", "Vincent"]
    private func choice(_ query: String, highlighted: Int = 0, for made: String? = nil) -> String? {
        SearchableDropdownPick.choice(people, query: query, highlighted: highlighted, highlightedFor: made ?? query) { $0 }
    }

    /// "vic" and Return, the list still drawn for "vi": Victor, not the first of the "vi" matches.
    func testReturnPicksAMatchOfWhatIsTypedNow() {
        XCTAssertEqual(SearchableDropdownPick.matching(people, query: "vi", text: { $0 }), ["ViPham-VN-go", "Victor_Tran", "Vincent"])
        XCTAssertEqual(choice("vic", highlighted: 0, for: "vi"), "Victor_Tran")
        // A row arrowed to in the earlier search does not carry over: the new search starts at its first match.
        XCTAssertEqual(choice("vin", highlighted: 1, for: "vi"), "Vincent")
        XCTAssertNil(choice("zz", highlighted: 0, for: "vi"))
    }

    func testTheHighlightedRowOfThisSearchIsPicked() {
        XCTAssertEqual(choice("vi", highlighted: 2), "Vincent")
        XCTAssertEqual(choice("", highlighted: 1), "ViPham-VN-go", "nothing typed: the row the list opened on")
        XCTAssertNil(choice("vi", highlighted: 9))
    }
}
