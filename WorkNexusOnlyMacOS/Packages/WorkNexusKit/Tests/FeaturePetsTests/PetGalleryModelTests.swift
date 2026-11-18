import CoreDomain
import Foundation
import XCTest
@testable import FeaturePets

/// The gallery reads the catalogue a page at a time, without repeats, and starts over for a new search.
@MainActor
final class PetGalleryModelTests: XCTestCase {
    private struct Pages: PetCatalogRepository {
        var totalPages = 2
        func browse(_ q: PetQuery) async -> Outcome<PetCatalogPage> {
            if q.text == "boom" { return .failure(.network("offline")) }
            let pets = (0..<2).map { i in
                CatalogPet(id: "\(q.text)p\(q.page)-\(i)", displayName: "P", description: "", kind: nil, tags: [], ownerHandle: "o",
                           likeCount: 0, downloadCount: 0, spriteVersion: 2, spritesheetURL: URL(string: "https://codex-pets.net/s.webp")!,
                           posterURL: nil, previewURL: nil)
            }
            return .success(PetCatalogPage(pets: pets, page: q.page, totalPages: totalPages, total: totalPages * 2))
        }
    }

    private struct NoLibrary: PetLibraryRepository {
        func list() async -> Outcome<[InstalledPet]> { .success([]) }
        func install(_ pet: CatalogPet) async -> Outcome<InstalledPet> { .failure(.unexpected("no")) }
        func remove(id: String) async -> Outcome<Void> { .success(()) }
    }

    func testPagesAddUpAndANewSearchStartsOver() async {
        let model = PetGalleryModel(services: PetsFeature.Services(catalog: Pages(), library: NoLibrary()))
        await model.reloadIfChanged()
        XCTAssertEqual(model.pets.map(\.id), ["p1-0", "p1-1"])
        XCTAssertTrue(model.hasMore)
        await model.loadMore()
        XCTAssertEqual(model.pets.count, 4)
        XCTAssertFalse(model.hasMore)
        await model.loadMore()                                 // nothing past the last page
        XCTAssertEqual(model.pets.count, 4)
        await model.reloadIfChanged()                          // same search: kept as it is
        XCTAssertEqual(model.pets.count, 4)
        model.text = "cat"
        await model.reloadIfChanged()
        XCTAssertEqual(model.pets.map(\.id), ["catp1-0", "catp1-1"])
    }

    func testAFailureIsShownAndCleared() async {
        let model = PetGalleryModel(services: PetsFeature.Services(catalog: Pages(), library: NoLibrary()))
        model.text = "boom"
        await model.reload()
        XCTAssertEqual(model.error, "offline")
        XCTAssertFalse(model.isLoading)
        model.text = "ok"
        await model.reload()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.pets.count, 2)
    }
}
