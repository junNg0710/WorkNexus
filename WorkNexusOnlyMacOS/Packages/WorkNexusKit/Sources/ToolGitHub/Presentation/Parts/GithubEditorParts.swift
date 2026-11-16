import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/metadata_editor_parts.dart
/// The pieces of a metadata editor popover (assignee / reviewers): search box, option row, save footer, message.

/// The search box at the top of an editor; it takes focus as the popover opens so typing filters straight away.
struct GithubEditorSearchField: View {
    @Environment(\.appTheme) private var theme
    @Binding var text: String
    let hint: String
    var body: some View {
        AppSearchField(text: $text, hint: hint, autofocus: true).padding(theme.spacing.s8)
    }
}

/// One selectable row: a check column, an optional leading view, a title and a muted subtitle.
struct GithubEditorOptionTile: View {
    @Environment(\.appTheme) private var theme
    let title: String; var subtitle: String?; let selected: Bool; var leading: AnyView?; let onTap: () -> Void

    var body: some View {
        let c = theme.colors
        HoverSurface(onTap: onTap, cornerRadius: 0) {
            HStack(spacing: theme.spacing.s8) {
                Image(systemName: "checkmark").font(.system(size: theme.sizes.icon14)).foregroundStyle(c.accent)
                    .opacity(selected ? 1 : 0).frame(width: theme.sizes.icon16)
                if let leading { leading }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(theme.typography.body).foregroundStyle(c.tx).lineLimit(1)
                    if let subtitle { Text(subtitle).font(theme.typography.meta).foregroundStyle(c.tx3).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, theme.spacing.s14).padding(.vertical, theme.spacing.s8)
        }
    }
}

/// The footer of an editor: the error (if any) and the Save button (`onSave == nil` disables it).
struct GithubEditorFooter: View {
    @Environment(\.appTheme) private var theme
    let busy: Bool; var error: String?; let onSave: (() -> Void)?

    var body: some View {
        HStack(spacing: theme.spacing.s8) {
            if let error { Text(error).font(theme.typography.meta).foregroundStyle(theme.colors.red).lineLimit(2) }
            Spacer(minLength: 0)
            if busy { ProgressView().controlSize(.small) }
            AppButton(appString("save", "Save"), kind: .primary) { onSave?() }.disabled(busy || onSave == nil)
        }
        .padding(theme.spacing.s8)
        .overlay(alignment: .top) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
    }
}

struct GithubEditorMessage: View {
    @Environment(\.appTheme) private var theme
    let message: String
    var body: some View {
        Text(message).font(theme.typography.body).foregroundStyle(theme.colors.tx3).padding(theme.spacing.s24)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
