/// Ported from: lib/features/chat/presentation/widgets/mention_autocomplete.dart
import Foundation
import Observation

/// Someone (or everyone) that can be mentioned. `userId` is nil for "@all".
struct MentionCandidate: Hashable, Sendable {
    var userId: Int?
    var name: String
    var account: String?
}

/// Composer state for @mentions: the `@query` typed right before the caret and the highlighted suggestion.
@MainActor @Observable
final class MentionAutocomplete {
    private static let queryPattern = try! NSRegularExpression(pattern: #"(?:^|\s)@([^\s@]{0,30})$"#)

    private(set) var active: (start: Int, query: String)?
    private(set) var highlight = 0
    /// Query start dismissed with Esc: hidden until the user types elsewhere.
    private var dismissedAt: Int?
    /// The suggestions on screen (set by the list), for keyboard selection.
    var visible: [MentionCandidate] = []

    var query: String? { active?.query }

    /// Re-reads the query after every edit or caret move. `value` is `ChatComposerModel.valueText`.
    func update(value: String, selection: NSRange) {
        let ns = value as NSString
        var next: (start: Int, query: String)?
        if selection.length == 0, selection.location <= ns.length {
            let before = ns.substring(to: selection.location)
            if let m = Self.queryPattern.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) {
                let q = (before as NSString).substring(with: m.range(at: 1))
                next = (selection.location - (q as NSString).length - 1, q)
            }
        }
        if next?.start != dismissedAt { dismissedAt = nil }
        if let n = next, n.start == dismissedAt { next = nil }
        if next?.query != active?.query || next?.start != active?.start {
            active = next
            highlight = 0
        }
    }

    func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        highlight = ((highlight + delta) % count + count) % count
    }

    func highlightAt(_ index: Int) { if index != highlight { highlight = index } }

    func dismiss() { dismissedAt = active?.start; active = nil }

    /// After sending: no query is pending.
    func reset() { active = nil; dismissedAt = nil; visible = [] }

    /// Replaces the typed `@query` with a mention of `candidate`.
    func insert(into model: ChatComposerModel, _ candidate: MentionCandidate) {
        guard let active else { return }
        model.insertMention(start: active.start, end: model.selection.location, id: candidate.userId, name: candidate.name)
        self.active = nil
    }

    /// Types "@" at the caret (after a space if needed): starts a mention.
    func start(in model: ChatComposerModel) {
        let ns = model.valueText as NSString
        let at = min(model.selection.location, ns.length)
        let before = ns.substring(to: at)
        let spaced = before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n")
        model.insertText(spaced ? "@" : " @")
    }

    enum Key { case up, down, enter, tab, escape }

    /// Up/Down pick, Enter/Tab insert into `model`, Esc closes while suggestions are shown. Whether `key` was taken.
    func handle(_ key: Key, model: ChatComposerModel) -> Bool {
        guard query != nil, !visible.isEmpty else { return false }
        switch key {
        case .down: move(1, count: visible.count)
        case .up: move(-1, count: visible.count)
        case .enter, .tab: insert(into: model, visible[min(highlight, visible.count - 1)])
        case .escape: dismiss()
        }
        return true
    }

    /// `all` filtered by the query (name or account, case-insensitive), prefix matches first, at most `limit`.
    nonisolated static func filter(_ all: [MentionCandidate], _ query: String, limit: Int = 8) -> [MentionCandidate] {
        let q = query.lowercased()
        func has(_ c: MentionCandidate, _ test: (String) -> Bool) -> Bool { test(c.name.lowercased()) || test((c.account ?? "").lowercased()) }
        let prefix = all.filter { has($0) { $0.hasPrefix(q) } }
        let contains = all.filter { c in !has(c) { $0.hasPrefix(q) } && has(c) { $0.contains(q) } }
        return Array((prefix + contains).prefix(limit))
    }
}
