import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/item_description.dart
/// The rendered item body of the two-pane detail: the description Markdown (selectable, images through the account's
/// authenticated loader) or a muted placeholder when there is none.
struct GithubItemDescription: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    let service: GitHubPrService

    var body: some View {
        if ticket.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(appString("noDescription", "No description provided.")).font(theme.typography.body).foregroundStyle(theme.colors.tx3)
        } else {
            let t = ticket, s = service
            MarkdownText(ticket.body, fontSize: 15, height: 1.6,
                         images: BodyImageHooks(loader: { url in await s.fetchTicketImage(t, url: url) },
                                                fallbackUrl: { providerImageWebUrl(providerType: .github, baseUrl: nil, projectPath: nil, rawUrl: $0) },
                                                onOpenImage: { url in _ = await MainActor.run { openExternally(url) } }))
                .textSelection(.enabled)
        }
    }
}
