/// Ported from: lib/features/chat/presentation/widgets/chat_composer_toolbar.dart + chat_markdown_toolbar.dart
import CoreUI
import SwiftUI

/// A composer tool: a roomier icon button than `AppIconButton`'s, as the composer's controls are the chat's most used.
struct ComposerToolButton: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let systemImage: String
    let help: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: theme.sizes.icon18))
                .foregroundStyle(selected ? theme.colors.accent : theme.colors.tx2)
                .frame(width: theme.sizes.control36, height: theme.sizes.control36)
                .background(selected ? theme.colors.sel : hovering ? theme.colors.panel2 : .clear, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The tool row above the input: send image, attach file, mention someone, emoji, send code, the AI tools (replies, rewrites,
/// the summary, sticker suggestions) and the Markdown toggle.
struct ComposerToolbar: View {
    @Environment(\.appTheme) private var theme
    let controller: ChatComposerController
    let state: ChatThreadState
    @State private var emojiOpen = false
    @State private var codeOpen = false

    var body: some View {
        HStack(spacing: theme.spacing.s2) {
            ComposerToolButton(systemImage: "photo", help: appString("chatSendImage", "Send images")) { controller.pickFiles(imagesOnly: true) }
            ComposerToolButton(systemImage: "paperclip", help: appString("chatAttach", "Attach files")) { controller.pickFiles(imagesOnly: false) }
            ComposerToolButton(systemImage: "at", help: appString("chatMention", "Mention someone")) {
                controller.mentions.start(in: controller.model)
                controller.model.requestFocus()
            }
            ComposerToolButton(systemImage: "face.smiling", help: appString("chatEmoji", "Emoji"), selected: emojiOpen) { emojiOpen.toggle() }
                .popover(isPresented: $emojiOpen, arrowEdge: .top) {
                    ChatEmojiPanel(state: state, onInsert: { controller.insert($0) }, onSent: { emojiOpen = false },
                                   onExpand: controller.threadRootId == nil ? { emojiOpen = false; state.sidePanel = .emoji } : nil,
                                   threadRootId: controller.threadRootId)
                        .frame(width: 360, height: 360)
                }
            ComposerToolButton(systemImage: "chevron.left.forwardslash.chevron.right", help: appString("chatSendCode", "Send code")) { codeOpen = true }
                .sheet(isPresented: $codeOpen) { SendCodeDialog(controller: controller) }
            if controller.offersAi { ChatAiComposeButton(controller: controller, state: state) }
            ComposerToolButton(systemImage: "textformat", help: controller.markdown
                               ? appString("chatMarkdownOn", "Markdown on — messages are sent formatted")
                               : appString("chatMarkdownOff", "Markdown off — messages are sent as plain text"),
                               selected: controller.markdown) { controller.markdownOverride = !controller.markdown }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.spacing.s12)
        .padding(.vertical, theme.spacing.s2)
    }
}

/// The Markdown formatting row under the input (shown while Markdown is on); each button applies to the selection.
struct MarkdownToolbar: View {
    @Environment(\.appTheme) private var theme
    let model: ChatComposerModel
    @Binding var expanded: Bool

    private static let groups: [[(MarkdownFormat, String, String, String)]] = [
        [(.bold, "bold", "chatFormatBold", "Bold"), (.italic, "italic", "chatFormatItalic", "Italic"),
         (.underline, "underline", "chatFormatUnderline", "Underline"), (.strikethrough, "strikethrough", "chatFormatStrikethrough", "Strikethrough"),
         (.code, "chevron.left.forwardslash.chevron.right", "chatFormatCode", "Code")],
        [(.heading, "textformat.size", "chatFormatHeading", "Heading"), (.quote, "text.quote", "chatFormatQuote", "Quote"),
         (.bulletList, "list.bullet", "chatFormatBulletList", "Bulleted list"), (.numberedList, "list.number", "chatFormatNumberedList", "Numbered list")],
        [(.indent, "increase.indent", "chatFormatIndent", "Indent"), (.outdent, "decrease.indent", "chatFormatOutdent", "Outdent"),
         (.clear, "eraser", "chatFormatClear", "Clear formatting")],
    ]

    var body: some View {
        HStack(spacing: theme.spacing.s2) {
            ForEach(Self.groups.indices, id: \.self) { g in
                if g > 0 { Rectangle().fill(theme.colors.line).frame(width: theme.borders.hairline, height: theme.sizes.icon16) }
                ForEach(Self.groups[g], id: \.0) { format, icon, key, fallback in
                    FormatButton(systemImage: icon, help: appString(key, fallback), selected: model.isOn(format)) { model.apply(format); model.requestFocus() }
                }
            }
            Spacer(minLength: 0)
            FormatButton(systemImage: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                         help: expanded ? appString("chatComposerCollapse", "Shrink the input") : appString("chatComposerExpand", "Expand the input"),
                         selected: expanded) { expanded.toggle(); model.requestFocus() }
        }
        .padding(.horizontal, theme.spacing.s12)
        .padding(.bottom, theme.spacing.s4)
    }
}

private struct FormatButton: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let systemImage: String
    let help: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: theme.sizes.icon14))
                .foregroundStyle(selected ? theme.colors.accent : theme.colors.tx2)
                .frame(width: theme.sizes.control32, height: theme.sizes.control32 - theme.spacing.s4)
                .background(selected ? theme.colors.sel : hovering ? theme.colors.panel2 : .clear, in: RoundedRectangle(cornerRadius: theme.radii.sm))
        }
        .buttonStyle(.plain).onHover { hovering = $0 }.help(help)
    }
}
