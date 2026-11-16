import CoreDomain
import Foundation
import WebKit

/// Where a page's request is being answered: the app it belongs to and the page that asked. `app` is read at each call, so
/// an app edited after its page opened (a new address) is judged by what it is now.
@MainActor
struct MiniAppPageContext {
    let app: () -> MiniApp
    /// The address of the page (frame) that sent the call.
    let pageURL: URL?
    let model: MiniAppsModel
    let prompter: MiniAppPermissionPrompter
    /// The page is in the app's selected tab, so it is what the user is looking at (a background tab's is not).
    var selectedTab = true
}

/// Something the app lets a mini app's page do through the app itself — show a notification, sign in. Each is its own class;
/// the web view only knows this interface, so a new capability is added without touching it.
@MainActor
protocol MiniAppPageCapability: AnyObject {
    /// A script run in the page's main frame, to take over the web API the capability stands behind.
    var script: (source: String, atDocumentStart: Bool)? { get }
    /// The bridge call names this capability answers.
    var handledCalls: Set<String> { get }
    /// Answers one call (a Promise value for the page: String, number, dictionary or nil).
    func handle(_ name: String, args: [Any], page: MiniAppPageContext) async -> Any?
}

/// Ported from: lib/features/mini_apps/presentation/util/mini_app_page_token.dart
func newMiniAppPageToken() -> String {
    var bytes = [UInt8](repeating: 0, count: 16)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return bytes.map { String(format: "%02x", $0) }.joined()
}

/// Receives the bridge calls of every page of one web view's content controller and hands them to the capability that
/// answers that name. Calls from a frame other than the main frame, or without the capability's token, are ignored.
@MainActor
final class MiniAppBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let handlerName = "wnBridge"
    private let capabilities: [MiniAppPageCapability]
    private let tokens: [ObjectIdentifier: String]
    private let context: (WKWebView?) -> MiniAppPageContext

    init(capabilities: [(MiniAppPageCapability, token: String)], context: @escaping (WKWebView?) -> MiniAppPageContext) {
        self.capabilities = capabilities.map(\.0)
        tokens = Dictionary(uniqueKeysWithValues: capabilities.map { (ObjectIdentifier($0.0), $0.token) })
        self.context = context
    }

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                                           replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        MainActor.assumeIsolated {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let name = body["name"] as? String,
                  let token = body["token"] as? String, let capability = capabilities.first(where: { $0.handledCalls.contains(name) }),
                  tokens[ObjectIdentifier(capability)] == token else { replyHandler(nil, nil); return }
            let args = body["args"] as? [Any] ?? []
            let page = context(message.webView)
            Task { @MainActor in replyHandler(await capability.handle(name, args: args, page: page), nil) }
        }
    }
}
