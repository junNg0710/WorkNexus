/// Ported from: lib/tools/zentao/presentation/providers/zentao_doc_providers.dart (the stream providers and `ZenTaoDocSync`)
import CoreDomain
import Foundation

/// What a fetch into the docs cache is for: an account's libraries, one library's documents, one document, or a
/// document's history.
public enum ZentaoDocFetch: Hashable, Sendable {
    case libs(accountId: String)
    case docs(accountId: String, libId: String)
    case doc(accountId: String, docId: String)
    case history(accountId: String, docId: String)
}

/// Where a fetch stands. The cached rows render meanwhile, so a failure is shown beside them rather than in their place.
public enum ZentaoDocSyncStatus: Equatable, Sendable {
    case idle, loading, done
    case failed(Failure)

    public var isLoading: Bool { self == .loading }
    public var failure: Failure? { if case .failed(let f) = self { f } else { nil } }
    public var hasFailed: Bool { failure != nil }
}

extension ZentaoDocsState {
    public func sync(_ fetch: ZentaoDocFetch) -> ZentaoDocSyncStatus { syncs[fetch] ?? .idle }

    // MARK: Cache reads that stay alive

    // The tree's reads stay alive: the nav pane is rebuilt on every trip to Tasks or Bugs, and a fresh subscription
    // has no rows for a frame - the tree would flash "Loading" and lose its place. They are cheap local watches, one
    // per account or opened library.

    /// Starts following the cached libraries and pins of `accountId` (once).
    public func watchAccount(_ accountId: String) {
        watch("libs|\(accountId)") { [repo] in
            for await v in repo.watchLibs(accountId: accountId) { self.libs[accountId] = v }
        }
        watch("pins|\(accountId)") { [repo] in
            for await v in repo.watchPins(accountId: accountId) { self.pins[accountId] = v }
        }
    }

    /// Starts following the cached documents of library `libId` (once).
    public func watchLib(accountId: String, libId: String) {
        let key = Self.libKey(accountId, libId)
        watch("docs|\(key)") { [repo] in
            for await v in repo.watchDocs(accountId: accountId, libId: libId) { self.docLists[key] = v }
        }
    }

    /// Follows the app settings (once).
    public func start() {
        guard let settingsRepo else { return }
        watch("settings") { for await s in settingsRepo.watch() { self.settings = s } }
    }

    private func watch(_ key: String, _ body: @escaping @MainActor () async -> Void) {
        guard watchers[key] == nil else { return }
        watchers[key] = Task { await body() }
    }

    // MARK: Cache reads bound to a view

    /// Follows one cached document until cancelled (the viewer's task): nil until it was fetched.
    public func observeDoc(accountId: String, docId: String) async {
        let key = Self.libKey(accountId, docId)
        for await doc in repo.watchDoc(accountId: accountId, docId: docId) {
            if Task.isCancelled { return }
            docCache[key] = doc
            if doc == nil { docCache.removeValue(forKey: key) }
            docAnswered.insert(key)
        }
    }

    /// Follows one document's cached history until cancelled (the history panel's task).
    public func observeHistory(accountId: String, docId: String) async {
        let key = Self.libKey(accountId, docId)
        for await list in repo.watchHistory(accountId: accountId, docId: docId) {
            if Task.isCancelled { return }
            histories[key] = list
        }
    }

    public func doc(accountId: String, docId: String) -> ZenTaoDoc? { docCache[Self.libKey(accountId, docId)] }
    public func isDocAnswered(accountId: String, docId: String) -> Bool { docAnswered.contains(Self.libKey(accountId, docId)) }
    public func history(accountId: String, docId: String) -> [ZenTaoDocAction] { histories[Self.libKey(accountId, docId)] ?? [] }

    // MARK: Fetching

    /// Fetches into the cache unless a fetch of the same thing is under way or is still fresh (`idleLife`);
    /// `force` fetches again (a Retry, a Refresh).
    public func ensure(_ fetch: ZentaoDocFetch, account: Account, force: Bool = false) async {
        if sync(fetch).isLoading { return }
        if !force, sync(fetch) == .done, let at = fetchedAt[fetch], now().timeIntervalSince(at) < Self.idleLife { return }
        syncs[fetch] = .loading
        let res: Outcome<Void>
        switch fetch {
        case .libs: res = await repo.refreshLibs(account: account)
        case .docs(_, let libId): res = await repo.refreshDocs(account: account, libId: libId)
        case .doc(_, let docId): res = await repo.refreshDoc(account: account, docId: docId)
        case .history(_, let docId): res = await repo.refreshHistory(account: account, docId: docId)
        }
        switch res {
        case .success: syncs[fetch] = .done; fetchedAt[fetch] = now()
        case .failure(let f): syncs[fetch] = .failed(f)
        }
    }
}
