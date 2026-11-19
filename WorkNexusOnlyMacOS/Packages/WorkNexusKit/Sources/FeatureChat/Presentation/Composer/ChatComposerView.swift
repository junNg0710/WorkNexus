/// Ported from: lib/features/chat/presentation/widgets/chat_composer.dart
import AppKit
import CoreUI
import SwiftUI

/// Message input: Enter sends, Shift+Enter adds a line; pasted, picked or dropped files (dropped on the input,
/// `chatFileDrop`) wait above it, and the next send takes them with the text typed (the input stays open) — or
/// text) until sent. A message picked with "reply" shows above the input and the next send answers it; in a reply thread
/// (`threadRootId`) sends answer its root unless another message is picked.
public struct ChatComposerView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    @Environment(\.chatSettings) private var settings
    let state: ChatThreadState
    let hint: String?
    @State private var controller: ChatComposerController
    @State private var inputHeight: CGFloat = 0
    /// The input holds a tall block of lines (Markdown mode's expand toggle) instead of growing with its text.
    @State private var expanded = false

    public init(state: ChatThreadState, threadRootId: Int? = nil, hint: String? = nil) {
        self.state = state; self.hint = hint
        _controller = State(initialValue: ChatComposerController(state: state, threadRootId: threadRootId))
    }

    public var body: some View {
        Group {
            if CanSendToChat()(state.chat, selfUserId: state.selfUserId, selfAccount: state.selfAccount) {
                composer
            } else {
                ChatReadOnlyBar(adminsOnly: state.chat.committers.trimmingCharacters(in: .whitespaces) == "$ADMINS")
            }
        }
        .onAppear { sync() }
        .onChange(of: settings) { _, _ in sync() }
        .onDisappear { controller.keepDraft(); controller.stopTyping() }
        .task(id: state.chatGid) { await controller.loadMembers() }
        .task(id: state.chatGid) { await controller.stickerSuggestions.load(services?.stickers) }
        .task(id: state.chatGid) {
            guard let repository = services?.chat else { return }
            await controller.stickerSuggestions.watchLatest(repository, accountId: state.accountId, chatGid: state.chatGid)
        }
    }

    private func sync() {
        controller.services = services
        controller.settings = settings
    }

    private var composer: some View {
        VStack(spacing: 0) {
            ComposerErrorLine(message: controller.error) { controller.error = nil }
            // The replies the AI suggested, when asked, and stickers for what is typed (or to answer with), over the tools.
            ChatReplySuggestionsBar(controller: controller)
            ChatStickerSuggestionsBar(controller: controller)
            ComposerToolbar(controller: controller, state: state)
            Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline)
            if let draft = state.replyDraft {
                ReplyDraftBanner(message: draft, state: state) { state.replyDraft = nil; controller.model.requestFocus() }
            }
            // Files dropped, pasted or picked wait above the input, which stays open: a message can go with them.
            if !state.stagedFiles.isEmpty {
                StagedFilesStrip(files: state.stagedFiles, onClear: controller.clearStaged, onRemove: controller.removeStaged)
            }
            ComposerInputRow(controller: controller, state: state, hint: hint, expanded: expanded, height: $inputHeight)
            if controller.markdown { MarkdownToolbar(model: controller.model, expanded: $expanded) }
        }
        .background(theme.colors.panel)
        .overlay(alignment: .top) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
        .onChange(of: controller.model.revision) { _, _ in controller.textChanged() }
        .onChange(of: controller.model.text) { _, _ in controller.keepDraft() }
        .onChange(of: state.pendingInsertion) { _, text in takeInsertion(text) }
        .onChange(of: state.replyDraft?.gid) { _, gid in if gid != nil { controller.model.requestFocus() } }
        // Files just added (dropped, pasted, picked): the caret goes to the input, to type what goes with them.
        .onChange(of: state.stagedFiles.count) { old, new in controller.keepDraft(); if new > old { controller.model.requestFocus() } }
        .onAppear { takeInsertion(state.pendingInsertion) }
    }

    private func takeInsertion(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        state.pendingInsertion = nil
        controller.insert(text)
    }
}

/// The input line: the text box with its @mention list above it, and the send (or like) button.
private struct ComposerInputRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatSettings) private var settings
    let controller: ChatComposerController
    let state: ChatThreadState
    let hint: String?
    let expanded: Bool
    @Binding var height: CGFloat

    private var model: ChatComposerModel { controller.model }
    private var fontSize: CGFloat { 14 * CGFloat(settings.textScale) }
    private var font: NSFont {
        theme.typography.family.isEmpty ? .systemFont(ofSize: fontSize) : (NSFont(name: theme.typography.family, size: fontSize) ?? .systemFont(ofSize: fontSize))
    }
    /// Grows with its text up to a few lines; expanded it holds 14 lines (Dart `_kExpandedLines`).
    private var boxHeight: CGFloat { expanded ? fontSize * 1.45 * 14 : min(max(height, theme.sizes.control36), theme.sizes.control36 * 4.5) }

    var body: some View {
        HStack(alignment: .bottom, spacing: theme.spacing.s10) {
            ZStack(alignment: .topLeading) {
                ChatComposerTextView(
                    model: model, font: font, textColor: NSColor(theme.colors.tx), accent: NSColor(theme.colors.accent),
                    revision: model.revision, focusTick: model.focusTick, resetUndoTick: model.resetUndoTick,
                    onKey: { controller.handle($0) }, onPaste: { controller.pasteAttachments() },
                    onChange: { controller.textChanged() }, contentHeight: $height)
                if model.text.isEmpty {
                    Text(hint ?? appString("chatComposerHint", "Message — Enter to send, Shift+Enter for a new line"))
                        .font(theme.typography.body).foregroundStyle(theme.colors.tx3)
                        .padding(.top, 6).allowsHitTesting(false).lineLimit(1)
                }
            }
            .frame(height: boxHeight)
            .padding(.horizontal, theme.spacing.s12)
            .background(theme.colors.card, in: RoundedRectangle(cornerRadius: theme.radii.lg))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
            .overlay(alignment: .top) {
                ChatMentionList(mentions: controller.mentions, state: state) { controller.pick($0) }
                    .alignmentGuide(.top) { $0[.bottom] }
                    .offset(y: -theme.spacing.s4)
            }
            if model.isBlank && state.stagedFiles.isEmpty {
                Button(action: controller.sendLike) { Text("👍").font(.system(size: 26)).frame(width: theme.sizes.control36, height: theme.sizes.control36) }
                    .buttonStyle(.plain).help(appString("chatSendLike", "Send a like"))
            } else {
                ComposerSendButton { controller.send() }
            }
        }
        .padding(EdgeInsets(top: theme.spacing.s8, leading: theme.spacing.s16, bottom: theme.spacing.s8, trailing: theme.spacing.s12))
    }
}

/// The last send failure, dismissible.
private struct ComposerErrorLine: View {
    @Environment(\.appTheme) private var theme
    let message: String?
    let onDismiss: () -> Void

    var body: some View {
        if let message {
            HStack(spacing: theme.spacing.s8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.colors.red)
                Text(message).font(theme.typography.meta).foregroundStyle(theme.colors.red).lineLimit(2)
                Spacer(minLength: 0)
                AppIconButton("xmark", help: appString("chatDismiss", "Dismiss"), action: onDismiss)
            }
            .padding(.horizontal, theme.spacing.s12)
            .background(theme.colors.red.opacity(0.08))
        }
    }
}
