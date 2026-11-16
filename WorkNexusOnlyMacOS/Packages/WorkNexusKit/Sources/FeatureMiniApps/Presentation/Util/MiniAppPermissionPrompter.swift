import AppKit
import CoreDomain
import Foundation

/// Ported from: lib/features/mini_apps/presentation/util/ask_mini_app_permission.dart (+ widgets/mini_app_permission_dialog.dart)
/// Whether app `app`'s page, now at `origin`, may use `kinds`: the answer remembered for them, or — the first time — the
/// user's, asked in a dialog and then remembered. A dismissed dialog blocks this once without remembering it. A page on
/// another site than the app's is blocked without asking: it would otherwise get the app's answers, or be asked about
/// under the app's name. A page in the background is asked once the user opens its app, not over whatever they are
/// looking at.
@MainActor
final class MiniAppPermissionPrompter {
    private unowned let model: MiniAppsModel
    /// Dialogs open right now, by app and kinds, so a page asking twice at once gets one dialog.
    private var asking: [String: Task<MiniAppPermissionDecision, Never>] = [:]
    /// Shows the question and answers it (nil: dismissed). Replaceable, for tests.
    var present: (_ site: String, _ kinds: [MiniAppPermissionKind]) async -> MiniAppPermissionDecision? = MiniAppPermissionPrompter.showAlert

    init(model: MiniAppsModel) { self.model = model }

    func ask(app: MiniApp, kinds: some Sequence<MiniAppPermissionKind>, origin: URL?) async -> MiniAppPermissionDecision {
        let sorted = Set(kinds).sorted()
        guard !sorted.isEmpty, IsMiniAppOrigin()(app.url, origin) else { return .block }
        let services = model.services
        if let saved = await services.resolvePermission(app.id, sorted) { return saved }
        await model.untilShown(app.id)
        let key = "\(app.id)|\(sorted.map(\.rawValue).joined(separator: ","))"
        if let running = asking[key] { return await running.value }
        let task = Task { await self.askNow(app, sorted) }
        asking[key] = task
        let answer = await task.value
        asking[key] = nil
        return answer
    }

    private func askNow(_ app: MiniApp, _ kinds: [MiniAppPermissionKind]) async -> MiniAppPermissionDecision {
        let services = model.services
        // Answered by an earlier dialog while this request waited.
        if let saved = await services.resolvePermission(app.id, kinds) { return saved }
        let host = URL(string: app.url)?.host
        guard let answer = await present(host?.isEmpty == false ? host! : app.name, kinds) else { return .block }
        for kind in kinds { _ = await services.permissions.save(MiniAppPermissionGrant(miniAppId: app.id, kind: kind, decision: answer)) }
        return answer
    }

    /// "<site> wants to <action>, <action> and <action>", with what each means and that the choice is remembered.
    static func showAlert(site: String, kinds: [MiniAppPermissionKind]) async -> MiniAppPermissionDecision? {
        let alert = NSAlert()
        let actions = ListFormatter.localizedString(byJoining: kinds.map(\.action))
        alert.messageText = String(format: String(localized: "miniAppPermissionTitle"), site, actions)
        alert.informativeText = (kinds.map(\.detail) + [String(localized: "miniAppPermissionRemembered")]).joined(separator: "\n")
        alert.addButton(withTitle: String(localized: "miniAppPermissionAllow"))
        alert.addButton(withTitle: String(localized: "miniAppPermissionBlock"))
        let response = await run(alert)
        switch response { case .alertFirstButtonReturn: return .allow; case .alertSecondButtonReturn: return .block; default: return nil }
    }

    /// As a sheet on the key window when there is one, else modal.
    static func run(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        if let window = NSApp.keyWindow { return await alert.beginSheetModal(for: window) }
        return alert.runModal()
    }
}
