import CoreDomain
import WebKit
import XCTest
@testable import FeatureMiniApps

/// The saved passwords in a real WKWebView: local HTML only (no network), the keychain an in-memory double.
@MainActor
final class WebLoginsWebViewTests: XCTestCase {
    private let site = "https://intranet.example.com"

    /// A classic sign-in form; it counts its submits and the `input` events a framework would hear.
    private let classic = """
    <html><body><form id="f" onsubmit="window.__submitted=(window.__submitted||0)+1;return false">
    <input id="u" name="email" type="email"><input id="p" name="pw" type="password"><button id="go" type="submit">Sign in</button></form>
    <script>window.__events=[];['u','p'].forEach(function(id){['input','change'].forEach(function(t){
      document.getElementById(id).addEventListener(t,function(){window.__events.push(id+':'+t)})})});</script></body></html>
    """

    /// A single-page app: no <form>, the fields are drawn a moment after the page loaded, the button is a plain one.
    private let spa = """
    <html><body><div id="app"></div><script>
    setTimeout(function(){
      document.getElementById('app').innerHTML =
        '<div class="card"><div class="row"><input id="u" placeholder="User"></div>' +
        '<div class="row"><input id="p" type="password"><button id="eye" type="button" aria-label="Show password">o</button></div>' +
        '<div class="actions"><button id="go" type="button">Log in</button></div></div>';
      document.getElementById('go').addEventListener('click', function(){ window.__clicked=(window.__clicked||0)+1; });
    }, 350);
    </script></body></html>
    """

    private func start(_ url: String, html: String, accounts: [Account] = [], vault: [String: String] = [:],
                       saved: [WebLogin] = []) async throws -> (Harness, MiniAppBrowserModel, WKWebView) {
        let h = try await Harness(accounts: accounts, vault: vault)
        let a = app("a", url)
        await h.seed([a])
        for login in saved { _ = try got(await SaveWebLogin(h.feature.webLogins)(login)) }
        let browser = h.model.browserModel(for: a)
        let parts = MiniAppWebParts.make(app: a, model: h.model, browser: browser, loadInitialPage: false)
        parts.web.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        parts.web.loadHTMLString(html, baseURL: URL(string: url))
        for _ in 0..<500 where parts.web.isLoading || parts.web.url == nil { try await Task.sleep(for: .milliseconds(10)) }
        if parts.web.isLoading || parts.web.url == nil { throw XCTSkip("WebKit did not load a page in this environment") }
        return (h, browser, parts.web)
    }

    /// Runs `source` as the page's own script would.
    private func js(_ web: WKWebView, _ source: String) async throws -> Any? { try await web.evaluateJavaScript(source) }
    private func text(_ web: WKWebView, _ id: String) async throws -> String {
        (try await js(web, "(document.getElementById('\(id)') || {}).value || ''") as? String) ?? ""
    }
    /// Types into a field the way a user does, as far as the page can tell.
    private func type(_ web: WKWebView, _ id: String, _ value: String) async throws {
        _ = try await js(web, "(function(){var e=document.getElementById('\(id)');e.value='\(value)';e.dispatchEvent(new Event('input',{bubbles:true}));return 1})()")
    }
    private func until(_ what: String = "condition", _ ok: () async throws -> Bool) async throws {
        for _ in 0..<160 { if try await ok() { return }; try await Task.sleep(for: .milliseconds(25)) }
        XCTFail("timed out waiting for \(what)")
    }
    /// Long enough for the script's check, the bridge and the app's answer to have happened.
    private func settle() async throws { try await Task.sleep(for: .milliseconds(700)) }

    // MARK: Autofill

    func testAClassicFormIsFilledWithTheOneSavedSignInAndNotSent() async throws {
        let (_, browser, web) = try await start("\(site)/login", html: classic, saved: [WebLogin(origin: site, username: "alice@corp.com", password: "hunter2")])
        try await until("the fill") { try await self.text(web, "p") == "hunter2" }
        do { let u = try await text(web, "u"); XCTAssertEqual(u, "alice@corp.com") }
        try await settle()
        do { let n = try await js(web, "window.__submitted || 0") as? Int; XCTAssertEqual(n, 0, "filled, never submitted") }
        // The fields changed the way typing changes them: a framework's listeners heard it.
        do { let e = try await js(web, "window.__events.join(',')") as? String; XCTAssertEqual(e, "u:input,u:change,p:input,p:change") }
        XCTAssertEqual(browser.passwords.saved.map(\.username), ["alice@corp.com"], "the toolbar's list is the page's")
        XCTAssertNil(browser.passwords.offer)
    }

    func testAFormDrawnLateWithoutAFormElementIsFilledToo() async throws {
        let (_, _, web) = try await start("https://spa.example.com/#/?temp=1730000000", html: spa,
                                          saved: [WebLogin(origin: "https://spa.example.com", username: "jun", password: "spa-pw")])
        do { let before = try await text(web, "p"); XCTAssertEqual(before, "", "nothing is there yet") }
        try await until("the fill") { try await self.text(web, "p") == "spa-pw" }
        do { let u = try await text(web, "u"); XCTAssertEqual(u, "jun") }
        try await settle()
        do { let n = try await js(web, "window.__clicked || 0") as? Int; XCTAssertEqual(n, 0) }
    }

    func testTextTheUserTypedIsNeverReplaced() async throws {
        let typed = classic.replacingOccurrences(of: "<input id=\"u\" name=\"email\" type=\"email\">", with: "<input id=\"u\" name=\"email\" type=\"email\" value=\"someone@else.io\">")
        let (_, _, web) = try await start("\(site)/login", html: typed, saved: [WebLogin(origin: site, username: "alice@corp.com", password: "hunter2")])
        try await settle()
        do { let u = try await text(web, "u"); XCTAssertEqual(u, "someone@else.io") }
        do { let p = try await text(web, "p"); XCTAssertEqual(p, "") }
    }

    func testASignInIsNeverFilledOnAnotherOrigin() async throws {
        let saved = [WebLogin(origin: site, username: "alice", password: "hunter2")]
        for other in ["http://intranet.example.com/login", "https://intranet.example.com:8443/login", "https://intranet.example.com.evil.io/login",
                      "https://example.com/login"] {
            let (_, browser, web) = try await start(other, html: classic, saved: saved)
            try await settle()
            do { let p = try await text(web, "p"); XCTAssertEqual(p, "", other) }
            XCTAssertEqual(browser.passwords.saved, [], other)
        }
    }

    func testAnHttpSiteIsFilledOnlyWithASignInSavedOnThatVeryOrigin() async throws {
        let (_, _, web) = try await start("http://nas.local:5000/", html: classic, saved: [WebLogin(origin: "http://nas.local:5000", username: "admin", password: "lan")])
        try await until("the fill") { try await self.text(web, "p") == "lan" }
    }

    func testSeveralSignInsOpenTheChooserAndThePickedOneIsFilled() async throws {
        let (_, browser, web) = try await start("\(site)/login", html: classic, saved: [WebLogin(origin: site, username: "alice", password: "a-pw"),
                                                                                         WebLogin(origin: site, username: "bob", password: "b-pw")])
        try await until("the chooser") { browser.passwords.chooserRequested }
        do { let p = try await text(web, "p"); XCTAssertEqual(p, "", "nothing is filled until one is picked") }
        XCTAssertEqual(browser.passwords.saved.map(\.username), ["alice", "bob"])
        // The user typed something meanwhile; picking a sign-in is an order, so it replaces it.
        try await type(web, "u", "typo")
        let filled = await browser.passwords.fill(WebLoginSummary(origin: site, username: "bob"))
        XCTAssertTrue(filled)
        do { let u = try await text(web, "u"); XCTAssertEqual(u, "bob") }
        do { let p = try await text(web, "p"); XCTAssertEqual(p, "b-pw") }
        // Deleting from the toolbar's list.
        await browser.passwords.delete(WebLoginSummary(origin: site, username: "alice"))
        XCTAssertEqual(browser.passwords.saved.map(\.username), ["bob"])
    }

    func testAPickedSignInIsNotFilledOnceThePageIsElsewhere() async throws {
        let (h, browser, web) = try await start("https://other.example.org/login", html: classic)
        _ = try got(await SaveWebLogin(h.feature.webLogins)(WebLogin(origin: site, username: "alice", password: "a-pw")))
        try await settle()
        let filled = await browser.passwords.fill(WebLoginSummary(origin: site, username: "alice"))
        XCTAssertFalse(filled)
        do { let p = try await text(web, "p"); XCTAssertEqual(p, "") }
    }

    // MARK: Capture

    func testSendingAClassicFormOffersToSaveAndNothingIsKeptUntilSaveIsChosen() async throws {
        let (h, browser, web) = try await start("\(site)/login", html: classic)
        try await settle()
        try await type(web, "u", "alice@corp.com"); try await type(web, "p", "hunter2")
        _ = try await js(web, "document.getElementById('go').click(); 1")
        try await until("the offer") { browser.passwords.offer != nil }
        XCTAssertEqual(browser.passwords.offer, MiniAppPasswordsModel.Offer(origin: site, username: "alice@corp.com", isUpdate: false))
        do { let kept = try got(await ListWebLogins(h.feature.webLogins)()); XCTAssertEqual(kept, [], "asked, not kept") }
        // "Not now" forgets it.
        browser.passwords.dismiss()
        XCTAssertNil(browser.passwords.offer)
        do { let saved = await browser.passwords.saveOffer(); XCTAssertFalse(saved, "what was typed is gone") }
        // Sent again, then "Save".
        try await Task.sleep(for: .milliseconds(1600))
        _ = try await js(web, "document.getElementById('f').requestSubmit(); 1")
        try await until("the offer") { browser.passwords.offer != nil }
        do { let saved = await browser.passwords.saveOffer(); XCTAssertTrue(saved) }
        XCTAssertNil(browser.passwords.offer)
        do { let kept = try got(await FindWebLogins(h.feature.webLogins)(for: web.url)); XCTAssertEqual(kept, [WebLogin(origin: site, username: "alice@corp.com", password: "hunter2")]) }
        XCTAssertEqual(browser.passwords.saved.map(\.username), ["alice@corp.com"])
    }

    func testTheSameSignInAsksNothingAndAnotherPasswordAsksToUpdate() async throws {
        let (h, browser, web) = try await start("\(site)/login", html: classic, saved: [WebLogin(origin: site, username: "alice", password: "hunter2")])
        try await until("the fill") { try await self.text(web, "p") == "hunter2" }
        _ = try await js(web, "document.getElementById('go').click(); 1")
        try await settle()
        XCTAssertNil(browser.passwords.offer, "saved as it is")
        try await Task.sleep(for: .milliseconds(1000))
        try await type(web, "p", "changed-pw")
        _ = try await js(web, "document.getElementById('go').click(); 1")
        try await until("the offer") { browser.passwords.offer != nil }
        XCTAssertEqual(browser.passwords.offer?.isUpdate, true)
        _ = await browser.passwords.saveOffer()
        do { let kept = try got(await FindWebLogins(h.feature.webLogins)(for: web.url)); XCTAssertEqual(kept.map(\.password), ["changed-pw"]) }
    }

    func testAFormWithoutAFormElementIsCapturedByItsButtonAndByEnter() async throws {
        let (_, browser, web) = try await start("https://spa.example.com/#/?temp=1", html: spa)
        try await until("the form") { try await self.js(web, "!!document.getElementById('p')") as? Bool == true }
        try await settle()
        try await type(web, "u", "jun"); try await type(web, "p", "spa-pw")
        // The show / hide button beside the password field is not a send.
        _ = try await js(web, "document.getElementById('eye').click(); 1")
        try await settle()
        XCTAssertNil(browser.passwords.offer)
        _ = try await js(web, "document.getElementById('go').click(); 1")
        try await until("the offer") { browser.passwords.offer != nil }
        XCTAssertEqual(browser.passwords.offer, MiniAppPasswordsModel.Offer(origin: "https://spa.example.com", username: "jun", isUpdate: false))
        browser.passwords.dismiss()
        try await Task.sleep(for: .milliseconds(1600))
        try await type(web, "p", "second")
        _ = try await js(web, "document.getElementById('p').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })); 1")
        try await until("the offer") { browser.passwords.offer != nil }
        do { let saved = await browser.passwords.saveOffer(); XCTAssertTrue(saved) }
    }

    func testNeverForThisSiteStopsTheQuestion() async throws {
        let (h, browser, web) = try await start("\(site)/login", html: classic)
        try await settle()
        try await type(web, "u", "alice"); try await type(web, "p", "hunter2")
        _ = try await js(web, "document.getElementById('go').click(); 1")
        try await until("the offer") { browser.passwords.offer != nil }
        await browser.passwords.neverForSite()
        XCTAssertNil(browser.passwords.offer)
        do { let never = try got(await NeverSaveForSite(h.feature.webLogins).list()); XCTAssertEqual(never, [site]) }
        try await Task.sleep(for: .milliseconds(1600))
        _ = try await js(web, "document.getElementById('go').click(); 1")
        try await settle()
        XCTAssertNil(browser.passwords.offer)
        do { let kept = try got(await ListWebLogins(h.feature.webLogins)()); XCTAssertEqual(kept, []) }
    }

    // MARK: What the page cannot do

    func testThePagesOwnScriptsCannotReachTheScriptItsBridgeOrASavedPassword() async throws {
        let (_, browser, web) = try await start("\(site)/login", html: "<html><body><p>no form here</p></body></html>",
                                                saved: [WebLogin(origin: site, username: "alice", password: "hunter2")])
        try await settle()
        // The script's globals live in another world.
        do { let t = try await js(web, "typeof window.__wnFillLogin + ' ' + typeof window.__wnPasswords") as? String; XCTAssertEqual(t, "undefined undefined") }
        do { let t = try await web.evaluateJavaScript("typeof window.__wnFillLogin", in: nil, contentWorld: MiniAppPasswordCapability.world) as? String
             XCTAssertEqual(t, "function") }
        // The page's world has the bridge (notifications use it), but a password call from there is refused whatever it sends.
        _ = try await js(web, """
        (function(){ var b = window.webkit.messageHandlers.wnBridge;
          ['', 'guess', '0123456789abcdef0123456789abcdef'].forEach(function(token){
            b.postMessage({ name: 'wnPasswordSubmit', token: token, args: ['mallory', 'planted'] });
            b.postMessage({ name: 'wnPasswordForm', token: token, args: [true] });
          }); return 1 })()
        """)
        try await settle()
        XCTAssertNil(browser.passwords.offer)
        XCTAssertFalse(browser.passwords.chooserRequested)
        // A form the page draws afterwards is filled through the other world; the page still has no handle on the fill.
        _ = try await js(web, "document.body.innerHTML = '<input id=u><input id=p type=password>'; 1")
        try await until("the fill") { try await self.text(web, "p") == "hunter2" }
    }

    func testACallWithTheRightTokenFromThePagesWorldIsStillRefused() async throws {
        let h = try await Harness()
        let a = app("a", "\(site)/")
        await h.seed([a])
        let browser = h.model.browserModel(for: a)
        let passwords = MiniAppPasswordCapability(token: "known-token", tab: browser)
        let notifications = MiniAppNotificationCapability(notifier: h.notifier, isWindowFocused: { true })
        browser.passwords.bind(h.model.services.webLogins, filler: WKLoginFiller(web: nil))
        let prompter = MiniAppPermissionPrompter(model: h.model)
        let bridge = MiniAppBridge(capabilities: [(notifications, notifications.token), (passwords, "known-token")]) { web in
            MiniAppPageContext(app: { a }, pageURL: web?.url, model: h.model, prompter: prompter)
        }
        XCTAssertEqual(bridge.worlds, [.page, MiniAppPasswordCapability.world])
        let web = MiniAppWebFactory.makeWebView(configuration: MiniAppWebFactory.makeConfiguration(bridge: bridge, capabilities: [notifications, passwords]))
        web.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        web.loadHTMLString("<html><body>x</body></html>", baseURL: URL(string: "\(site)/"))
        for _ in 0..<500 where web.isLoading || web.url == nil { try await Task.sleep(for: .milliseconds(10)) }
        if web.isLoading || web.url == nil { throw XCTSkip("WebKit did not load a page in this environment") }
        let call = "window.webkit.messageHandlers.wnBridge.postMessage({ name: 'wnPasswordSubmit', token: 'known-token', args: ['mallory', 'planted'] }); 1"
        _ = try await web.evaluateJavaScript(call)
        try await settle()
        XCTAssertNil(browser.passwords.offer, "the page's world is not the capability's")
        // The very same call from the capability's own world is the real thing.
        _ = try await web.evaluateJavaScript(call, in: nil, contentWorld: MiniAppPasswordCapability.world)
        try await until("the offer") { browser.passwords.offer != nil }
        XCTAssertEqual(browser.passwords.offer?.username, "mallory")
    }

    // MARK: ZenTao keeps priority

    func testZenTaosOwnLoginPageIsLeftToTheAppsAccount() async throws {
        let account = Account(id: "z", workspaceId: "w", providerType: .zentao, handle: "dyno", baseUrl: "https://zentao.example.com", credentialsRef: "secret:z")
        let html = """
        <html><body><form id="f" onsubmit="window.__submitted=(window.__submitted||0)+1;return false">
        <input name="account" id="account"><input type="password" name="password" id="p"><button type="submit">Go</button></form></body></html>
        """
        let (_, browser, web) = try await start("https://zentao.example.com/user-login.html", html: html, accounts: [account], vault: ["secret:z": "s3cret"],
                                                saved: [WebLogin(origin: "https://zentao.example.com", username: "someone-else", password: "other-pw")])
        try await until("the app's own sign-in") { try await self.js(web, "window.__submitted || 0") as? Int == 1 }
        do { let u = try await text(web, "account"); XCTAssertEqual(u, "dyno") }
        do { let p = try await text(web, "p"); XCTAssertEqual(p, "s3cret") }
        try await settle()
        XCTAssertNil(browser.passwords.offer, "the app's own account is not offered for saving")
        XCTAssertFalse(browser.passwords.chooserRequested)
    }
}
