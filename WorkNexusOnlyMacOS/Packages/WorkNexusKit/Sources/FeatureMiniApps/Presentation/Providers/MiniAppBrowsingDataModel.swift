import CoreDomain
import Foundation
import Observation

/// Ported from: lib/features/mini_apps/presentation/providers/mini_app_browsing_data_controller.dart
/// Clears what the mini apps' pages keep (pass-throughs to `MiniAppBrowsingDataRepository`). `running` is the job under way:
/// `cacheJob`, `allJob` or the id of the app being cleared. The open pages reload afterwards, so none keeps a sign-in it no
/// longer has.
@MainActor @Observable
final class MiniAppBrowsingDataModel {
    static let cacheJob = "#cache"
    static let allJob = "#all"

    private(set) var running: String?
    private let data: MiniAppBrowsingDataRepository
    private let model: MiniAppsModel

    init(data: MiniAppBrowsingDataRepository, model: MiniAppsModel) { self.data = data; self.model = model }

    var canClear: Bool { data.canClear }

    func clearCache(_ apps: [MiniApp]) async -> Bool { await job(Self.cacheJob, apps) { await $0.clearCache() } }
    /// The site's kept session cookies go with what the web view had for it.
    func clearSite(_ app: MiniApp) async -> Bool {
        let done = await job(app.id, [app]) { await $0.clearSite(url: app.url) }
        if done { await model.sessionCookies?.snapshotNow() }
        return done
    }

    /// The session cookies kept between runs are sign-ins too: they are forgotten with the rest.
    func clearAll(_ apps: [MiniApp]) async -> Bool {
        let done = await job(Self.allJob, apps) { await $0.clearAll(urls: apps.map(\.url)) }
        if done { await model.sessionCookies?.forgetAll() }
        return done
    }

    private func job(_ id: String, _ reload: [MiniApp], _ run: (MiniAppBrowsingDataRepository) async -> Outcome<Void>) async -> Bool {
        guard running == nil else { return false }
        running = id
        let result = await run(data)
        running = nil
        guard case .success = result else { return false }
        model.reloadRunningApps(ids: reload.map(\.id))
        return true
    }
}
