import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/{unified_diff_view,commits_section,changed_files_section}.dart
/// A unified diff: added lines green, removed red, hunk headers in the accent, scrolling sideways.
public struct UnifiedDiffView: View {
    @Environment(\.appTheme) private var theme
    let diff: String
    public init(_ diff: String) { self.diff = diff }
    public var body: some View {
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in DiffLine(line: line) }
            }
            .padding(.vertical, theme.spacing.s6).frame(minWidth: 0, alignment: .leading)
        }
        .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.sm))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.sm).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        .padding(.top, theme.spacing.s6)
    }
}

private struct DiffLine: View {
    @Environment(\.appTheme) private var theme
    let line: String
    var body: some View {
        let c = theme.colors
        let add = line.hasPrefix("+") && !line.hasPrefix("+++"), del = line.hasPrefix("-") && !line.hasPrefix("---")
        let fg = add ? c.green : del ? c.red : line.hasPrefix("@@") ? c.accent : c.tx2
        Text(line.isEmpty ? " " : line).font(theme.typography.mono).foregroundStyle(fg).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, theme.spacing.s8).frame(maxWidth: .infinity, alignment: .leading)
            .background(add ? c.green.opacity(0.14) : del ? c.red.opacity(0.14) : .clear)
    }
}

/// Loads a list once (and again on retry), showing loading / error / empty states around it.
struct LoadedSection<Item: Sendable, Row: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String; let emptyTitle: String; let loader: () async -> Outcome<[Item]>; let row: ([Item]) -> Row
    @State private var state: Outcome<[Item]>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailSectionTitle(title, count: state?.value?.count)
            switch state {
            case nil: AppStateView(.loading)
            case .failure(let f)?: AppStateView(.error(f.message)) { state = nil; Task { state = await loader() } }
            case .success(let items)?:
                if items.isEmpty { AppStateView(.empty(emptyTitle)) } else { row(items) }
            }
        }
        .task { if state == nil { state = await loader() } }
    }
}

/// The commits of a merge request / PR; `loader` fetches them (the tool's adapter).
public struct CommitsSection: View {
    @Environment(\.appTheme) private var theme
    let loader: () async -> Outcome<[RepoCommit]>
    public init(loader: @escaping () async -> Outcome<[RepoCommit]>) { self.loader = loader }
    public var body: some View {
        LoadedSection(title: appString("commits", "Commits"), emptyTitle: appString("noCommits", "No commits"), loader: loader) { commits in
            VStack(alignment: .leading, spacing: theme.spacing.s8) {
                ForEach(commits) { commit in
                    let meta = [commit.author, commit.date.map { formatWhen($0) }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                    HStack(alignment: .top, spacing: theme.spacing.s8) {
                        Text(commit.shortSha).font(theme.typography.mono).foregroundStyle(theme.colors.accent)
                            .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s4)
                            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.sm))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(commit.title).font(theme.typography.body).foregroundStyle(theme.colors.tx)
                            if !meta.isEmpty { Text(meta).font(theme.typography.meta).foregroundStyle(theme.colors.tx3) }
                        }
                    }
                }
            }
        }
    }
}

/// The changed files of a merge request / PR, each expandable to its diff.
public struct ChangedFilesSection: View {
    @Environment(\.appTheme) private var theme
    let loader: () async -> Outcome<[RepoFileChange]>
    public init(loader: @escaping () async -> Outcome<[RepoFileChange]>) { self.loader = loader }
    public var body: some View {
        LoadedSection(title: appString("changedFiles", "Changed files"), emptyTitle: appString("noChangedFiles", "No changed files"), loader: loader) { files in
            VStack(alignment: .leading, spacing: theme.spacing.s4) { ForEach(files) { ChangedFileRow(file: $0) } }
        }
    }
}

private struct ChangedFileRow: View {
    @Environment(\.appTheme) private var theme
    let file: RepoFileChange
    @State private var open = false
    var body: some View {
        let c = theme.colors
        let hasDiff = !(file.diff ?? "").isEmpty
        let (glyph, color): (String, Color) = switch (file.status ?? "").lowercased() {
        case "added": ("A", c.green)
        case "deleted", "removed": ("D", c.red)
        case "renamed": ("R", c.violet)
        default: ("M", c.amber)
        }
        VStack(alignment: .leading, spacing: 0) {
            HoverSurface(onTap: hasDiff ? { open.toggle() } : nil, enabled: hasDiff, cornerRadius: theme.radii.sm) {
                HStack(spacing: theme.spacing.s8) {
                    Text(glyph).font(theme.typography.metaStrong).foregroundStyle(color)
                    Text(file.path).font(theme.typography.mono).foregroundStyle(c.tx).frame(maxWidth: .infinity, alignment: .leading)
                    if file.additions > 0 { Text("+\(file.additions)").font(theme.typography.metaStrong).foregroundStyle(c.green) }
                    if file.deletions > 0 { Text("−\(file.deletions)").font(theme.typography.metaStrong).foregroundStyle(c.red) }
                    if hasDiff { Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: theme.sizes.icon14)).foregroundStyle(c.tx3) }
                }
                .padding(.vertical, theme.spacing.s4)
            }
            if open, hasDiff, let diff = file.diff { UnifiedDiffView(diff) }
        }
    }
}
