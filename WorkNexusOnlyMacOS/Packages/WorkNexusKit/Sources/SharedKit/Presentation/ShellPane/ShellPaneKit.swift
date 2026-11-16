import CoreTools
import CoreUI
import SwiftUI

private struct PaneCollapseKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
public extension EnvironmentValues {
    /// Folds the pane the shell hosts into its strip (`ToolModule.paneCollapsible`); nil when the pane cannot fold.
    /// `ToolPaneScaffold` draws the collapse button in its header while this is set.
    var paneCollapse: (() -> Void)? {
        get { self[PaneCollapseKey.self] }
        set { self[PaneCollapseKey.self] = newValue }
    }
}

public extension View {
    /// Lets the pane under this view fold itself (`\.paneCollapse`).
    func paneCollapse(_ action: @escaping () -> Void) -> some View { environment(\.paneCollapse, action) }
}

/// Ported from: shared/shell_pane (ToolPaneScaffold, FeatureTabStrip, ScopeFilterField, ScopeRow).
public struct ToolPaneScaffold<Content: View>: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.paneCollapse) private var collapse
    let title: String; let subtitle: String?; let content: Content
    public init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.content = content()
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: theme.spacing.s2) {
                    Text(title.uppercased()).font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
                    if let subtitle { Text(subtitle).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx) }
                }
                Spacer(minLength: 0)
                if let collapse { AppIconButton(AppPanelIcon.collapse(.leading), help: appString("paneCollapse", "Collapse sidebar"), action: collapse) }
            }
            .padding(theme.spacing.s12)
            Divider().overlay(theme.colors.line)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

public struct FeatureTabStrip: View {
    @Environment(\.appTheme) private var theme
    let sections: [ToolSection]; let selected: SectionID; let onSelect: (SectionID) -> Void
    public init(sections: [ToolSection], selected: SectionID, onSelect: @escaping (SectionID) -> Void) {
        self.sections = sections; self.selected = selected; self.onSelect = onSelect
    }
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.s4) {
                // A section that is not built yet stays in the strip, dimmed: it opens a "coming soon" view (`ComingSoonView`).
                ForEach(sections) { s in
                    Button { onSelect(s.id) } label: {
                        HStack(spacing: theme.spacing.s6) {
                            Image(systemName: s.systemImage).font(.system(size: theme.sizes.icon14))
                            Text(LocalizedStringKey(s.label)).font(theme.typography.label)
                            if let unread = s.unreadCount?(), unread > 0 { UnreadBadge(count: unread) }
                        }
                        .padding(.horizontal, theme.spacing.s10).frame(height: theme.sizes.control32)
                        .foregroundStyle(s.id == selected ? theme.colors.accent : theme.colors.tx2)
                        .background(s.id == selected ? theme.colors.sel : .clear, in: RoundedRectangle(cornerRadius: theme.radii.md))
                        .opacity(s.available ? 1 : 0.5)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s6)
        }
    }
}

/// A filter field with a 150 ms debounce: typing updates `text` after the pause (clearing is immediate), and a change
/// of `text` from outside (a reset) is shown at once.
public struct ScopeFilterField: View {
    @Environment(\.appTheme) private var theme
    @Binding var text: String
    @State private var draft: String
    @State private var debounce = FilterDebounce()
    let prompt: String; let delay: Duration
    public init(text: Binding<String>, prompt: String, delay: Duration = FilterDebounce.defaultDelay) {
        _text = text; self.prompt = prompt; self.delay = delay; _draft = State(initialValue: text.wrappedValue)
    }
    public var body: some View {
        HStack(spacing: theme.spacing.s6) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.colors.tx3).font(.system(size: theme.sizes.icon14))
            TextField(prompt, text: $draft).textFieldStyle(.plain).font(theme.typography.body)
                .onChange(of: draft) { _, new in debounce.submit(new, delay: delay) { text = $0 } }
                .onChange(of: text) { _, new in if new != draft { debounce.cancel(); draft = new } }
        }
        .padding(.horizontal, theme.spacing.s10).frame(height: theme.sizes.control32)
        .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
        .padding(.horizontal, theme.spacing.s8)
    }
}

public struct ScopeRow: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let title: String; var systemImage: String; var selected: Bool; var indent: Int; var trailing: String?; let action: () -> Void
    public init(title: String, systemImage: String = "folder", selected: Bool = false, indent: Int = 0,
                trailing: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.selected = selected; self.indent = indent
        self.trailing = trailing; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.s8) {
                Image(systemName: systemImage).font(.system(size: theme.sizes.icon14)).frame(width: theme.sizes.icon16)
                Text(title).font(theme.typography.body).lineLimit(1)
                Spacer(minLength: 0)
                if let trailing { Text(trailing).font(theme.typography.caption).foregroundStyle(theme.colors.tx3) }
            }
            .padding(.leading, theme.spacing.s10 + CGFloat(indent) * theme.spacing.s14).padding(.trailing, theme.spacing.s10)
            .frame(height: theme.sizes.control32)
            .foregroundStyle(selected ? theme.colors.accent : theme.colors.tx)
            .background(selected ? theme.colors.sel : (hovering ? theme.colors.panel2 : .clear), in: RoundedRectangle(cornerRadius: theme.radii.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }.padding(.horizontal, theme.spacing.s6)
    }
}
