import AppKit
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/detail/gitlab_mr_more_button.dart
/// The MR header's "⋮" menu, as on GitLab: Mark as ready / draft and Close while open, Reopen once closed, and Copy
/// reference (`group/project!42`).
struct GitlabMrMoreButton: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let ticket: Ticket
    let entity: GitLabItemEntity
    let commands: GitlabMrCommands

    var body: some View {
        let phase = GitlabMrPhase.of(ticket, entity)
        let path = entity.projectPath ?? ""
        let busy = commands.busy != nil
        Menu {
            if phase.isActive {
                if phase == .draft {
                    Button { commands.setDraft(false) } label: { Label(appString("markAsReady", "Mark as ready"), systemImage: "checkmark.circle") }
                } else {
                    Button { commands.setDraft(true) } label: { Label(appString("markAsDraft", "Mark as draft"), systemImage: "circle.dashed") }
                }
            }
            if !path.isEmpty {
                Button { copy("\(path)!\(ticket.externalKey)") } label: { Label(appString("copyReference", "Copy reference"), systemImage: "doc.on.doc") }
            }
            if phase.isActive {
                Divider()
                Button(role: .destructive, action: commands.close) { Label(appString("closeMergeRequest", "Close merge request"), systemImage: "xmark.circle") }
            }
            if phase == .closed {
                Divider()
                Button(action: commands.reopen) { Label(appString("reopenMergeRequest", "Reopen merge request"), systemImage: "arrow.counterclockwise") }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.tx2)
                .frame(width: theme.sizes.control32, height: theme.sizes.control32).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().disabled(busy).help(appString("more", "More"))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        toasts?.show(appString("referenceCopied", "Reference copied"))
    }
}
