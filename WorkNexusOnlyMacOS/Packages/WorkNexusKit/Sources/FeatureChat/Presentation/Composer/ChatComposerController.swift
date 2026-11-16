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
        typing = ChatTypingSender(
            send: { [weak self] chat, on in self?.sendTyping(chat, on) },
            chat: { [weak self] in self?.state.chat },
            enabled: { [weak self] in self?.settings.sendTypingStatus ?? false })
    }

    var markdown: Bool { markdownOverride ?? settings.sendMarkdown }

    private var sender: ChatMessageSender? {
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
    }

    func stopTyping() { typing.stop() }

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
            if state.replyDraft != nil { state.replyDraft = nil; return true }
            return false
        case .enter:
            if mentions.handle(.enter, model: model) { return true }
            send(); return true
        case .toggleMarkdown: markdownOverride = !markdown; return true
        }
    }

    // MARK: sending

    private func report(_ result: Outcome<Void>) {
        if case .failure(let f) = result {
            error = appString("chatActionFailed", "Couldn't complete that: {reason}").replacingOccurrences(of: "{reason}", with: f.message)
        }
    }

    /// Sends the input; a lone emoji goes large.
    func send() {
        guard !model.isBlank, let sender else { return }
        let message = model.messageText
        let plain = model.hasMentions ? nil : model.plainText
        model.clear(); mentions.reset()
        typing.changed("")
        Task { report(await sender.composed(message: message, plain: plain)) }
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

    /// Sends the staged files, then goes back to typing.
    func sendStaged() {
        let files = state.stagedFiles
        state.stagedFiles = []
        model.requestFocus()
        guard !files.isEmpty, let sender else { return }
        Task { report(await sender.files(files)) }
    }

    func clearStaged() { state.stagedFiles = []; model.requestFocus() }

    func removeStaged(_ id: UUID) {
        state.stagedFiles.removeAll { $0.id == id }
        if state.stagedFiles.isEmpty { model.requestFocus() }
    }

    /// Files or an image on the clipboard are staged (true); false leaves plain text to the text view.
    func pasteAttachments() -> Bool {
        guard let items = readClipboardAttachments() else { return false }
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
