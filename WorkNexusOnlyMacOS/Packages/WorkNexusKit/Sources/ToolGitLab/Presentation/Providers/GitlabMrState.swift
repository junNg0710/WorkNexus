import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/util/gitlab_mr_phase.dart, lib/core/widgets/merge_request_state_pill.dart,
/// lib/shared/detail/presentation/widgets/provider_detail_sections.dart (`humanizeMergeState`).

/// Where a GitLab merge request stands — read once from its raw status, so the header menu, the widgets and the
/// overview all agree.
enum GitlabMrPhase {
    case draft, open, merged, closed

    /// Still accepting changes (draft or ready for review).
    var isActive: Bool { self == .draft || self == .open }

    static func of(_ t: Ticket, _ entity: GitLabItemEntity) -> GitlabMrPhase {
        switch t.providerStatus.lowercased() {
        case "merged": .merged
        case "closed": .closed
        case "draft": .draft
        default: entity.draft == true ? .draft : .open
        }
    }

    var label: String {
        switch self {
        case .draft: appString("gitlabColDraft", "Draft")
        case .open: appString("gitlabColOpen", "Open")
        case .merged: appString("gitlabColMerged", "Merged")
        case .closed: appString("gitlabColClosed", "Closed")
        }
    }

    func color(_ p: AppPalette) -> Color {
        switch self { case .draft: p.amber; case .open: p.green; case .merged: p.violet; case .closed: p.tx3 }
    }

    var systemImage: String {
        switch self {
        case .merged: "arrow.triangle.merge"
        case .closed: "xmark.circle"
        case .draft: "circle.dashed"
        case .open: "arrow.triangle.pull"
        }
    }
}

/// Whether GitLab will refuse the merge until the source branch is rebased: its own `need_rebase` status, or — on
/// fast-forward / semi-linear projects, where that status can still read `mergeable` — any commits behind target.
func gitlabMrNeedsRebase(_ entity: GitLabItemEntity) -> Bool {
    entity.mergeStatus == "need_rebase" || (entity.commitsBehind ?? 0) > 0
}

/// GitLab raw merge states are snake_case tokens (`need_rebase`, `ci_still_running`…); show them as readable words.
func humanizeMergeState(_ raw: String?) -> String {
    let words = (raw ?? "").replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    guard let first = words.first else { return "" }
    return first.uppercased() + words.dropFirst()
}

/// The state of a row of the merge-request table (Dart `GitLabMrTableRow`): Draft, Merged / Closed, In review or Open.
func gitlabMrTableState(_ t: Ticket, palette c: AppPalette) -> (label: String, color: Color) {
    var entity: GitLabItemEntity?
    if case .gitlabItem(let g)? = t.providerEntity { entity = g }
    if entity?.draft == true { return (appString("draft", "Draft"), c.tx3) }
    if t.status == .done {
        return t.providerStatus.lowercased() == "merged" ? (appString("viewMerged", "Merged"), c.violet) : (appString("viewClosed", "Closed"), c.red)
    }
    if entity?.reviewers.isEmpty == false { return (appString("inReview", "In review"), c.amber) }
    return (appString("viewOpen", "Open"), c.green)
}

/// A merge-request state chip (Open / Draft / Merged / Closed), colour-coded, with that state's glyph.
struct GitlabStatePill: View {
    @Environment(\.appTheme) private var theme
    let phase: GitlabMrPhase
    var body: some View {
        let tint = phase.color(theme.colors)
        HStack(spacing: theme.spacing.s4) {
            Image(systemName: phase.systemImage).font(.system(size: theme.sizes.icon12))
            Text(phase.label).font(theme.typography.label)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s4)
        .background(tint.opacity(0.16), in: Capsule())
    }
}
