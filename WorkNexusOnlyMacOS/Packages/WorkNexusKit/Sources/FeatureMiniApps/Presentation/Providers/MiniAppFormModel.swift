import CoreDomain
import CoreUI
import Foundation
import Observation

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_dialog.dart (state)
/// The add / edit dialog's form: the address and name, and — editing — the icon, with the commands that save the app and
/// change the icon. A failure is kept as the sentence the dialog shows under the address.
@MainActor @Observable
final class MiniAppFormModel {
    var url: String
    var name: String
    private(set) var iconPath: String?
    private(set) var error: String?
    private(set) var saving = false
    /// An icon is being fetched or copied in.
    private(set) var iconBusy = false

    /// The app being edited; nil when adding one.
    let existing: MiniApp?
    private let model: MiniAppsModel

    init(model: MiniAppsModel, existing: MiniApp? = nil) {
        self.model = model; self.existing = existing
        url = existing?.url ?? ""; name = existing?.name ?? ""; iconPath = existing?.iconPath
    }

    var canSave: Bool { !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saving && !iconBusy }

    /// The address was typed in: its error no longer applies.
    func clearError() { error = nil }

    /// Adds the app, or applies the edit; the app as kept, or nil with `error` set.
    func save() async -> MiniApp? {
        guard canSave else { return nil }
        saving = true; error = nil
        defer { saving = false }
        let result: Outcome<MiniApp>
        if let existing {
            result = await model.services.updateMiniApp(app: existing, url: url, name: name, iconPath: iconPath)
        } else {
            result = await model.services.addMiniApp(url: url, name: name, existing: model.apps)
        }
        switch result {
        case .success(let app): return app
        case .failure(let failure):
            if case .parse = failure { error = appString("miniAppInvalidUrl", "Enter a web address such as example.com") }
            else { error = appFormat("actionFailed", "Failed: %1$@", failure.message) }
            return nil
        }
    }

    /// Takes the image at `path` as the icon.
    func importIcon(from path: String) async {
        guard let existing else { return }
        await changeIcon { await self.model.services.apps.importIcon(id: existing.id, sourcePath: path).map { Optional($0) } }
    }

    /// Takes the icon of the site in the address field.
    func useSiteIcon() async {
        guard let existing else { return }
        await changeIcon { await self.model.services.apps.fetchSiteIcon(id: existing.id, pageUrl: self.url) }
    }

    /// Runs an icon change, keeping the dialog open and showing its failure inline.
    private func changeIcon(_ run: () async -> Outcome<String?>) async {
        iconBusy = true; error = nil
        defer { iconBusy = false }
        if case .success(let path?) = await run() { iconPath = path }
        else { error = appString("miniAppIconFailed", "Couldn't get an icon this way") }
    }
}
