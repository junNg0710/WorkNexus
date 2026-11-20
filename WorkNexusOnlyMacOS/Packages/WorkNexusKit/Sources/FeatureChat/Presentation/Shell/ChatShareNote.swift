/// Not in the Flutter app: the note sent with a link shared from elsewhere in the app.
import AppKit
import CoreDomain
import CoreUI
import Observation
import SwiftUI

/// What is typed as the note, as in the chat's input: `@` suggests the people of the chats picked (and "@all" when one is
/// a group); a picked name becomes a mention (`ChatComposerModel.messageText` writes it as the chat does).
@MainActor @Observable
final class ChatShareNoteModel {
    let text = ChatComposerModel()
    let mentions = MentionAutocomplete()
    /// Who can be mentioned: the people of the picked chats (everyone known when none is picked yet).
    private(set) var people: [Int] = []
    private(set) var hasGroup = false

    func setPeople(_ ids: [Int], hasGroup: Bool) { people = ids; self.hasGroup = hasGroup }

    /// Re-reads the `@query` before the caret and what it matches.
    func refresh(users: [Int: ChatUser], selfUserId: Int?) {
        mentions.update(value: text.valueText, selection: text.selection)
        guard let q = mentions.query else { mentions.visible = []; return }
        mentions.visible = MentionAutocomplete.filter(Self.candidates(people: people, hasGroup: hasGroup, users: users, selfUserId: selfUserId), q)
    }

    /// "@all" first when a group is picked, then each person (not the sender) by name, unknown ones as "User #id".
    nonisolated static func candidates(people: [Int], hasGroup: Bool, users: [Int: ChatUser], selfUserId: Int?) -> [MentionCandidate] {
        var out: [MentionCandidate] = hasGroup ? [MentionCandidate(userId: nil, name: "all", account: nil)] : []
        for id in people where id != selfUserId {
            let u = users[id]
            let name = (u?.realname.isEmpty == false ? u?.realname : u?.account) ?? "User #\(id)"
            out.append(MentionCandidate(userId: id, name: name, account: u?.account))
        }
        return out
    }

    /// Up/Down/Tab/Esc move through or close the suggestions; Enter picks one, else sends (`onSend`).
    func handle(_ key: ComposerKeyEvent, onSend: () -> Void) -> Bool {
        switch key {
        case .up: return mentions.handle(.up, model: text)
        case .down: return mentions.handle(.down, model: text)
        case .tab: return mentions.handle(.tab, model: text)
        case .escape: return mentions.handle(.escape, model: text)
        case .enter:
            if mentions.handle(.enter, model: text) { return true }
            onSend(); return true
        case .toggleMarkdown: return false
        }
    }
}

/// The note's box under the chats: grows with its lines up to a few, the suggestions above it while a name is typed.
struct ChatShareNote: View {
    @Environment(\.appTheme) private var theme
    let note: ChatShareNoteModel
    let users: [Int: ChatUser]
    let selfUserId: Int?
    let onSend: () -> Void
    @State private var height: CGFloat = 0
    static let fontSize: CGFloat = 14

    var body: some View {
        let font = theme.typography.nsFont(size: Self.fontSize)
        VStack(alignment: .leading, spacing: theme.spacing.s6) {
            ChatMentionList(mentions: note.mentions) { pick($0) }
            ZStack(alignment: .topLeading) {
                ChatComposerTextView(
                    model: note.text, font: font, textColor: NSColor(theme.colors.tx), accent: NSColor(theme.colors.accent),
                    revision: note.text.revision, focusTick: note.text.focusTick, resetUndoTick: note.text.resetUndoTick,
                    onKey: { note.handle($0, onSend: onSend) }, onPaste: { false },
                    onChange: { note.refresh(users: users, selfUserId: selfUserId) }, contentHeight: $height)
                if note.text.text.isEmpty {
                    Text(appString("chatShareNoteHint", "Add a note — type @ to mention someone"))
                        .font(theme.typography.body).foregroundStyle(theme.colors.tx3)
                        .padding(.top, theme.spacing.s6).allowsHitTesting(false).lineLimit(1)
                }
            }
            // One line to start, up to about three as it grows (as the chat's input does); past that it scrolls.
            .frame(height: min(max(height, theme.sizes.control36), theme.sizes.control36 * 3))
            .padding(.horizontal, theme.spacing.s10)
            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        }
    }

    private func pick(_ candidate: MentionCandidate) {
        note.mentions.insert(into: note.text, candidate)
        note.text.requestFocus()
        note.refresh(users: users, selfUserId: selfUserId)
    }
}
