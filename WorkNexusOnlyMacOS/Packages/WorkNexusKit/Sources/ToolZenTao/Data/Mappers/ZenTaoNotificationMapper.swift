import CoreDomain
import Foundation

// Ported from: lib/features/notifications/data/mappers/zentao_notification_mapper.dart

/// Parses the view of ZenTao's `message-ajaxGetDropmenu-all` page into notifications. `allMessages` is
/// `{ "2026-10-09": [message, ...], ... }` (or a plain list); each message's `data` is HTML such as
/// `JunNg assigned Bug <a data-url='.../bug-view-6492.html'>[#6492::Title]</a>`.
func zenTaoNotificationsFromView(_ view: JSON, accountId: String) -> [ZenTaoNotification] {
    var groups: [[Any]] = []
    if asEntries(view["allMessages"]) != nil {
        groups = listOrMapValues(view["allMessages"]).compactMap { $0 as? [Any] }
    } else if let list = view["allMessages"] as? [Any] {
        groups = [list]
    }
    return groups.flatMap { $0 }.compactMap { asMap($0).flatMap { notification($0, accountId) } }
}

private func regex(_ p: String, _ o: NSRegularExpression.Options = []) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: o) }
private let anchorRegex = regex(##"<a\b[^>]*?(?:data-url|href)\s*=\s*['"]([^'"#][^'"]*)['"][^>]*>(.*?)</a>"##, [.caseInsensitive, .dotMatchesLineSeparators])
private let refRegex = regex(#"^\[#(\d+)::(.*)\]$"#, [.dotMatchesLineSeparators])
/// `bug-view-6492`, `/bug-view-6492.html` or `?m=bug&f=view&id=6492`.
private let pathViewRegex = regex(#"(?:^|[/=])([a-z]+)-view-(\d+)"#, [.caseInsensitive])
private let queryViewRegex = regex(#"[?&]m=([a-z]+)&f=view&\w*id=(\d+)"#, [.caseInsensitive])

private func group(_ m: NSTextCheckingResult?, _ i: Int, in s: String) -> String? {
    guard let m, m.range(at: i).location != NSNotFound else { return nil }
    return (s as NSString).substring(with: m.range(at: i))
}

private func notification(_ m: JSON, _ accountId: String) -> ZenTaoNotification? {
    let id = (str(m["id"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let html = str(m["data"]) ?? ""
    if id.isEmpty || html.isEmpty { return nil }
    let ns = html as NSString
    let anchor = anchorRegex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length))
    let summary = plainText(anchor == nil ? html : ns.substring(to: anchor!.range.location))
    let url = group(anchor, 1, in: html).map(decodeHtmlEntities)
    let linkText = group(anchor, 2, in: html).map(plainText)
    let ref = linkText.flatMap { t in refRegex.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)).map { ($0, t) } }
    var view: (NSTextCheckingResult, String)?
    if let url {
        let range = NSRange(location: 0, length: (url as NSString).length)
        if let v = pathViewRegex.firstMatch(in: url, range: range) ?? queryViewRegex.firstMatch(in: url, range: range) { view = (v, url) }
    }
    return ZenTaoNotification(
        accountId: accountId, id: id, summary: summary.isEmpty ? (linkText ?? "") : summary,
        objectType: group(view?.0, 1, in: view?.1 ?? "")?.lowercased(),
        objectId: ref.flatMap { group($0.0, 1, in: $0.1) } ?? group(view?.0, 2, in: view?.1 ?? ""),
        objectTitle: ref.flatMap { group($0.0, 2, in: $0.1) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? linkText,
        url: url, read: str(m["status"]) == "read",
        createdAt: str(m["createdDate"]).flatMap(ZenTaoDayParser.parse))
}

private func plainText(_ html: String) -> String {
    decodeHtmlEntities(html.replacingRegex("<[^>]+>", with: " ")).replacingRegex(#"\s+"#, with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
