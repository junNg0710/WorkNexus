import CoreDomain
import Foundation
import XCTest
@testable import FeaturePets

/// A catalogue that answers from memory: pages by query, files by URL.
final class FakePetSource: PetCatalogSource, @unchecked Sendable {
    var page = Data()
    var files: [URL: Data] = [:]
    private(set) var queries: [PetQuery] = []
    private(set) var downloads: [URL] = []

    func fetchPage(_ query: PetQuery) async throws -> Data { queries.append(query); return page }
    func download(_ url: URL) async throws -> Data {
        downloads.append(url)
        guard let data = files[url] else { throw Failure.network("404 \(url)") }
        return data
    }
}

/// The codex-pets.net catalogue, read from a real (trimmed) `/api/pets` page.
final class PetCatalogTests: XCTestCase {
    static func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    func testAPageIsReadAndHiddenCreatorsAreLeftOut() async throws {
        let source = FakePetSource()
        source.page = try Self.fixture("pets-page.json")
        let page = try unwrap(await BrowsePets(CodexPetsCatalogRepository(source: source))(PetQuery(text: "  cat ")))
        // The fixture's second pet is marked `ownerShadowbanned`.
        XCTAssertEqual(page.pets.map(\.id), ["yuki-caramel-monkey", "hitch-snk-e0e8e1340f02"])
        XCTAssertEqual(page.total, 3704)
        XCTAssertTrue(page.hasMore)
        let monkey = try XCTUnwrap(page.pets.first)
        XCTAssertEqual(monkey.kind, .animal)
        XCTAssertEqual(monkey.spriteVersion, 2)
        XCTAssertEqual(monkey.ownerHandle, "vickiyuki")
        XCTAssertEqual(monkey.spritesheetURL.scheme, "https")
        XCTAssertEqual(monkey.spritesheetURL.lastPathComponent, "spritesheet.webp")
        XCTAssertNotNil(monkey.posterURL)
        XCTAssertEqual(source.queries.first?.text, "cat")            // the search is trimmed
    }

    func testAPageTheAppCannotReadIsAParseFailure() async {
        let source = FakePetSource()
        source.page = Data("<html>".utf8)
        let outcome = await CodexPetsCatalogRepository(source: source).browse(PetQuery())
        guard case .failure(.parse) = outcome else { return XCTFail("expected a parse failure, got \(outcome)") }
    }

    func testRelativeAndUnsafeURLs() {
        let base = CodexPetsHTTP.baseURL
        XCTAssertEqual(PetMappers.url("/assets/a.webp", base: base)?.absoluteString, "https://codex-pets.net/assets/a.webp")
        XCTAssertNil(PetMappers.url("http://example.com/a.webp", base: base))
        XCTAssertNil(PetMappers.url("", base: base))
        let unsafe = PetDTO(id: "../etc", spritesheetUrl: "https://codex-pets.net/a.webp")
        XCTAssertNil(PetMappers.pet(unsafe, base: base))
        let noSheet = PetDTO(id: "ok")
        XCTAssertNil(PetMappers.pet(noSheet, base: base))
    }

    func testTheQueryString() throws {
        let url = CodexPetsHTTP.pageURL(PetQuery(text: "red fox", kind: .animal, sort: .new, page: 3, pageSize: 500), base: CodexPetsHTTP.baseURL)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.path, "/api/pets")
        XCTAssertEqual(dict, ["page": "3", "pageSize": "60", "sort": "new", "q": "red fox", "kind": "animal"])
        // No search, no kind: neither is sent (and `content` never is, so only safe pets come back).
        let plain = CodexPetsHTTP.pageURL(PetQuery(), base: CodexPetsHTTP.baseURL).query ?? ""
        XCTAssertFalse(plain.contains("q=")); XCTAssertFalse(plain.contains("kind=")); XCTAssertFalse(plain.contains("content"))
        XCTAssertEqual(PetQuery(page: 2).next.page, 3)
    }

    func testPetIDsMustBeSafeFolderNames() {
        for ok in ["yuki-caramel-monkey", "a_b.c", "x1"] { XCTAssertTrue(PetID.isSafe(ok), ok) }
        for bad in ["", ".", "..", ".hidden", "a/b", "a b", "猴子", String(repeating: "a", count: 129)] { XCTAssertFalse(PetID.isSafe(bad), bad) }
    }
}

/// The value of an outcome, failing the test with its failure.
func unwrap<T>(_ outcome: Outcome<T>, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    switch outcome {
    case .success(let v): return v
    case .failure(let f): XCTFail("\(f)", file: file, line: line); throw f
    }
}

extension PetDTO {
    init(id: String, spritesheetUrl: String? = nil) {
        self.init(id: id, displayName: nil, description: nil, kind: nil, tags: nil, ownerHandle: nil, likeCount: nil, downloadCount: nil,
                  spriteVersionNumber: nil, ownerShadowbanned: nil, spritesheetUrl: spritesheetUrl, posterUrl: nil, previewUrl: nil)
    }
}
