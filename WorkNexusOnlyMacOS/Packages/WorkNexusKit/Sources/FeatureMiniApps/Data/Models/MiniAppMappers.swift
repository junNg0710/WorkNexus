/// Ported from: lib/features/mini_apps/data/mappers/mini_app_mapper.dart, mini_app_permission_mapper.dart
extension MiniApp {
    init(row r: MiniAppRow, tabs: MiniAppTabsRow? = nil) {
        self.init(id: r.id, name: r.name, url: r.url, iconPath: r.iconPath, lastUrl: r.lastUrl, position: r.position,
                  openTabs: tabs?.urls ?? [], selectedTab: tabs?.selected ?? 0)
    }
}

extension MiniAppRow {
    init(app a: MiniApp) { self.init(id: a.id, name: a.name, url: a.url, iconPath: a.iconPath, lastUrl: a.lastUrl, position: a.position) }
}

extension MiniAppPermissionGrant {
    /// A row naming a kind this build does not know (written by a newer one) is skipped.
    init?(row r: MiniAppPermissionRow) {
        guard let kind = MiniAppPermissionKind(rawValue: r.kind) else { return nil }
        self.init(miniAppId: r.miniAppId, kind: kind, decision: r.allowed ? .allow : .block)
    }
}

extension MiniAppPermissionRow {
    init(grant g: MiniAppPermissionGrant) { self.init(miniAppId: g.miniAppId, kind: g.kind.rawValue, allowed: g.decision == .allow) }
}

extension NativeApp {
    init(row r: NativeAppRow) { self.init(id: r.id, name: r.name, bundleId: r.bundleId, path: r.path, position: r.position) }
}

extension NativeAppRow {
    init(app a: NativeApp) { self.init(id: a.id, name: a.name, bundleId: a.bundleId, path: a.path, position: a.position) }
}
