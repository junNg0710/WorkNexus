import CoreDomain
import CorePersistence
import Foundation
import GRDB

/// Ported from: lib/features/mini_apps/data/repositories/local_mini_app_repository.dart (+ mini_app_local_datasource.dart)
/// `MiniAppRepository` over the local database, an icon store and the site the icon comes from.
public final class GRDBMiniAppRepository: MiniAppRepository, @unchecked Sendable {
    private let db: AppDatabase
    private let icons: MiniAppIconStore
    private let siteIcons: SiteIconSource
    private static let failure = "Could not keep the mini app"

    public init(database: AppDatabase, icons: MiniAppIconStore, siteIcons: SiteIconSource = FaviconFetcher()) {
        db = database; self.icons = icons; self.siteIcons = siteIcons
    }

    public func watchAll() -> AsyncStream<[MiniApp]> {
        db.observe { db in
            let tabs = Dictionary(try MiniAppTabsRow.fetchAll(db).map { ($0.miniAppId, $0) }, uniquingKeysWith: { a, _ in a })
            return try MiniAppRow.order(Column("position")).fetchAll(db).map { MiniApp(row: $0, tabs: tabs[$0.id]) }
        }
    }

    public func save(_ app: MiniApp) async -> Outcome<Void> {
        await write { try MiniAppRow(app: app).save($0) }
    }

    public func saveLastUrl(id: String, url: String) async -> Outcome<Void> {
        await write { try $0.execute(sql: "UPDATE miniApps SET lastUrl = ? WHERE id = ?", arguments: [url, id]) }
    }

    public func saveTabs(id: String, urls: [String], selected: Int) async -> Outcome<Void> {
        await write { try MiniAppTabsRow(miniAppId: id, urls: urls, selected: selected).save($0) }
    }

    /// Gives each app in `ids` its index as position, in one write.
    public func saveOrder(_ ids: [String]) async -> Outcome<Void> {
        await write { db in
            for (i, id) in ids.enumerated() { try db.execute(sql: "UPDATE miniApps SET position = ? WHERE id = ?", arguments: [i, id]) }
        }
    }

    public func delete(id: String) async -> Outcome<Void> {
        icons.delete(id: id)
        return await write { db in
            try db.execute(sql: "DELETE FROM miniAppPermissions WHERE miniAppId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM miniAppTabs WHERE miniAppId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM miniApps WHERE id = ?", arguments: [id])
        }
    }

    public func fetchSiteIcon(id: String, pageUrl: String) async -> Outcome<String?> {
        guard let page = URL(string: pageUrl) else { return .failure(.parse("Not a web address")) }
        guard let icon = await siteIcons.fetch(page) else { return .success(nil) }
        do { return .success(try icons.save(id: id, data: icon.data, fileExtension: icon.fileExtension)) }
        catch { return .failure(.storage(Self.failure)) }
    }

    public func importIcon(id: String, sourcePath: String) async -> Outcome<String> {
        do { return .success(try icons.importFile(id: id, sourcePath: sourcePath)) }
        catch { return .failure(.storage(Self.failure)) }
    }

    private func write(_ body: @escaping @Sendable (Database) throws -> Void) async -> Outcome<Void> {
        do { try await db.writer.write(body); return .success(()) }
        catch { return .failure(.storage(Self.failure)) }
    }
}
