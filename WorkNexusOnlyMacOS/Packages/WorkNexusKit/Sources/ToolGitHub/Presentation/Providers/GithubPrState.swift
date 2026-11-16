import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/provider_detail_sections.dart (`humanizeMergeState`),
/// lib/core/widgets/merge_request_state_pill.dart, lib/tools/github/presentation/widgets/github_pr_row.dart (state).

/// GitHub raw merge states are snake_case tokens (`behind`, `clean`, `has_hooks`…); show them as readable words.
func humanizeMergeState(_ raw: String?) -> String {
    let words = (raw ?? "").replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    guard let first = words.first else { return "" }
    return first.uppercased() + words.dropFirst()
}

/// Whether GitHub says the PR's branch is behind its base (the fix is "Update branch"; there is no API rebase).
func githubNeedsBranchUpdate(_ entity: GitHubItemEntity) -> Bool { (entity.mergeableState ?? "").lowercased() == "behind" }

/// Where a pull request / issue stands, read from the raw `providerStatus` and the entity's flags.
enum GithubItemState {
    case draft, open, merged, closed

    static func of(_ t: Ticket) -> GithubItemState {
        if case .githubItem(let g)? = t.providerEntity {
            if g.draft == true { return .draft }
            if g.merged == true { return .merged }
        }
        switch t.providerStatus.lowercased() {
        case "merged": return .merged
        case "closed": return .closed
        case "draft": return .draft
        default: return t.status == .done ? .closed : .open
        }
    }

    /// Still accepting changes (open or draft).
    var isActive: Bool { self == .open || self == .draft }

    var label: String {
        switch self {
        case .draft: appString("githubColDraft", "Draft")
        case .open: appString("githubColOpen", "Open")
        case .merged: appString("githubColMerged", "Merged")
        case .closed: appString("githubColClosed", "Closed")
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

/// A PR state chip (Open / Draft / Merged / Closed), colour-coded, with that state's glyph.
struct GithubStatePill: View {
    @Environment(\.appTheme) private var theme
    let state: GithubItemState
    var body: some View {
        let tint = state.color(theme.colors)
        HStack(spacing: theme.spacing.s4) {
            Image(systemName: state.systemImage).font(.system(size: theme.sizes.icon12))
            Text(state.label).font(theme.typography.label)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s4)
        .background(tint.opacity(0.16), in: Capsule())
    }
}
