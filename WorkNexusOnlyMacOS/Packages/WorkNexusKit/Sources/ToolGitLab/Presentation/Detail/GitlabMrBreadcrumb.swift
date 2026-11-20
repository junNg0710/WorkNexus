import CoreUI
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/detail/gitlab_mr_breadcrumb.dart
/// The repository an MR belongs to, above its title as on GitLab: "group / project › !42". The path opens the project in
/// the browser.
struct GitlabMrBreadcrumb: View {
    @Environment(\.appTheme) private var theme
    @State private var hovered = false
    /// `group/sub/project`.
    let projectPath: String
    /// The MR's iid, shown as `!42`.
    let reference: String
    /// The MR's web URL; the project's is its prefix before `/-/`.
    var mrUrl: String?

    /// `https://host/group/web/-/merge_requests/42` → `https://host/group/web`.
    static func projectURL(_ mrUrl: String?) -> String? {
        guard let mrUrl, let cut = mrUrl.range(of: "/-/"), cut.lowerBound > mrUrl.startIndex else { return nil }
        return String(mrUrl[..<cut.lowerBound])
    }

    var body: some View {
        let c = theme.colors
        let label = projectPath.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " / ")
        HStack(spacing: theme.spacing.s6) {
            Image(systemName: "folder").font(.system(size: theme.sizes.icon14)).foregroundStyle(c.tx3)
            if let url = Self.projectURL(mrUrl) {
                Text(label).font(theme.typography.paragraph).foregroundStyle(c.tx2).underline(hovered, color: c.tx2).lineLimit(1)
                    .onHover { hovered = $0 }.onTapGesture { openLinkExternally(url, inApp: false) }
                    .pointerStyle(.link).help(appString("mrOpenProject", "Open the project in the browser"))
            } else {
                Text(label).font(theme.typography.paragraph).foregroundStyle(c.tx2).lineLimit(1)
            }
            Image(systemName: "chevron.right").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.tx3)
            Text(verbatim: "!\(reference)").font(theme.typography.paragraph).foregroundStyle(c.tx2)
        }
    }
}
