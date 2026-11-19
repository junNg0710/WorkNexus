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
        let busy = commands.busy != nil
        AppMenuButton(help: appString("more", "More"), items: menuItems) {
            Image(systemName: "ellipsis").font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.tx2)
                .frame(width: theme.sizes.control32, height: theme.sizes.control32).contentShape(Rectangle())
        }
        .fixedSize().disabled(busy)
    }

    /// The menu, read when the button is pressed (the MR's phase may have moved on since the header was drawn).
    private func menuItems() -> [AppNativeMenu.Item] {
        let phase = GitlabMrPhase.of(ticket, entity)
        let path = entity.projectPath ?? ""
        var out: [AppNativeMenu.Item] = []
        if phase.isActive {
            if phase == .draft {
                out.append(.init(appString("markAsReady", "Mark as ready"), icon: "checkmark.circle") { commands.setDraft(false) })
            } else {
                out.append(.init(appString("markAsDraft", "Mark as draft"), icon: "circle.dashed") { commands.setDraft(true) })
            }
        }
        if !path.isEmpty {
            out.append(.init(appString("copyReference", "Copy reference"), icon: "doc.on.doc") { copy("\(path)!\(ticket.externalKey)") })
        }
        if phase.isActive {
            out.append(.init(appString("closeMergeRequest", "Close merge request"), icon: "xmark.circle", destructive: true, dividerBefore: true,
                             action: commands.close))
        }
        if phase == .closed {
            out.append(.init(appString("reopenMergeRequest", "Reopen merge request"), icon: "arrow.counterclockwise", dividerBefore: true,
                             action: commands.reopen))
        }
        return out
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        toasts?.show(appString("referenceCopied", "Reference copied"))
    }
}
