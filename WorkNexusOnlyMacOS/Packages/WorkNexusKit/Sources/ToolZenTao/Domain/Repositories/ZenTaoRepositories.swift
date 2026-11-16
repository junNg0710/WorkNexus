import CoreDomain
import Foundation

/// Ported from: lib/tools/zentao/domain/repositories/{zentao_profile_repository,zentao_doc_repository}.dart
public protocol ZenTaoProfileRepository: Sendable {
    func watch(accountId: String) -> AsyncStream<ZenTaoProfile?>
    func watchDepartments(accountId: String) -> AsyncStream<[ZenTaoDepartment]>
    func refresh(account: Account) async -> Outcome<ZenTaoProfile>
    func update(account: Account, changes: ZenTaoProfileUpdate) async -> Outcome<ZenTaoProfile>
}

/// ZenTao documents, read-only. The `watch*` streams read the local cache (the source of truth); the
/// `refresh*` calls fetch from the server and write the cache, which the streams then emit.
public protocol ZenTaoDocRepository: Sendable {
    func watchLibs(accountId: String) -> AsyncStream<[ZenTaoDocLib]>
    func watchDocs(accountId: String, libId: String) -> AsyncStream<[ZenTaoDocSummary]>
    func watchDoc(accountId: String, docId: String) -> AsyncStream<ZenTaoDoc?>
    func refreshLibs(account: Account) async -> Outcome<Void>
    func refreshDocs(account: Account, libId: String) async -> Outcome<Void>
    func refreshDoc(account: Account, docId: String) async -> Outcome<Void>
    /// A document's history, oldest first.
    func watchHistory(accountId: String, docId: String) -> AsyncStream<[ZenTaoDocAction]>
    func refreshHistory(account: Account, docId: String) async -> Outcome<Void>
    /// The account's pinned libraries and documents (stored locally only).
    func watchPins(accountId: String) -> AsyncStream<ZenTaoDocPins>
    func savePins(accountId: String, pins: ZenTaoDocPins) async -> Outcome<Void>
    /// An image embedded in a document body, through the authenticated session.
    func fetchImage(account: Account, url: String) async -> Data?
    /// A document's attached `file`, downloaded for showing in place.
    func readFile(account: Account, file: TicketAttachment) async -> Outcome<Data>
    /// Saves a document's attached `file` to the user's Downloads folder and returns the saved path.
    func saveFile(account: Account, file: TicketAttachment) async -> Outcome<String>
    /// The cached document as ZenTao sent it - its whole record - as indented JSON, for a backup.
    func readBackup(accountId: String, docId: String) async -> Outcome<String>
    /// Saves `text` to the user's Downloads folder as `fileName` (numbered when taken); returns the saved path.
    func saveText(fileName: String, text: String) async -> Outcome<String>
}

/// Ported from: lib/shared/sync/data/source_list_cache.dart - the last-fetched product / project lists, so the
/// sidebar tree can paint from disk on launch.
public protocol ZenTaoSourceListCache: Sendable {
    func readProducts(accountId: String) async -> [ProviderProduct]?
    func readProjects(accountId: String) async -> [ProviderProject]?
    func withKnownProgramNames(accountId: String, projects: [ProviderProject]) async -> [ProviderProject]
    func saveProducts(accountId: String, items: [ProviderProduct]) async
    func saveProjects(accountId: String, items: [ProviderProject]) async
}

/// The team groups of a leader, kept on this Mac. Not in the Flutter app.
public protocol ZenTaoTeamGroupRepository: Sendable {
    func watchGroups(accountId: String) -> AsyncStream<[ZenTaoTeamGroup]>
    func save(_ group: ZenTaoTeamGroup) async -> Outcome<Void>
    func delete(id: String) async -> Outcome<Void>
}

/// Nothing saved, nothing stored: where a team group store is not wired (tests, previews).
public struct NoTeamGroups: ZenTaoTeamGroupRepository {
    public init() {}
    public func watchGroups(accountId: String) -> AsyncStream<[ZenTaoTeamGroup]> { AsyncStream { $0.yield([]); $0.finish() } }
    public func save(_ group: ZenTaoTeamGroup) async -> Outcome<Void> { .success(()) }
    public func delete(id: String) async -> Outcome<Void> { .success(()) }
}
