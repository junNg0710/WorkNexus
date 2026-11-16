import SwiftUI

/// Ported from: lib/core/widgets/app_expandable_card.dart
/// A settings card that folds away: an icon, a title and a one-line summary of what is in force, opening on a click into its
/// sections (usually `AppExpandableCardSection`s, split by hairlines).
public struct AppExpandableCard<Sections: View>: View {
    @Environment(\.appTheme) private var theme
    @State private var expanded: Bool
    @State private var hovering = false
    let icon: String
    let title: String
    let summary: String
    let sections: Sections

    public init(icon: String, title: String, summary: String, initiallyExpanded: Bool = false, @ViewBuilder sections: () -> Sections) {
        self.icon = icon; self.title = title; self.summary = summary; self.sections = sections()
        _expanded = State(initialValue: initiallyExpanded)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: theme.motion.base)) { expanded.toggle() }
            } label: {
                HStack(spacing: theme.spacing.s14) {
                    Image(systemName: icon).font(.system(size: theme.sizes.icon24)).foregroundStyle(theme.colors.accent)
                    VStack(alignment: .leading, spacing: theme.spacing.s4) {
                        Text(title).font(theme.typography.titleSm).foregroundStyle(theme.colors.tx)
                        Text(summary).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.tx3)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(theme.spacing.s20).frame(maxWidth: .infinity, alignment: .leading)
                .background(hovering ? theme.colors.tx.opacity(0.04) : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).onHover { hovering = $0 }
            if expanded {
                VStack(alignment: .leading, spacing: 0) { sections }.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.card, in: RoundedRectangle(cornerRadius: theme.radii.lg))
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}

/// A titled block inside an `AppExpandableCard`: `trailing` sits beside the title (a short control), `content` below it (a form,
/// a list).
public struct AppExpandableCardSection<Trailing: View, Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let hint: String
    let trailing: Trailing
    let content: Content

    public init(title: String, hint: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title; self.hint = hint; self.trailing = trailing(); self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline)
            VStack(alignment: .leading, spacing: theme.spacing.s4) {
                HStack(spacing: theme.spacing.s12) {
                    Text(title).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).frame(maxWidth: .infinity, alignment: .leading)
                    trailing
                }
                Text(hint).font(theme.typography.meta).foregroundStyle(theme.colors.tx3).fixedSize(horizontal: false, vertical: true)
                if Content.self != EmptyView.self {
                    content.padding(.top, theme.spacing.s10)
                }
            }
            .padding(theme.spacing.s20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

public extension AppExpandableCardSection where Content == EmptyView {
    /// A section that is only a title, a hint and a control.
    init(title: String, hint: String, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, hint: hint, trailing: trailing, content: { EmptyView() })
    }
}

public extension AppExpandableCardSection where Trailing == EmptyView {
    /// A section that is a title, a hint and a body.
    init(title: String, hint: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, hint: hint, trailing: { EmptyView() }, content: content)
    }
}
