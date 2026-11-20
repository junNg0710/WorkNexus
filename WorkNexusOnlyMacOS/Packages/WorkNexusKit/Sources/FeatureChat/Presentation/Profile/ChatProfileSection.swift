/// Ported from: lib/features/chat/presentation/widgets/{chat_profile_section,chat_profile_info_row}.dart
import AppKit
import CoreUI
import SwiftUI

/// A titled card of the profile popup ("WORK", "OPEN WORK 33"): an uppercase title with an optional count, the rows on a
/// raised panel.
struct ChatProfileSection<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String; var count: Int?
    @ViewBuilder let content: Content

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            HStack(spacing: theme.spacing.s8) {
                Text(title.uppercased()).font(theme.typography.label).tracking(0.6).foregroundStyle(c.tx2)
                if let count {
                    Text(verbatim: "\(count)").font(theme.typography.metaStrong).foregroundStyle(c.tx2)
                        .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s2)
                        .background(c.panel2, in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: theme.spacing.s4) { content }
                .padding(theme.spacing.s12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(c.card, in: RoundedRectangle(cornerRadius: theme.radii.lg))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(c.line, lineWidth: theme.borders.hairline))
        }
        .padding(.top, theme.spacing.s20)
    }
}

/// An icon in a tinted square, as every row of the popup leads with.
struct ChatProfileIcon: View {
    @Environment(\.appTheme) private var theme
    let systemImage: String; let tint: Color
    var body: some View {
        Image(systemName: systemImage).font(.system(size: theme.sizes.icon16)).foregroundStyle(tint)
            .frame(width: theme.sizes.control32, height: theme.sizes.control32)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: theme.radii.md))
    }
}

/// A label over its value; `copyable` adds a copy button that shows on hover.
struct ChatProfileInfoRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let icon: String; let label: String; let value: String
    var copyable = false
    @State private var hovering = false

    var body: some View {
        let c = theme.colors
        HStack(spacing: theme.spacing.s12) {
            ChatProfileIcon(systemImage: icon, tint: c.accent)
            VStack(alignment: .leading, spacing: theme.spacing.s2) {
                Text(label).font(theme.typography.meta).foregroundStyle(c.tx2)
                Text(value).font(theme.typography.bodyStrong).foregroundStyle(c.tx).textSelection(.enabled).lineLimit(2)
            }
            Spacer(minLength: 0)
            if copyable {
                AppIconButton("doc.on.doc", help: shellString("chatProfileCopy", "Copy {label}", ["label": label])) {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
                    toasts?.show(appString("chatCopied", "Copied"))
                }
                .opacity(hovering ? 1 : 0)
            }
        }
        .padding(.vertical, theme.spacing.s4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// A quiet one-line note inside a section (a failed fetch, "None").
struct ChatProfileNote: View {
    @Environment(\.appTheme) private var theme
    let text: String; var isError = false
    var body: some View {
        Text(text).font(theme.typography.body).foregroundStyle(isError ? theme.colors.red : theme.colors.tx3)
            .padding(.vertical, theme.spacing.s4)
    }
}

/// Placeholder rows while a section loads.
struct ChatProfileLoadingRows: View {
    @Environment(\.appTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            ForEach(0..<2, id: \.self) { i in SkeletonBox(width: [180, 130][i], height: theme.spacing.s14, radius: theme.radii.sm) }
        }
        .padding(.vertical, theme.spacing.s4)
    }
}

/// The first `shown` of `count` rows, then "+N more" that reveals the rest ("Show less" folds them back).
struct ChatProfileExpandable<Row: View>: View {
    @Environment(\.appTheme) private var theme
    let count: Int; var shown = 4
    @ViewBuilder let row: (Int) -> Row
    @State private var expanded = false

    var body: some View {
        let visible = expanded ? count : min(count, shown)
        ForEach(0..<visible, id: \.self) { row($0) }
        if count > shown {
            Button { withAnimation(.easeOut(duration: theme.motion.base)) { expanded.toggle() } } label: {
                HStack(spacing: theme.spacing.s4) {
                    Text(expanded ? shellString("chatProfileShowLess", "Show less")
                                  : shellString("chatProfileMore", "+{count} more", ["count": "\(count - shown)"]))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: theme.sizes.icon12))
                }
                .font(theme.typography.metaStrong).foregroundStyle(theme.colors.accent)
            }
            .buttonStyle(.plain).pointerStyle(.link).padding(.top, theme.spacing.s4)
        }
    }
}
