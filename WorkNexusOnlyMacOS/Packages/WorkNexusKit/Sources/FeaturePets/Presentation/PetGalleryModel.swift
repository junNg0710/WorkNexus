import CoreDomain
import Foundation
import Observation

/// The online catalogue as the gallery shows it: a search, a kind and an order, read a page at a time. A newer search
/// wins over one still on its way (its page is dropped). Not in the Flutter app.
@MainActor @Observable
public final class PetGalleryModel {
    public var text = ""
    public var kind: PetKind?
    public var sort: PetQuery.Sort = .popular
    public private(set) var pets: [CatalogPet] = []
    public private(set) var total = 0
    public private(set) var isLoading = false
    public private(set) var error: String?
    public private(set) var hasMore = false

    @ObservationIgnored private let browse: BrowsePets
    @ObservationIgnored private var lastQuery: PetQuery?
    @ObservationIgnored private var shownQuery: PetQuery?
    @ObservationIgnored private var generation = 0
    static let pageSize = 30

    public init(services: PetsFeature.Services) { browse = services.browse }

    /// What the gallery asks for now, from the first page.
    public var query: PetQuery { PetQuery(text: text, kind: kind, sort: sort, page: 1, pageSize: Self.pageSize) }

    /// Starts over with the current search.
    public func reload() async {
        generation += 1
        let mine = generation
        pets = []; hasMore = false; shownQuery = query
        await load(query, generation: mine)
    }

    /// Starts over unless the pets shown are already those of the current search (coming back to the page).
    public func reloadIfChanged() async {
        guard shownQuery != query || (pets.isEmpty && !isLoading) else { return }
        await reload()
    }

    /// The next page, when there is one and nothing is loading.
    public func loadMore() async {
        guard hasMore, !isLoading, let last = lastQuery else { return }
        await load(last.next, generation: generation)
    }

    private func load(_ q: PetQuery, generation mine: Int) async {
        isLoading = true; error = nil
        let outcome = await browse(q)
        guard mine == generation else { return }   // a newer search is under way
        isLoading = false
        switch outcome {
        case .success(let page):
            let seen = Set(pets.map(\.id))
            pets += page.pets.filter { !seen.contains($0.id) }
            total = page.total; hasMore = page.hasMore; lastQuery = q
        case .failure(let f):
            error = f.message
        }
    }
}
