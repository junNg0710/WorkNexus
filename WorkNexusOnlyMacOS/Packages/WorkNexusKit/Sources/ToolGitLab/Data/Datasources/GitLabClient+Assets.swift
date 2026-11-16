import Foundation

/// Ported from: lib/tools/gitlab/data/datasources/gitlab_client.dart (assets section)
extension GitLabClient {
    /// Fetches raw bytes for an authenticated inline asset (e.g. an `/uploads/…` image embedded in a description).
    /// Only an image response is accepted (an HTML login page is never returned as an image); nil on any
    /// non-image response.
    ///
    /// A markdown upload renders as a project-web-relative link (`/uploads/<secret>/<file>`) that only a session
    /// cookie can read, so it is mapped to the Markdown uploads API (`/projects/:id/uploads/…`, GitLab 17.4+),
    /// which honours `PRIVATE-TOKEN`.
    func fetchBytes(_ url: String, projectPath: String? = nil, projectId: Int? = nil) async throws -> Data? {
        guard let resolved = resolveAsset(url, projectPath: projectPath, projectId: projectId) else { return nil }
        var req = URLRequest(url: resolved)
        authorize(&req)
        let res = try await transport.send(req, accept: { $0 < 500 })
        let type = (res.header("content-type") ?? "").lowercased()
        guard res.status == 200, !res.data.isEmpty, type.hasPrefix("image") else { return nil }
        return res.data
    }

    /// Resolves an inline-asset URL into an absolute URL (see `fetchBytes`). Absolute URLs are used as is.
    func resolveAsset(_ url: String, projectPath: String?, projectId: Int?) -> URL? {
        let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.union(.urlPathAllowed).union(CharacterSet(charactersIn: "%#"))) ?? url
        if let parsed = URL(string: url) ?? URL(string: encoded), parsed.scheme != nil { return parsed }
        let path = URLComponents(string: encoded)?.percentEncodedPath ?? encoded
        let segments = path.split(separator: "/").map(String.init)
        let project: String? = {
            if let projectId, projectId > 0 { return "\(projectId)" }
            if let projectPath, !projectPath.isEmpty { return projectPath }
            return nil
        }()
        if let project, segments.count >= 3, segments[0] == "uploads" {
            // The project ref is one percent-encoded segment (`group/web` → `group%2Fweb`); base sub-paths are kept.
            let rest = segments.dropFirst().joined(separator: "/")
            return URL(string: "\(baseUrl)/api/v4/projects/\(Self.encodeSegment(project))/uploads/\(rest)")
        }
        guard let base = URL(string: baseUrl + "/") else { return nil }
        return URL(string: encoded, relativeTo: base)?.absoluteURL
    }

    /// Dart `Uri.encodeComponent`: everything but `A-Z a-z 0-9 - _ . ! ~ * ' ( )` is percent-encoded.
    static func encodeSegment(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")) ?? s
    }
}
