import Foundation
import GRDB

/// DB rows of the feature's tables; never leave `Data/` (rule 3.3).
struct MiniAppRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "miniApps"
    var id: String
    var name: String
    var url: String
    var iconPath: String?
    var lastUrl: String?
    var position: Int
}

struct MiniAppTabsRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "miniAppTabs"
    var miniAppId: String
    var tabsJson: String
    var selected: Int

    var urls: [String] { (tabsJson.data(using: .utf8).flatMap { try? JSONDecoder().decode([String].self, from: $0) }) ?? [] }
    init(miniAppId: String, urls: [String], selected: Int) {
        self.miniAppId = miniAppId; self.selected = selected
        tabsJson = (try? JSONEncoder().encode(urls)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}

struct MiniAppPermissionRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "miniAppPermissions"
    var miniAppId: String
    var kind: String
    var allowed: Bool
}

struct NativeAppRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "nativeApps"
    var id: String
    var name: String
    var bundleId: String
    var path: String
    var position: Int
}
