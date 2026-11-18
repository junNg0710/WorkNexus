import Foundation

/// Which page of the catalogue to show: a search, a kind, an order. Not in the Flutter app.
public struct PetQuery: Sendable, Equatable {
    public enum Sort: String, Sendable, CaseIterable { case new, popular, random }

    public var text: String
    public var kind: PetKind?
    public var sort: Sort
    public var page: Int
    public var pageSize: Int

    public init(text: String = "", kind: PetKind? = nil, sort: Sort = .popular, page: Int = 1, pageSize: Int = 30) {
        self.text = text; self.kind = kind; self.sort = sort; self.page = max(page, 1); self.pageSize = min(max(pageSize, 1), 60)
    }

    /// The same search, one page further on.
    public var next: PetQuery { var q = self; q.page += 1; return q }
}

/// One page of the catalogue.
public struct PetCatalogPage: Sendable, Equatable {
    public var pets: [CatalogPet]
    public var page: Int
    public var totalPages: Int
    public var total: Int

    public init(pets: [CatalogPet], page: Int, totalPages: Int, total: Int) {
        self.pets = pets; self.page = page; self.totalPages = totalPages; self.total = total
    }

    public var hasMore: Bool { page < totalPages }
}
