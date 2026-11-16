import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/{detail_scroll_body,detail_region_card,section_label,detail_section_title}.dart
/// The scrolling body of a detail tab: the content card, the activity card, and the metadata sidebar — side by side
/// in the two-pane layout, stacked in a centred 768pt column in the tabbed one.
public struct DetailScrollBody<Content: View, Sidebar: View, Activity: View>: View {
    @Environment(\.appTheme) private var theme
    let layout: DetailLayout; let content: Content; let sidebar: Sidebar?; let activity: Activity?
    public static var docMaxWidth: CGFloat { 768 }
    public static var metaPaneWidth: CGFloat { 320 }

    public init(layout: DetailLayout, @ViewBuilder content: () -> Content, @ViewBuilder sidebar: () -> Sidebar,
                @ViewBuilder activity: () -> Activity) {
        self.layout = layout; self.content = content(); self.sidebar = sidebar(); self.activity = activity()
    }

    fileprivate init(layout: DetailLayout, content: Content) {
        self.layout = layout; self.content = content; sidebar = nil; activity = nil
    }

    public var body: some View {
        let s = theme.spacing
        ScrollView {
            Group {
                if layout == .twoPane {
                    HStack(alignment: .top, spacing: s.s14) {
                        VStack(alignment: .leading, spacing: s.s14) {
                            DetailRegionCard { content }
                            if let activity { DetailRegionCard { activity } }
                        }
                        .frame(maxWidth: .infinity)
                        if let sidebar { sidebar.frame(width: Self.metaPaneWidth) }
                    }
                } else {
                    VStack(alignment: .leading, spacing: s.s14) {
                        DetailRegionCard { content }
                        if let sidebar { sidebar }
                        if let activity { DetailRegionCard { activity } }
                    }
                    .frame(maxWidth: Self.docMaxWidth)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(EdgeInsets(top: s.s20, leading: s.s20, bottom: s.s40, trailing: s.s20))
        }
        .background(theme.colors.bg)
    }
}

public extension DetailScrollBody where Sidebar == EmptyView, Activity == EmptyView {
    init(layout: DetailLayout, @ViewBuilder content: () -> Content) { self.init(layout: layout, content: content()) }
}

/// A bordered card region in the detail body.
public struct DetailRegionCard<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let padding: CGFloat?; let content: Content
    public init(padding: CGFloat? = nil, @ViewBuilder content: () -> Content) { self.padding = padding; self.content = content() }
    public var body: some View {
        content.padding(padding ?? theme.spacing.s20).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.card, in: RoundedRectangle(cornerRadius: theme.radii.lg))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}

/// Upper-case caption above a group of fields.
public struct SectionLabel: View {
    @Environment(\.appTheme) private var theme
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased()).font(theme.typography.label).foregroundStyle(theme.colors.tx3)
    }
}

/// A section heading with an optional count badge.
public struct DetailSectionTitle: View {
    @Environment(\.appTheme) private var theme
    let title: String; let count: Int?
    public init(_ title: String, count: Int? = nil) { self.title = title; self.count = count }
    public var body: some View {
        HStack(spacing: theme.spacing.s6) {
            Text(title).font(theme.typography.titleSm).foregroundStyle(theme.colors.tx).lineLimit(1)
            if let count, count > 0 { AppCountBadge(count) }
            Spacer(minLength: 0)
        }
        .padding(.bottom, theme.spacing.s8)
    }
}
