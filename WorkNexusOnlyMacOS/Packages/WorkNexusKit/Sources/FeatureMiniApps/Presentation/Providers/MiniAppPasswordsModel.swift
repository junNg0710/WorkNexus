import CoreDomain
import Foundation
import Observation

/// The use cases behind the saved passwords, as the presentation needs them.
struct WebLoginServices: Sendable {
    var list: ListWebLogins
    var find: FindWebLogins
    var save: SaveWebLogin
    var forget: ForgetWebLogin
    var never: NeverSaveForSite
    var offer: ResolveWebLoginOffer

    init(_ logins: WebLoginRepository) {
        list = ListWebLogins(logins); find = FindWebLogins(logins); save = SaveWebLogin(logins); forget = ForgetWebLogin(logins)
        never = NeverSaveForSite(logins); offer = ResolveWebLoginOffer(logins)
    }
}

/// New (no Dart counterpart): the saved passwords of one tab — what the toolbar's key button lists for the page's site, the
/// "Save password?" bar and the chooser that opens when a form has several sign-ins to pick from. The typed password of a
/// pending offer is kept here in memory only, out of what the views observe, until the user answers or it runs out.
@MainActor @Observable
final class MiniAppPasswordsModel {
    /// What the bar asks about: never the password itself.
    struct Offer: Equatable {
        var origin: String
        var username: String
        var isUpdate: Bool
    }

    /// An unanswered offer is dropped after this long, and the typed password with it.
    static let offerLifetime: Duration = .seconds(180)

    private(set) var offer: Offer?
    /// The origin of the page the list below is for.
    private(set) var origin: String?
    /// The sign-ins saved for `origin`.
    private(set) var saved: [WebLoginSummary] = []
    /// A form with several sign-ins to pick from appeared: the toolbar's button opens its list, then clears this.
    var chooserRequested = false

    @ObservationIgnored private var pending: WebLogin?
    @ObservationIgnored private var services: WebLoginServices?
    /// The tab's own page, and the page (a window the tab opened, maybe) whose form was reported last.
    @ObservationIgnored private var pageFiller: MiniAppLoginFilling?
    @ObservationIgnored private var formFiller: MiniAppLoginFilling?
    @ObservationIgnored private var expiry: Task<Void, Never>?

    deinit { expiry?.cancel() }

    /// Hands over the use cases and the way into the tab's page (when its web view exists).
    func bind(_ services: WebLoginServices, filler: MiniAppLoginFilling) {
        self.services = services
        pageFiller = filler
    }

    // MARK: What the page reports

    /// A sign-in form is on the page at `origin`, which has `saved` sign-ins; `filler` reaches that very page.
    func formAppeared(origin: String, saved: [WebLoginSummary], filler: MiniAppLoginFilling) {
        self.origin = origin; self.saved = saved; formFiller = filler
    }

    func requestChooser() { chooserRequested = true }

    /// The form was sent with `login`, which is not saved as it is: ask.
    func offer(_ login: WebLogin, isUpdate: Bool) {
        pending = login
        offer = Offer(origin: login.origin, username: login.username, isUpdate: isUpdate)
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: Self.offerLifetime)
            if !Task.isCancelled { self?.dismiss() }
        }
    }

    // MARK: The bar's answers

    /// "Save" / "Update": keeps the sign-in. False when the keychain refused it (the bar then stays).
    @discardableResult
    func saveOffer() async -> Bool {
        guard let login = pending, let services else { return false }
        guard case .success = await services.save(login) else { return false }
        dismiss()
        await refresh(origin: login.origin)
        return true
    }

    /// "Never for this site".
    func neverForSite() async {
        guard let login = pending, let services else { dismiss(); return }
        _ = await services.never(login.origin)
        dismiss()
    }

    /// "Not now": forgets what was typed.
    func dismiss() {
        expiry?.cancel(); expiry = nil
        pending = nil; offer = nil
    }

    // MARK: The toolbar's list

    /// Lists the sign-ins of the page at `address` (no passwords are read).
    func refresh(address: String) async { await refresh(origin: webOrigin(ofAddress: address)) }

    private func refresh(origin: String?) async {
        self.origin = origin
        guard let origin, let services, case .success(let list) = await services.list(origin: origin) else { saved = []; return }
        // The page moved on meanwhile: its own answer is the one that counts.
        if self.origin == origin { saved = list }
    }

    /// Fills the page's form with the sign-in the user picked. False when the page has no form (or is on another site now).
    func fill(_ summary: WebLoginSummary) async -> Bool {
        guard let services, case .success(let logins) = await services.find(for: URL(string: summary.origin)),
              let login = logins.first(where: { $0.username == summary.username }) else { return false }
        if await formFiller?.fill(login, force: true) == true { return true }
        return await pageFiller?.fill(login, force: true) ?? false
    }

    func delete(_ summary: WebLoginSummary) async {
        guard let services else { return }
        _ = await services.forget(summary)
        await refresh(origin: origin)
    }
}
