import CoreDomain
import CorePersistence
import Foundation
import GRDB

/// The document endpoints for `account`, or nil when it has no stored credentials. The composition root hands
/// out the sync's pooled client: a login of this repository's own would end the sync's ZenTao session.
public typealias ZenTaoDocsRemoteFactory = @Sendable (Account) async -> ZenTaoClient?

/// Where saved files go; nil when the platform has no Downloads folder.
public typealias ZenTaoDownloadsDirectoryFinder = @Sendable () async -> URL?

/// Ported from: lib/tools/zentao/data/repositories/local_zentao_doc_repository.dart
/// `ZenTaoDocRepository` over the `zenTaoDocSnapshots` table: the cache is the source of truth, `refresh*` fetch
/// from ZenTao into it.
public final class GRDBZenTaoDocRepository: ZenTaoDocRepository, @unchecked Sendable {
    private let db: AppDatabase
    private let remoteFor: ZenTaoDocsRemoteFactory
    private let downloads: ZenTaoDownloadsDirectoryFinder

    private static let libsKey = "libs"
    private static let pinsKey = "pins"
    private static func libKey(_ id: String) -> String { "lib:\(id)" }
    private static func docKey(_ id: String) -> String { "doc:\(id)" }
    private static func historyKey(_ id: String) -> String { "history:\(id)" }

    private struct Unreadable: Error {}

    public init(db: AppDatabase, remote: @escaping ZenTaoDocsRemoteFactory, downloads: ZenTaoDownloadsDirectoryFinder? = nil) {
        self.db = db
        self.remoteFor = remote
        self.downloads = downloads ?? { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first }
    }

    // MARK: Watching

    private func watchJSON<T: Equatable & Sendable>(_ accountId: String, _ key: String, _ map: @escaping @Sendable (JSON?) -> T) -> AsyncStream<T> {
        db.observe { d -> T in
            let row = try ZenTaoDocSnapshotRow.fetchOne(d, key: ["accountId": accountId, "key": key])
            return map(row.flatMap { asMap(try? jsonDecode($0.json)) })
        }.removingDuplicates()
    }

    public func watchLibs(accountId: String) -> AsyncStream<[ZenTaoDocLib]> {
        watchJSON(accountId, Self.libsKey) { $0.map(mapZenTaoDocLibs) ?? [] }
    }

    public func watchDocs(accountId: String, libId: String) -> AsyncStream<[ZenTaoDocSummary]> {
        watchJSON(accountId, Self.libKey(libId)) { $0.map { mapZenTaoDocSummaries($0, libId: libId) } ?? [] }
    }

    public func watchDoc(accountId: String, docId: String) -> AsyncStream<ZenTaoDoc?> {
        watchJSON(accountId, Self.docKey(docId)) { json in
            guard let doc = asMap(json?["doc"]) else { return nil }
            return mapZenTaoDoc(doc, baseUrl: str(json?["base"]) ?? "")
        }
    }

    public func watchHistory(accountId: String, docId: String) -> AsyncStream<[ZenTaoDocAction]> {
        watchJSON(accountId, Self.historyKey(docId)) { $0.map(mapZenTaoDocHistory) ?? [] }
    }

    public func watchPins(accountId: String) -> AsyncStream<ZenTaoDocPins> {
        watchJSON(accountId, Self.pinsKey) { $0.map(mapZenTaoDocPins) ?? ZenTaoDocPins() }
    }

    // MARK: Refreshing

    public func refreshLibs(account: Account) async -> Outcome<Void> { await refresh(account, Self.libsKey) { try await $0.libs() } }

    public func refreshDocs(account: Account, libId: String) async -> Outcome<Void> {
        await refresh(account, Self.libKey(libId)) { try await $0.docs(libId) }
    }

    public func refreshDoc(account: Account, docId: String) async -> Outcome<Void> {
        await refresh(account, Self.docKey(docId)) { remote in
            let json = try await remote.doc(docId)
            // A document the user may not read comes back without its fields; storing it would replace a
            // readable cached copy with nothing.
            if mapZenTaoDoc(json, baseUrl: remote.baseUrl) == nil { throw Unreadable() }
            // The base URL is kept beside the document: its files' links are built from it on read.
            return ["base": remote.baseUrl, "doc": json]
        }
    }

    public func refreshHistory(account: Account, docId: String) async -> Outcome<Void> {
        await refresh(account, Self.historyKey(docId)) { try await $0.history(docId) }
    }

    private func refresh(_ account: Account, _ key: String, _ fetch: (ZenTaoDocsRemote) async throws -> JSON) async -> Outcome<Void> {
        do {
            guard let client = await remoteFor(account) else { return .failure(.auth("No ZenTao connection credentials")) }
            let encoded = jsonEncode(try await fetch(ZenTaoDocsRemote(client: client)))
            let stored = try await db.writer.read { try ZenTaoDocSnapshotRow.fetchOne($0, key: ["accountId": account.id, "key": key]) }
            // An unchanged reply leaves the row (and its watchers) alone.
            if stored?.json == encoded { return .success(()) }
            let row = ZenTaoDocSnapshotRow(accountId: account.id, key: key, json: encoded, fetchedAt: Date())
            try await db.writer.write { try row.save($0) }
            return .success(())
        } catch is Unreadable {
            return .failure(.notFound("ZenTao document is not readable"))
        } catch let e as ZenTaoError {
            switch e {
            case .http(let code, _, _) where code == 401: return .failure(.auth("ZenTao authentication failed"))
            case .http(let code, _, _) where code == 403 || code == 404: return .failure(.notFound("Could not load ZenTao documents"))
            case .format: return .failure(.parse("Invalid ZenTao document reply"))
            default: return .failure(.network("Could not load ZenTao documents"))
            }
        } catch {
            return .failure(.unexpected("Could not load ZenTao documents: \(error)"))
        }
    }

    // MARK: Pins

    public func savePins(accountId: String, pins: ZenTaoDocPins) async -> Outcome<Void> {
        let row = ZenTaoDocSnapshotRow(accountId: accountId, key: Self.pinsKey, json: jsonEncode(zenTaoDocPinsToJson(pins)), fetchedAt: Date())
        return await guarded {
            do { try await self.db.writer.write { try row.save($0) } }
            catch { throw Failure.storage("Could not save the pins") }
        }
    }

    // MARK: Files

    public func fetchImage(account: Account, url: String) async -> Data? {
        guard let client = await remoteFor(account) else { return nil }
        return (try? await ZenTaoDocsRemote(client: client).image(url)) ?? nil
    }

    private func bytes(_ account: Account, _ file: TicketAttachment) async -> Outcome<Data> {
        guard let client = await remoteFor(account) else { return .failure(.auth("No ZenTao connection credentials")) }
        do {
            guard let data = try await ZenTaoDocsRemote(client: client).download(file.url) else {
                return .failure(.network("Could not download the file"))
            }
            return .success(data)
        } catch let e as ZenTaoError {
            if case .http(let code, _, _) = e {
                if code == 401 { return .failure(.auth("ZenTao authentication failed")) }
                if code == 403 || code == 404 { return .failure(.notFound("Could not download the file")) }
            }
            return .failure(.network("Could not download the file"))
        } catch { return .failure(.network("Could not download the file")) }
    }

    public func readFile(account: Account, file: TicketAttachment) async -> Outcome<Data> { await bytes(account, file) }

    public func saveFile(account: Account, file: TicketAttachment) async -> Outcome<String> {
        switch await bytes(account, file) {
        case .failure(let f): return .failure(f)
        case .success(let data):
            guard let dir = await downloads() else { return .failure(.storage("No Downloads folder")) }
            do {
                let dest = Self.freePath(dir, Self.safeName(file.title))
                try data.write(to: dest, options: .atomic)
                return .success(dest.path)
            } catch { return .failure(.storage("Could not save the file")) }
        }
    }

    public func readBackup(accountId: String, docId: String) async -> Outcome<String> {
        do {
            let row = try await db.writer.read { try ZenTaoDocSnapshotRow.fetchOne($0, key: ["accountId": accountId, "key": Self.docKey(docId)]) }
            guard let stored = row.flatMap({ asMap(try? jsonDecode($0.json)) }), let doc = asMap(stored["doc"]) else {
                return .failure(.notFound("ZenTao document is not cached"))
            }
            return .success(jsonEncode(doc, pretty: true))
        } catch { return .failure(.storage("Could not read the document")) }
    }

    public func saveText(fileName: String, text: String) async -> Outcome<String> {
        guard let dir = await downloads() else { return .failure(.storage("No Downloads folder")) }
        do {
            let dest = Self.freePath(dir, Self.safeName(fileName))
            try text.write(to: dest, atomically: true, encoding: .utf8)
            return .success(dest.path)
        } catch { return .failure(.storage("Could not save the file")) }
    }

    static func safeName(_ name: String) -> String {
        let safe = name.replacingRegex(#"[/\\:*?"<>|]"#, with: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return safe.isEmpty ? "file" : safe
    }

    /// `name` in `dir`, numbered (`name (2).ext`) when a file already has it.
    static func freePath(_ dir: URL, _ name: String) -> URL {
        let ns = name as NSString
        let ext = ns.pathExtension.isEmpty ? "" : ".\(ns.pathExtension)"
        let stem = ns.pathExtension.isEmpty ? name : ns.deletingPathExtension
        var candidate = dir.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem) (\(n))\(ext)")
            n += 1
        }
        return candidate
    }
}
