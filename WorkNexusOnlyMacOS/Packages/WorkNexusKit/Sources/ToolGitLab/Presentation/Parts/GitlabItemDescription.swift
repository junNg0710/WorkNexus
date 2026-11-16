import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/item_description.dart
/// The rendered item body of the two-pane detail: the description Markdown (selectable, images through the account's
/// authenticated loader — relative `/uploads` paths resolve against the project) or a muted placeholder when none.
struct GitlabItemDescription: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    let service: GitLabMrService
    var baseUrl: String?

    private var projectPath: String? { if case .gitlabItem(let g)? = ticket.providerEntity { g.projectPath } else { nil } }

    var body: some View {
        if ticket.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(appString("noDescription", "No description provided.")).font(theme.typography.body).foregroundStyle(theme.colors.tx3)
        } else {
            let t = ticket, s = service, base = baseUrl
            let path = projectPath
            MarkdownText(ticket.body, fontSize: 15, height: 1.6,
                         images: BodyImageHooks(loader: { url in await s.fetchTicketImage(t, url: url) },
                                                fallbackUrl: { providerImageWebUrl(providerType: .gitlab, baseUrl: base, projectPath: path, rawUrl: $0) },
                                                onOpenImage: { url in _ = await MainActor.run { openExternally(url) } }),
                         underlineLinksOnHover: true)
                .textSelection(.enabled)
        }
    }
}
