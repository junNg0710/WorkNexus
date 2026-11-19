/// Ported from: lib/features/chat/presentation/widgets/chat_composer.dart (`_ChatComposerState`) + chat_staged_files_provider.dart
import AppKit
import CoreDomain
import CoreUI
import Foundation
import Observation

/// Everything the composer view does besides drawing: the text model, @mention suggestions, typing signals, sending and staging.
@MainActor @Observable
final class ChatComposerController {
    let state: ChatThreadState
    let model = ChatComposerModel()
    let mentions = MentionAutocomplete()
    /// The ✨ AI help (reply ideas, rewrites) and the sticker strip: their state stays in the composer.
    let ai: ChatComposerAi
    let stickerSuggestions: ChatStickerSuggester
    /// The last failure to show above the input.
    var error: String?
    /// Member user ids of the open group (loaded lazily for the @mention list).
    private(set) var members: [Int] = []
    /// Local Markdown on/off; nil follows the app setting. (The host owns the persistent setting.)
    var markdownOverride: Bool?
    var threadRootId: Int?

    @ObservationIgnored var services: ChatServices?
    @ObservationIgnored var settings = ChatSettings()
    @ObservationIgnored private var typing: ChatTypingSender!

    init(state: ChatThreadState, threadRootId: Int? = nil) {
        self.state = state; self.threadRootId = threadRootId
        ai = ChatComposerAi(state: state)
        stickerSuggestions = ChatStickerSuggester(inThread: threadRootId != nil)
        typing = ChatTypingSender(
            send: { [weak self] chat, on in self?.sendTyping(chat, on) },
            chat: { [weak self] in self?.state.chat },
            enabled: { [weak self] in self?.settings.sendTypingStatus ?? false })
        // What was typed or staged here before the chat was left.
        if let kept = ChatComposerDrafts.shared.draft(draftKey) {
            model.restore(kept)
            if state.stagedFiles.isEmpty { state.stagedFiles = kept.staged }
        }
    }

    private var draftKey: String { ChatComposerDrafts.key(accountId: state.accountId, chatGid: state.chatGid, threadRootId: threadRootId) }

    /// Keeps the draft for this chat (called as it changes and when the composer goes away; sending empties it).
    func keepDraft() { ChatComposerDrafts.shared.save(model.draft(staged: state.stagedFiles), for: draftKey) }

    var markdown: Bool { markdownOverride ?? settings.sendMarkdown }

    var sender: ChatMessageSender? {
        guard let services else { return nil }
        var s = settings
        s.sendMarkdown = markdown
        return ChatMessageSender(state: state, services: services, settings: s, threadRootId: threadRootId)
    }

    // MARK: text changes

    /// After every edit or caret move: re-reads the @query and announces typing.
    func textChanged() {
        mentions.update(value: model.valueText, selection: model.selection)
        updateSuggestions()
        typing.changed(model.text)
        stickerSuggestions.typed(model.plainText)
    }

    /// The composer goes away: typing stops being announced, and what it asked the AI for is stopped.
    func stopTyping() { typing.stop(); ai.stop(); stickerSuggestions.stop() }

    private func sendTyping(_ chat: ChatConversation, _ on: Bool) {
        guard let repo = services?.chat else { return }
        Task { _ = await SendTypingStatus(repo)(chat: chat, typing: on) }
    }

    // MARK: mentions

    func loadMembers() async {
        guard let repo = services?.chat, state.chat.type != .one2one else { members = []; return }
        if case .success(let ids) = await repo.members(accountId: state.accountId, chatGid: state.chatGid) { members = ids }
        updateSuggestions()
    }

    func updateSuggestions() {
        guard let q = mentions.query else { mentions.visible = []; return }
        let chat = state.chat
        let group = chat.type != .one2one
        let ids: [Int] = chat.type == .one2one ? (chat.peerUserId.map { [$0] } ?? []) : members
        var all: [MentionCandidate] = group ? [MentionCandidate(userId: nil, name: "all", account: nil)] : []
        for id in ids where id != state.selfUserId {
            let u = state.users[id]
            let name = (u?.realname.isEmpty == false ? u?.realname : u?.account) ?? appString("chatUnknownUser", "User #{id}").replacingOccurrences(of: "{id}", with: "\(id)")
            all.append(MentionCandidate(userId: id, name: name, account: u?.account))
        }
        mentions.visible = MentionAutocomplete.filter(all, q)
    }

    func pick(_ candidate: MentionCandidate) {
        mentions.insert(into: model, candidate)
        model.requestFocus()
    }

    // MARK: keys

    func handle(_ key: ComposerKeyEvent) -> Bool {
        switch key {
        case .up: return mentions.handle(.up, model: model)
        case .down: return mentions.handle(.down, model: model)
        case .tab: return mentions.handle(.tab, model: model)
        case .escape:
            if mentions.handle(.escape, model: model) { return true }
            // The suggestion trays over the tools go first, as their close button does: AI replies, then stickers.
            if ai.replies != .idle { ai.clearReplies(); return true }
            if stickerSuggestions.offer(enabled: settings.stickerSuggestions) != nil { stickerSuggestions.close(); return true }
            if state.replyDraft != nil { state.replyDraft = nil; return true }
            if !state.stagedFiles.isEmpty { clearStaged(); return true }
            return false
        case .enter:
            if mentions.handle(.enter, model: model) { return true }
            send(); return true
        case .toggleMarkdown: markdownOverride = !markdown; return true
        }
    }

    // MARK: sending

    func report(_ result: Outcome<Void>) {
        if case .failure(let f) = result {
            error = appString("chatActionFailed", "Couldn't complete that: {reason}").replacingOccurrences(of: "{reason}", with: f.message)
        }
    }

    /// Sends the input: the files waiting above it first, then the text typed with them (a lone emoji goes large). Each
    /// goes as its own message, as xxd has no caption; a reply being written answers with the first.
    func send() {
        let files = state.stagedFiles
        guard !(model.isBlank && files.isEmpty), let sender else { return }
        let text: (message: String, plain: String?)? = model.isBlank ? nil : (model.messageText, model.hasMentions ? nil : model.plainText)
        state.stagedFiles = []
        model.clear(); mentions.reset()
        keepDraft()
        stickerSuggestions.cleared()
        typing.changed("")
        Task {
            if !files.isEmpty { report(await sender.files(files)) }
            if let text { report(await sender.composed(message: text.message, plain: text.plain)) }
        }
    }

    func sendLike() { sendLargeEmoji("👍") }

    func sendLargeEmoji(_ emoji: String) {
        guard let sender else { return }
        Task { report(await sender.largeEmoji(emoji)) }
    }

    /// Inserts `text` (an emoji picked from the panel) at the caret.
    func insert(_ text: String) {
        model.insertText(text)
        model.requestFocus()
    }

    // MARK: files

    func stage(_ files: [StagedFile]) {
        guard !files.isEmpty else { return }
        state.stagedFiles.append(contentsOf: files)
    }

    func stage(urls: [URL]) {
        stage(urls.compactMap(ChatStaging.staged(from:)))
    }

    func clearStaged() { state.stagedFiles = []; model.requestFocus() }

    func removeStaged(_ id: UUID) {
        state.stagedFiles.removeAll { $0.id == id }
        if state.stagedFiles.isEmpty { model.requestFocus() }
    }

    /// Files or an image on the clipboard are staged (true); false leaves plain text to the text view.
    func pasteAttachments() -> Bool {
        // Only folders copied: nothing to send, so the paste falls through to text (their paths).
        guard let items = readClipboardAttachments(), !items.isEmpty else { return false }
        stage(items.map { StagedFile(name: $0.name, data: $0.data, mimeType: ChatStaging.mimeType(forName: $0.name)) })
        return true
    }

    func pickFiles(imagesOnly: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if imagesOnly { panel.allowedContentTypes = [.image] }
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in self?.stage(urls: urls) }
        }
    }

    func sendCode(_ code: String, language: String, name: String?) async -> Outcome<Void> {
        guard let sender else { return .failure(.unexpected("Chat is not available")) }
        return await sender.code(code, language: language, name: name)
    }
}
