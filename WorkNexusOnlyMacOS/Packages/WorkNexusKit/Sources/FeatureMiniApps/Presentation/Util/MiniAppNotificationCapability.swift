import CoreDomain
import CoreUI
import Foundation

/// Ported from: lib/features/mini_apps/presentation/util/mini_app_notifications.dart
/// Lets a page show notifications, as OS notifications (see `MiniAppScripts.notifications`).
@MainActor
final class MiniAppNotificationCapability: MiniAppPageCapability {
    let token: String
    private let notifier: DesktopNotifying
    private let isWindowFocused: () -> Bool
    private static let kinds: [MiniAppPermissionKind] = [.notifications]

    init(token: String = newMiniAppPageToken(), notifier: DesktopNotifying, isWindowFocused: @escaping () -> Bool) {
        self.token = token; self.notifier = notifier; self.isWindowFocused = isWindowFocused
    }

    var script: (source: String, atDocumentStart: Bool)? { (MiniAppScripts.notifications.replacingOccurrences(of: "__TOKEN__", with: token), true) }
    var handledCalls: Set<String> { ["miniAppNotificationState", "miniAppNotificationPermission", "miniAppNotify"] }

    func handle(_ name: String, args: [Any], page: MiniAppPageContext) async -> Any? {
        let app = page.app()
        let onAppSite = IsMiniAppOrigin()(app.url, page.pageURL)
        switch name {
        case "miniAppNotificationState":
            guard onAppSite else { return "denied" }
            switch await page.model.services.resolvePermission(app.id, Self.kinds) {
            case .allow: return "granted"
            case .block: return "denied"
            case nil: return "default"
            }
        case "miniAppNotificationPermission":
            let answer = await page.prompter.ask(app: app, kinds: Self.kinds, origin: page.pageURL)
            return answer == .allow ? "granted" : "denied"
        case "miniAppNotify":
            guard args.count >= 1, onAppSite, await page.model.services.resolvePermission(app.id, Self.kinds) == .allow else { return nil }
            let title = "\(args[0])"
            let body = args.count > 1 ? "\(args[1])" : ""
            let tag = args.count > 2 ? "\(args[2])" : ""
            // The user is looking at this very page: it needs no pop-up.
            if page.model.isShown(app.id) && page.selectedTab && isWindowFocused() { return nil }
            await notifier.show(
                // One per tag, so a page updating a notification replaces it.
                id: Self.stableId(app.id, tag.isEmpty ? title : tag), title: title, body: body, payload: miniAppNotificationPayload(app.id))
            return nil
        default: return nil
        }
    }

    /// A positive id that is the same for the same app and tag within and across runs (FNV-1a).
    static func stableId(_ appId: String, _ tag: String) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in (appId + "\u{0}" + tag).utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return Int(h & 0x7fff_ffff)
    }
}
