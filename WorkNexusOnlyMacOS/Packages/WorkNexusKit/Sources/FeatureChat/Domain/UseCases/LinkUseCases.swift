import CoreDomain
import Foundation

public enum LinkedItemKind: String, Hashable, Sendable { case issue, mergeRequest }

public struct MergeRequestLink: Hashable, Sendable {
    public var provider: ProviderType
    public var kind: LinkedItemKind
    public var host: String
    public var project: String
    public var number: String
}

/// Reads a GitLab merge request / issue or GitHub pull request / issue URL.
/// Ported from: lib/features/chat/domain/usecases/parse_merge_request_link.dart
public struct ParseMergeRequestLink: Sendable {
    public init() {}
    private static let gitlab = RX(#"^/(.+?)/-/(merge_requests|issues)/(\d+)(?:[/?#].*)?$"#)
    private static let github = RX(#"^/([^/]+/[^/]+)/(pull|issues)/(\d+)(?:[/?#].*)?$"#)

    public func callAsFunction(_ url: String) -> MergeRequestLink? {
        guard let comps = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              comps.scheme != nil, let rawHost = comps.host, !rawHost.isEmpty else { return nil }
        let host = rawHost.lowercased()
        let path = comps.percentEncodedPath
        let provider: ProviderType
        let m: RX.Match
        if let g = Self.gitlab.first(path) { provider = .gitlab; m = g }
        // `owner/repo/issues/N` is common on other forges, so an issue is GitHub's only on a GitHub host.
        else if let g = Self.github.first(path), g[2] == "pull" || Self.isGitHubHost(host) { provider = .github; m = g }
        else { return nil }
        return MergeRequestLink(provider: provider, kind: m[2] == "issues" ? .issue : .mergeRequest, host: host,
                                project: m[1] ?? "", number: m[3] ?? "")
    }

    static func isGitHubHost(_ h: String) -> Bool { h == "github.com" || h.hasPrefix("github.") }

    public static func same(_ a: MergeRequestLink, _ b: MergeRequestLink) -> Bool {
        a.provider == b.provider && (a.provider == .github || a.kind == b.kind) && a.host == b.host
            && a.number == b.number && a.project.lowercased() == b.project.lowercased()
    }
}

/// Ported from: lib/features/chat/domain/usecases/find_linked_merge_request.dart
public struct FindLinkedMergeRequest: Sendable {
    public init() {}
    public func callAsFunction(_ url: String, _ tickets: [Ticket]) -> Ticket? {
        let parse = ParseMergeRequestLink()
        guard let link = parse(url) else { return nil }
        return tickets.first { t in t.url.flatMap(parse.callAsFunction).map { ParseMergeRequestLink.same(link, $0) } ?? false }
    }
}

/// Ported from: lib/features/chat/domain/usecases/find_linked_ticket.dart
public struct FindLinkedTicket: Sendable {
    public init() {}
    private static let pathInfo = RX(#"^(bug|task|story)-view-(\d+)\b"#)

    public func callAsFunction(_ url: String, _ tickets: [Ticket]) -> Ticket? {
        guard let ref = Self.parse(url) else { return nil }
        return tickets.first { t in
            t.providerType == .zentao && t.externalKey == ref.id && t.externalType?.lowercased() == ref.type
                && URLComponents(string: t.url ?? "")?.host == ref.host
        }
    }

    public static func parse(_ url: String) -> (type: String, id: String, host: String)? {
        guard let c = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme != nil, let host = c.host, !host.isEmpty else { return nil }
        let segments = c.path.split(separator: "/").map(String.init)
        if let m = pathInfo.first(segments.last ?? ""), let t = m[1], let id = m[2] { return (t, id, host) }
        let q = Dictionary((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        guard q["f"] == "view", let type = q["m"], ["bug", "task", "story"].contains(type) else { return nil }
        guard let id = q["\(type)ID"] ?? q["id"], Int(id) != nil else { return nil }
        return (type, id, host)
    }
}

/// Ported from: lib/features/chat/domain/usecases/parse_sticker_pack_link.dart
public struct ParseStickerPackLink: Sendable {
    public init() {}
    private static let link = RX(#"^(?:https?://)?(?:www\.)?(?:t|telegram)\.me/addstickers/([A-Za-z0-9_]+)/?(?:\?.*)?$"#)
    private static let name = RX(#"^[A-Za-z0-9_]+$"#)
    /// The set's short name from a `t.me/addstickers/<name>` link or a bare name; nil when it is neither.
    public func callAsFunction(_ input: String) -> String? {
        let v = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = Self.link.first(v) { return m[1] }
        return Self.name.isFullMatch(v) ? v : nil
    }
}
