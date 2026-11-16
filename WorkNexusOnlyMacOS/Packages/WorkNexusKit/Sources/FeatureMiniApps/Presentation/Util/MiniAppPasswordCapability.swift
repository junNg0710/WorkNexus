import CoreDomain
import Foundation
import WebKit

/// New (no Dart counterpart): the mini apps' saved passwords, on the page's side (see `MiniAppPasswordScripts`).
///
/// - A sign-in form appeared: when exactly one sign-in is saved for the page's origin and the form is empty it is filled
///   (never sent); with several the toolbar's chooser opens. The origin is the one WebKit reports for the frame, and it must
///   be the one the web view shows — not anything the page says.
/// - The form was sent: the app asks (a bar under the toolbar) whether to save, or update, what was typed. Nothing is kept
///   until the user says so.
///
/// The page's scripts cannot reach any of it: the script and its bridge live in `world`, and the bridge refuses the calls
/// from any other world. A saved password only ever travels app → this world, as an argument of `__wnFillLogin`.
/// ZenTao's own login page of an account the app holds is left to `MiniAppLoginCapability`.
@MainActor
final class MiniAppPasswordCapability: MiniAppPageCapability {
    /// The JavaScript world of the script, apart from the page's.
    static let world = WKContentWorld.world(name: "wnPasswords")
    static let formCall = "wnPasswordForm"
    static let submitCall = "wnPasswordSubmit"

    let token: String
    /// The tab the capability was made for. A tab or window the page opened shares its opener's capability, so the tab is
    /// looked up by the web view first.
    private weak var tab: MiniAppBrowserModel?

    init(token: String = newMiniAppPageToken(), tab: MiniAppBrowserModel?) { self.token = token; self.tab = tab }

    var script: (source: String, atDocumentStart: Bool)? {
        (MiniAppPasswordScripts.source.replacingOccurrences(of: "__TOKEN__", with: token), false)
    }
    var handledCalls: Set<String> { [Self.formCall, Self.submitCall] }
    var contentWorld: WKContentWorld { Self.world }

    func handle(_ name: String, args: [Any], page: MiniAppPageContext) async -> Any? {
        // The frame's origin as WebKit has it, and only while it is the page the web view shows.
        guard let origin = page.frameOrigin, origin == webOrigin(of: page.pageURL) else { return nil }
        let state = page.model.tab(appId: page.app().id, web: page.web)?.passwords ?? tab?.passwords
        guard let state else { return nil }
        // ZenTao's login page of an account the app holds is signed in by the app itself.
        if case .success(.some) = await page.model.services.findSavedWebLogin(page.pageURL) { return nil }
        let services = page.model.services.webLogins
        switch name {
        case Self.formCall:
            let filler = WKLoginFiller(web: page.web)
            guard case .success(let saved) = await services.list(origin: origin) else { return nil }
            state.formAppeared(origin: origin, saved: saved, filler: filler)
            guard (args.first as? Bool) == true, !saved.isEmpty else { return nil }
            if saved.count > 1 { state.requestChooser(); return nil }
            guard case .success(let logins) = await services.find(for: page.pageURL), logins.count == 1, logins[0].origin == origin else { return nil }
            _ = await filler.fill(logins[0], force: false)
        case Self.submitCall:
            guard args.count >= 2, let username = args[0] as? String, let password = args[1] as? String else { return nil }
            let login = WebLogin(origin: origin, username: username, password: password)
            guard case .success(let offer) = await services.offer(login) else { return nil }
            switch offer {
            case .none: break
            case .save: state.offer(login, isUpdate: false)
            case .update: state.offer(login, isUpdate: true)
            }
        default: break
        }
        // The page learns nothing from the answer.
        return nil
    }
}

/// Puts a sign-in into the form of the page a web view shows.
@MainActor
protocol MiniAppLoginFilling {
    /// True when the form was filled. `force`: the user picked the sign-in, so it replaces what is in the fields.
    func fill(_ login: WebLogin, force: Bool) async -> Bool
}

/// Fills through the password script's own world: the password is an argument of a call into that world, which the page's
/// scripts cannot see, and the script fills only while the page is still on the sign-in's origin.
@MainActor
struct WKLoginFiller: MiniAppLoginFilling {
    weak var web: WKWebView?

    func fill(_ login: WebLogin, force: Bool) async -> Bool {
        guard let web, webOrigin(of: web.url) == login.origin else { return false }
        let filled = try? await web.callAsyncJavaScript(
            "return window.__wnFillLogin ? window.__wnFillLogin(origin, username, password, force) : false",
            arguments: ["origin": login.origin, "username": login.username, "password": login.password, "force": force],
            in: nil, contentWorld: MiniAppPasswordCapability.world)
        return (filled as? Bool) ?? false
    }
}
