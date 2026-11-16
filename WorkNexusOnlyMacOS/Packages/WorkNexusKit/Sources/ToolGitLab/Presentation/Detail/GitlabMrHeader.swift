import AppKit
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/detail/gitlab_mr_header.dart
/// The two-pane MR header, laid out like GitLab's: the project breadcrumb, title and panel-level actions (refresh / link /
/// edit / close-panel / the "⋮" menu), then the metadata line — status pill, "**author** requested to merge `source` into
/// `target`" with a copy button per branch, and the opened-at time. The tab strip's hairline closes the header.
struct GitlabMrHeader: View {
    @Environment(\.appTheme) private var theme
    let nav: AppNavController
    let ticket: Ticket
    let entity: GitLabItemEntity
    let dateFormat: String
    let commands: GitlabMrCommands
    let onClose: () -> Void
    let onSync: () -> Void

    private enum Slot { case author, branch, text }

    /// "{author} requested to merge {source} into {target}" cut into runs, so the author can be set in bold and each
    /// branch as a ref while translators keep control of the word order.
    private var sentence: [(Slot, String)] {
        let author = entity.author ?? "", source = entity.sourceBranch ?? "", target = entity.targetBranch ?? ""
        if source.isEmpty || target.isEmpty {
            return author.isEmpty ? [] : [(.text, appFormat("mrRequestedToMerge", "%1$@ requested to merge", author))]
        }
        return templateRuns(slots: 3) { appFormat("mrRequestedToMergeInto", "%1$@ requested to merge %2$@ into %3$@", $0[0], $0[1], $0[2]) }
            .compactMap { run in
                switch run.slot {
                case 0: author.isEmpty ? nil : (.author, author)
                case 1: (.branch, source)
                case 2: (.branch, target)
                default: run.text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : (.text, run.text.trimmingCharacters(in: .whitespaces))
                }
            }
    }

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            if let path = entity.projectPath, !path.isEmpty {
                GitlabMrBreadcrumb(projectPath: path, reference: ticket.externalKey, mrUrl: ticket.url)
            }
            HStack(alignment: .top, spacing: theme.spacing.s8) {
                GitlabBackButton(nav: nav)
                Text(ticket.title).font(theme.typography.display).foregroundStyle(c.tx).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                GitlabPanelHeaderActions(url: ticket.url, onSync: onSync, onClosePanel: onClose) {
                    GitlabMrMoreButton(ticket: ticket, entity: entity, commands: commands)
                }
            }
            FlowLayout(spacing: theme.spacing.s6, rowSpacing: theme.spacing.s6) {
                GitlabStatePill(phase: GitlabMrPhase.of(ticket, entity))
                ForEach(Array(sentence.enumerated()), id: \.offset) { _, run in
                    switch run.0 {
                    case .author: Text(run.1).font(theme.typography.bodyStrong).foregroundStyle(c.tx)
                    case .branch: GitlabBranchRef(branch: run.1)
                    case .text: Text(run.1).font(theme.typography.paragraph).foregroundStyle(c.tx2)
                    }
                }
                if ticket.createdAt != nil {
                    Text(formatWhen(ticket.createdAt, format: dateFormat)).font(theme.typography.paragraph).foregroundStyle(c.tx3)
                }
            }
        }
        .padding(EdgeInsets(top: theme.spacing.s20, leading: theme.spacing.s24, bottom: theme.spacing.s14, trailing: theme.spacing.s12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A branch name in GitLab's ref style — monospace on an accent tint — with a copy button beside it (a check mark for
/// two seconds as confirmation).
struct GitlabBranchRef: View {
    @Environment(\.appTheme) private var theme
    let branch: String
    @State private var copied = false

    var body: some View {
        let c = theme.colors
        HStack(spacing: theme.spacing.s2) {
            Text(branch).font(theme.typography.mono).foregroundStyle(c.accent).textSelection(.enabled)
                .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s2)
                .background(c.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: theme.radii.xs))
            AppIconButton(copied ? "checkmark" : "doc.on.doc", help: copied ? appString("linkCopied", "Copied!") : appString("copyBranchName", "Copy branch name")) {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(branch, forType: .string)
                copied = true
            }
            .scaleEffect(0.8).frame(width: theme.sizes.icon24, height: theme.sizes.icon24)
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { copied = false }
        }
    }
}
