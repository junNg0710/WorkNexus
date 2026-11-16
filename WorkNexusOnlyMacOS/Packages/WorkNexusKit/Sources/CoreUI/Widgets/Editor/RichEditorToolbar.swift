import SwiftUI

/// Ported from: lib/core/widgets/editor_toolbar_buttons.dart, editor_color_button.dart, editor_link_button.dart,
/// editor_link_dialog.dart — the rich-text editor's toolbar: undo/redo, headings, bold / italic / underline /
/// strike / code, colours, lists, quote, code block, link, alignment, indent, image, clear formatting.
struct RichEditorToolbar: View {
    @Environment(\.appTheme) private var theme
    let commands: RichEditorCommands
    let canInsertImage: Bool
    let uploading: Bool
    let onPickImage: () -> Void
    @State private var linkOpen = false
    @State private var linkText = ""

    var body: some View {
        let i = commands.activeInline, b = commands.activeBlock
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.s2) {
                ToolbarButton("arrow.uturn.backward", help: appString("chatUndo", "Undo")) { commands.undo() }
                ToolbarButton("arrow.uturn.forward", help: appString("chatRedo", "Redo")) { commands.redo() }
                ToolbarDivider()
                Menu {
                    Button(appString("editorToolParagraph", "Paragraph")) { commands.setHeader(nil) }
                    ForEach(1...3, id: \.self) { n in Button("\(appString("chatFormatHeading", "Heading")) \(n)") { commands.setHeader(n) } }
                } label: { ToolbarGlyph("textformat.size", active: b.header != nil) }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).help(appString("chatFormatHeading", "Heading"))
                ToolbarButton("bold", active: i.bold, help: appString("chatFormatBold", "Bold")) { commands.toggle(\.bold) }
                ToolbarButton("italic", active: i.italic, help: appString("chatFormatItalic", "Italic")) { commands.toggle(\.italic) }
                ToolbarButton("underline", active: i.underline, help: appString("chatFormatUnderline", "Underline")) { commands.toggle(\.underline) }
                ToolbarButton("strikethrough", active: i.strike, help: appString("editorToolStrikethrough", "Strikethrough")) { commands.toggle(\.strike) }
                ToolbarButton("chevron.left.forwardslash.chevron.right", active: i.code, help: appString("editorToolCode", "Code")) { commands.toggle(\.code) }
                EditorColorButton(commands: commands, isBackground: false)
                EditorColorButton(commands: commands, isBackground: true)
                ToolbarDivider()
                ToolbarButton("list.number", active: b.list == .ordered, help: appString("editorToolNumberedList", "Numbered list")) { commands.toggleList(.ordered) }
                ToolbarButton("list.bullet", active: b.list == .bullet, help: appString("editorToolBulletedList", "Bulleted list")) { commands.toggleList(.bullet) }
                ToolbarButton("text.quote", active: b.blockquote, help: appString("chatFormatQuote", "Quote")) { commands.toggleBlockquote() }
                ToolbarButton("curlybraces", active: b.codeBlock, help: appString("editorToolCodeBlock", "Code block")) { commands.toggleCodeBlock() }
                ToolbarButton("link", active: i.link != nil, help: appString("editorInsertLink", "Link")) { linkText = i.link ?? ""; linkOpen = true }
                    .popover(isPresented: $linkOpen) { linkPopover }
                ToolbarDivider()
                ToolbarButton("text.alignleft", active: b.align == nil, help: appString("editorToolAlignLeft", "Align left")) { commands.setAlign(nil) }
                ToolbarButton("text.aligncenter", active: b.align == "center", help: appString("editorToolAlignCenter", "Align center")) { commands.setAlign("center") }
                ToolbarButton("text.alignright", active: b.align == "right", help: appString("editorToolAlignRight", "Align right")) { commands.setAlign("right") }
                ToolbarButton("decrease.indent", help: appString("editorToolOutdent", "Outdent")) { commands.indent(-1) }
                ToolbarButton("increase.indent", help: appString("chatFormatIndent", "Indent")) { commands.indent(1) }
                if canInsertImage {
                    ToolbarDivider()
                    if uploading { ProgressView().controlSize(.small).frame(width: theme.sizes.control32) }
                    else { ToolbarButton("photo", help: appString("editorToolImage", "Image"), action: onPickImage) }
                }
                ToolbarButton("eraser", help: appString("editorToolClearFormatting", "Clear formatting")) { commands.clearFormat() }
            }
            .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s4)
        }
        .background(theme.colors.panel)
    }

    /// The link dialog: an address, normalised with `normalizeLinkUrl` (a bare `example.com` gains `https://`).
    private var linkPopover: some View {
        let url = normalizeLinkUrl(linkText)
        return VStack(alignment: .leading, spacing: theme.spacing.s8) {
            TextField("https://", text: $linkText).textFieldStyle(.roundedBorder).frame(width: 260)
                .onSubmit { apply(url) }
            HStack {
                Button(appString("editorLinkRemove", "Remove link")) { commands.setLink(nil); linkOpen = false }
                Spacer()
                Button(appString("editorToolApply", "Apply")) { apply(url) }.disabled(url == nil).keyboardShortcut(.defaultAction)
            }
        }.padding(theme.spacing.s12)
    }

    private func apply(_ url: String?) {
        guard let url else { return }
        commands.setLink(url); linkOpen = false
    }
}

struct ToolbarGlyph: View {
    @Environment(\.appTheme) private var theme
    let symbol: String; let active: Bool
    init(_ symbol: String, active: Bool = false) { self.symbol = symbol; self.active = active }
    var body: some View {
        Image(systemName: symbol).font(.system(size: theme.sizes.icon14))
            .foregroundStyle(active ? theme.colors.accent : theme.colors.tx2)
            .frame(width: theme.sizes.control32 - theme.spacing.s4, height: theme.sizes.control32 - theme.spacing.s4)
            .background(active ? theme.colors.sel : .clear, in: RoundedRectangle(cornerRadius: theme.radii.sm))
            .contentShape(Rectangle())
    }
}

struct ToolbarButton: View {
    let symbol: String; let active: Bool; let help: String; let action: () -> Void
    init(_ symbol: String, active: Bool = false, help: String, action: @escaping () -> Void) {
        self.symbol = symbol; self.active = active; self.help = help; self.action = action
    }
    var body: some View { Button(action: action) { ToolbarGlyph(symbol, active: active) }.buttonStyle(.plain).help(help) }
}

private struct ToolbarDivider: View {
    @Environment(\.appTheme) private var theme
    var body: some View { Rectangle().fill(theme.colors.line).frame(width: theme.borders.hairline, height: theme.sizes.icon16).padding(.horizontal, theme.spacing.s4) }
}
