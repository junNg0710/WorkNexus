/// Ported from: lib/features/chat/presentation/widgets/chat_composer_controller.dart + chat_mention_text_controller.dart
import Foundation
import Observation

/// What is being typed in the composer: plain text (Markdown markers shown as typed) plus the `@Name`s that are mentions.
/// A mention moves with the text around it, is deleted whole when a deletion reaches into it, and becomes plain text when
/// typed into. `messageText` writes it as the message to send (`[@Name](@#id)` for each mention).
@MainActor @Observable
final class ChatComposerModel {
    private(set) var text = ""
    var selection = NSRange(location: 0, length: 0)
    private(set) var mentions: [ChatTextMention] = []
    /// Bumped whenever the text was changed from outside the text view, so the view re-reads it.
    private(set) var revision = 0
    /// Bumped to ask the text view for keyboard focus.
    private(set) var focusTick = 0
    /// Set after sending: the text view forgets its undo history.
    private(set) var resetUndoTick = 0

    init() {}

    var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasMentions: Bool { !mentions.isEmpty }
    var plainText: String { text }

    func requestFocus() { focusTick += 1 }

    /// The text with each mention as one placeholder character, so it never reads as an `@query` being typed. Offsets match `text`
    /// when every mention name is one UTF-16 unit long; it is only used to read what lies before the caret, so it is padded.
    var valueText: String {
        guard !mentions.isEmpty else { return text }
        var units = Array(text.utf16)
        for m in mentions where m.end <= units.count { for i in m.start..<m.end { units[i] = 0xFFFC } }
        return String(decoding: units, as: UTF16.self)
    }

    /// The message to send: mentions as markup, trailing blank lines dropped.
    var messageText: String {
        let ns = text as NSString
        var out = "", at = 0
        for m in mentions.sorted(by: { $0.start < $1.start }) where m.start >= at && m.end <= ns.length {
            out += ns.substring(with: NSRange(location: at, length: m.start - at))
            let name = ns.substring(with: NSRange(location: m.start + 1, length: m.end - m.start - 1))
            out += "[@\(name)](@#\(m.id))"
            at = m.end
        }
        out += ns.substring(from: at)
        while let last = out.last, last.isWhitespace || last.isNewline { out.removeLast() }
        return out
    }

    // MARK: edits from the text view

    /// The text view now shows `next` with the caret at `caret`. Returns the text and caret the view must show instead, when a
    /// deletion reached into a mention and removed it whole (left alone while an IME is composing).
    @discardableResult
    func textChanged(_ next: String, caret: Int, composing: Bool) -> (text: String, caret: Int)? {
        let previous = text
        guard next != previous else { selection = NSRange(location: caret, length: 0); return nil }
        guard !mentions.isEmpty else { text = next; selection = NSRange(location: caret, length: 0); return nil }
        var edit = ChatMentionEdit.between(previous, next, caret: caret)
        var shown = next, shownCaret = caret
        if edit.inserted == 0, !composing {
            let wide = ChatMentionEdit.widenedForMentions(edit, mentions)
            if wide != edit {
                edit = wide
                shown = (previous as NSString).replacingCharacters(in: NSRange(location: wide.start, length: wide.oldEnd - wide.start), with: "")
                shownCaret = wide.start
            }
        }
        mentions = ChatMentionEdit.shift(mentions, edit)
        text = shown
        selection = NSRange(location: shownCaret, length: 0)
        return shown == next ? nil : (shown, shownCaret)
    }

    // MARK: programmatic edits

    /// Puts `replacement` in place of `range`, the caret after it.
    func replace(_ range: NSRange, with replacement: String) {
        let ns = text as NSString
        let r = NSRange(location: min(range.location, ns.length), length: min(range.length, max(0, ns.length - range.location)))
        let edit = ChatTextEdit(start: r.location, oldEnd: NSMaxRange(r), inserted: (replacement as NSString).length)
        mentions = ChatMentionEdit.shift(mentions, edit)
        text = ns.replacingCharacters(in: r, with: replacement)
        selection = NSRange(location: r.location + edit.inserted, length: 0)
        revision += 1
    }

    /// Puts `insertion` in place of the selection (or at the end when the selection is past the text).
    func insertText(_ insertion: String) {
        let len = (text as NSString).length
        replace(selection.location <= len ? selection : NSRange(location: len, length: 0), with: insertion)
    }

    /// Replaces `start..<end` (the typed `@query`) with a mention of `name` and a space. Without an `id` (`@all`) it is plain text.
    func insertMention(start: Int, end: Int, id: Int?, name: String) {
        let label = "@\(name)"
        replace(NSRange(location: start, length: end - start), with: label + " ")
        if let id {
            mentions.append(ChatTextMention(start: start, end: start + (label as NSString).length, id: id))
            mentions.sort { $0.start < $1.start }
        }
    }

    func isOn(_ format: MarkdownFormat) -> Bool { MarkdownFormatter.isOn(format, text: text, selection: selection) }

    /// Applies `format` to the selection, or takes it off when it is on.
    func apply(_ format: MarkdownFormat) {
        let result = MarkdownFormatter.apply(format, text: text, selection: selection)
        for e in result.edits.reversed() {
            let edit = ChatTextEdit(start: e.range.location, oldEnd: NSMaxRange(e.range), inserted: (e.replacement as NSString).length)
            mentions = ChatMentionEdit.shift(mentions, edit)
            text = (text as NSString).replacingCharacters(in: e.range, with: e.replacement)
        }
        selection = result.selection
        revision += 1
    }

    /// Empties the composer (after sending), history too.
    func clear() {
        text = ""; mentions = []; selection = NSRange(location: 0, length: 0)
        revision += 1; resetUndoTick += 1
    }
}
