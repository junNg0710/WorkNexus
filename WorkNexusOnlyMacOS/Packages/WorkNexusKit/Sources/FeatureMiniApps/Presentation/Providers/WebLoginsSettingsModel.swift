import CoreDomain
import Foundation
import Observation

/// New (no Dart counterpart): settings' saved passwords — each site and user (never a password: none is read here), and the
/// sites the user never wants to be asked about.
@MainActor @Observable
final class WebLoginsSettingsModel {
    private(set) var items: [WebLoginSummary] = []
    private(set) var neverSave: [String] = []
    private(set) var loadFailed = false
    private let services: WebLoginServices

    init(services: WebLoginServices) { self.services = services }

    func load() async {
        switch await services.list() {
        case .success(let all): items = all; loadFailed = false
        case .failure: loadFailed = true
        }
        if case .success(let origins) = await services.never.list() { neverSave = origins }
    }

    /// Each answers whether the change was kept; the lists are read again either way.
    func delete(_ item: WebLoginSummary) async -> Bool { await change { await $0.forget(item) } }
    func deleteAll() async -> Bool { await change { await $0.forget.all() } }
    func allow(_ origin: String) async -> Bool { await change { await $0.never.allow(origin) } }

    private func change(_ run: (WebLoginServices) async -> Outcome<Void>) async -> Bool {
        let result = await run(services)
        await load()
        if case .success = result { return true }
        return false
    }
}
