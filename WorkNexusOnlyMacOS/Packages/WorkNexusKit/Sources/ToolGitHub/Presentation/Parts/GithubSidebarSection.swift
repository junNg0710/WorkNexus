import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/detail_sidebar_section.dart (+ `_overlay`)
/// A sidebar block: a bold title, an optional "Edit" action that opens the editor as a popover, then the content.
/// A hairline separates it from the block above.
struct GithubSidebarSection<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    var action: String?
    var editor: ((_ close: @escaping () -> Void) -> AnyView)?
    let content: Content
    @State private var open = false

    init(title: String, action: String? = nil, editor: ((_ close: @escaping () -> Void) -> AnyView)? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title; self.action = action; self.editor = editor; self.content = content()
    }

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            HStack {
                Text(title).font(theme.typography.bodyStrong).foregroundStyle(c.tx)
                Spacer(minLength: 0)
                if let action, let editor {
                    Button { open.toggle() } label: {
                        Text(action).font(theme.typography.meta).foregroundStyle(open ? c.accent : c.tx2)
                            .padding(.horizontal, theme.spacing.s4).padding(.vertical, theme.spacing.s4)
                    }
                    .buttonStyle(.plain).pointerStyle(.link)
                    .popover(isPresented: $open, arrowEdge: .bottom) { editor { open = false } }
                }
            }
            content
        }
        .padding(.vertical, theme.spacing.s14).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(c.line).frame(height: theme.borders.hairline) }
    }
}

/// A muted one-line text (empty-state of a sidebar block).
struct GithubMutedText: View {
    @Environment(\.appTheme) private var theme
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx3) }
}
