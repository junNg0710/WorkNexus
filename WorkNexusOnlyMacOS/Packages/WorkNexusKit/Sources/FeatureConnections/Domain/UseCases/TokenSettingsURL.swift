import Foundation

/// Ported from: lib/features/connections/presentation/{github,gitlab}_connection_dialog.dart (`_openTokenPage`,
/// `_tokenSettingsBase`). Where a user creates a Personal Access Token for the server typed in the form.
public enum TokenSettingsURL {
    /// GitHub's "new personal access token" page (classic, `repo` + `read:org` pre-selected). github.com /
    /// api.github.com → github.com; an Enterprise host stays as-is with any `/api/v3` suffix stripped.
    public static func github(_ raw: String) -> String {
        var u = raw.trimmingCharacters(in: .whitespaces)
        if u.isEmpty { return "https://github.com/settings/tokens/new?scopes=repo,read:org&description=WorkNexus" }
        if !u.hasPrefix("http") { u = "https://\(u)" }
        if u.hasSuffix("/") { u.removeLast() }
        if u.hasSuffix("/api/v3") { u.removeLast("/api/v3".count) }
        if URL(string: u)?.host?.lowercased() == "api.github.com" { u = "https://github.com" }
        return "\(u)/settings/tokens/new?scopes=repo,read:org&description=WorkNexus"
    }

    /// GitLab's PAT page. gitlab.com always runs the latest (`/-/user_settings/…`); a self-hosted host may be
    /// older so it gets the legacy `/-/profile/…`, which 16.x redirects to the modern path.
    public static func gitlab(_ raw: String) -> String {
        var u = raw.trimmingCharacters(in: .whitespaces)
        if u.isEmpty { u = "https://gitlab.com" }
        if !u.hasPrefix("http") { u = "https://\(u)" }
        if u.hasSuffix("/") { u.removeLast() }
        if u.hasSuffix("/api/v4") { u.removeLast("/api/v4".count) }
        let saas = URL(string: u)?.host == "gitlab.com"
        let path = saas ? "/-/user_settings/personal_access_tokens" : "/-/profile/personal_access_tokens"
        return "\(u)\(path)?name=WorkNexus&scopes=api"
    }
}
