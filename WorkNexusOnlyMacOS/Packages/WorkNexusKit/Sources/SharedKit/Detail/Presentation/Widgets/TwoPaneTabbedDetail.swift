import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/two_pane_tabbed_detail.dart
/// The merge-request / PR detail frame: header, a sync bar, Overview / Commits / Changed files tabs (lazy: a tab builds
/// when first opened); Overview is two columns (sections + sidebar) from 820pt, stacked below.
public struct TwoPaneTabbedDetail<Header: View, Sidebar: View, Commits: View, Changes: View>: View {
    @Environment(\.appTheme) private var theme
    let isSyncing: Bool; let overview: [AnyView]; let overviewCount: Int?; let changesCount: Int?
    let header: Header; let sidebar: Sidebar; let commits: Commits; let changes: Changes
    @State private var tab: PaneTab = .overview
    @State private var visited: Set<PaneTab> = [.overview]
    public static var twoPaneBreakpoint: CGFloat { 820 }

    enum PaneTab: Hashable { case overview, commits, changes }

    public init(isSyncing: Bool, overviewSections: [AnyView], overviewCount: Int? = nil, changesCount: Int? = nil,
                @ViewBuilder header: () -> Header, @ViewBuilder sidebar: () -> Sidebar,
                @ViewBuilder commits: () -> Commits, @ViewBuilder changes: () -> Changes) {
        self.isSyncing = isSyncing; self.overview = overviewSections; self.overviewCount = overviewCount; self.changesCount = changesCount
        self.header = header(); self.sidebar = sidebar(); self.commits = commits(); self.changes = changes()
    }

    public var body: some View {
        let s = theme.spacing
        VStack(spacing: 0) {
            header
            Group { if isSyncing { ProgressView().progressViewStyle(.linear).tint(theme.colors.accent) } else { Color.clear } }
                .frame(height: theme.borders.thick)
            DetailUnderlineTabs(labels: [(.overview, appString("overview", "Overview")), (.commits, appString("commits", "Commits")),
                                         (.changes, appString("changedFiles", "Changed files"))],
                                current: tab,
                                counts: [PaneTab.overview: overviewCount, .changes: changesCount].compactMapValues { $0 }) {
                tab = $0; visited.insert($0)
            }
            ZStack {
                if visited.contains(.overview) { OverviewBody(sections: overview, sidebar: AnyView(sidebar)).opacity(tab == .overview ? 1 : 0).allowsHitTesting(tab == .overview) }
                if visited.contains(.commits) { ScrollBody { commits }.opacity(tab == .commits ? 1 : 0).allowsHitTesting(tab == .commits) }
                if visited.contains(.changes) { ScrollBody { changes }.opacity(tab == .changes ? 1 : 0).allowsHitTesting(tab == .changes) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.colors.card)
        .padding(.top, s.s0)
    }
}

private struct ScrollBody<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            content.frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: theme.spacing.s20, leading: theme.spacing.s24, bottom: theme.spacing.s24, trailing: theme.spacing.s24))
        }
    }
}

private struct OverviewBody: View {
    @Environment(\.appTheme) private var theme
    let sections: [AnyView]; let sidebar: AnyView
    var body: some View {
        ViewThatFits(in: .horizontal) {
            ScrollBody {
                HStack(alignment: .top, spacing: theme.spacing.s24) {
                    VStack(alignment: .leading, spacing: theme.spacing.s14) { ForEach(Array(sections.enumerated()), id: \.offset) { $1 } }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    sidebar.frame(width: 288)
                }
            }
            .frame(minWidth: TwoPaneTabbedDetail<EmptyView, EmptyView, EmptyView, EmptyView>.twoPaneBreakpoint)
            ScrollBody {
                VStack(alignment: .leading, spacing: theme.spacing.s14) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { $1 }
                    sidebar
                }
            }
        }
    }
}
