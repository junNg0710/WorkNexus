import CoreDomain
import Foundation

/// Ported from: lib/features/mini_apps/presentation/util/mini_app_login_capability.dart
/// Signs in a mini app that shows a ZenTao server the app has an account on, with that account's saved login — the web view
/// remembers no passwords of its own. The script (see `MiniAppScripts.login`) fills ZenTao's login form when it is empty,
/// and only on that server's login page: the app answers when the main frame is that page.
///
/// The form is submitted once per page of the app that is open (this object lives as long as that view): a wrong password is
/// not tried again and again (ZenTao may lock the account), and after signing out the form is filled but left to the user,
/// so signing out and switching account still work.
@MainActor
final class MiniAppLoginCapability: MiniAppPageCapability {
    let token: String
    private var submitted = false

    init(token: String = newMiniAppPageToken()) { self.token = token }

    var script: (source: String, atDocumentStart: Bool)? { (MiniAppScripts.login.replacingOccurrences(of: "__TOKEN__", with: token), false) }
    var handledCalls: Set<String> { ["miniAppLogin"] }

    func handle(_ name: String, args: [Any], page: MiniAppPageContext) async -> Any? {
        switch await page.model.services.findSavedWebLogin(page.pageURL) {
        case .failure: return nil
        case .success(nil): return nil
        case .success(let login?):
            let submit = !submitted
            submitted = true
            return ["account": login.account, "password": login.password, "submit": submit] as [String: Any]
        }
    }
}
