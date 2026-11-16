import AppKit
import Observation

/// Ported from: lib/core/widgets/editor_toolbar_buttons.dart (the formatting actions behind the toolbar).
/// Applies formatting to the editor's selection (or to the typing attributes when nothing is selected) and
/// reports the active state for the toolbar.
@MainActor @Observable
final class RichEditorCommands {
    @ObservationIgnored weak var textView: NSTextView?
    @ObservationIgnored var style: RichStyle?
    private(set) var activeInline = RichInline()
    private(set) var activeBlock = RichBlock()

    private var storage: NSTextStorage? { textView?.textStorage }

    /// Re-reads the active formatting at the caret / selection start.
    func refresh() {
        guard let tv = textView, let storage else { return }
        let r = tv.selectedRange()
        if r.length == 0 && r.location >= storage.length || storage.length == 0 {
            activeInline = (tv.typingAttributes[.wnInline] as? InlineBox)?.value ?? RichInline()
            activeBlock = (tv.typingAttributes[.wnBlock] as? BlockBox)?.value ?? RichBlock()
            return
        }
        let at = min(max(r.length == 0 ? r.location - 1 : r.location, 0), storage.length - 1)
        activeInline = (storage.attribute(.wnInline, at: at, effectiveRange: nil) as? InlineBox)?.value ?? RichInline()
        activeBlock = (storage.attribute(.wnBlock, at: at, effectiveRange: nil) as? BlockBox)?.value ?? RichBlock()
    }

    // MARK: inline

    /// Toggles a boolean character attribute over the selection (set unless every character already has it).
    func toggle(_ key: WritableKeyPath<RichInline, Bool>) {
        let on = !activeInline[keyPath: key]
        applyInline { $0[keyPath: key] = on }
    }

    /// Changes the character attributes of the selection (or of what is typed next, with a bare caret).
    func applyInline(_ change: @escaping (inout RichInline) -> Void) {
        guard let tv = textView, let storage, let s = style else { return }
        let range = tv.selectedRange()
        if range.length == 0 {
            var inline = (tv.typingAttributes[.wnInline] as? InlineBox)?.value ?? RichInline()
            let block = (tv.typingAttributes[.wnBlock] as? BlockBox)?.value ?? RichBlock()
            change(&inline)
            tv.typingAttributes = RichAttributedBridge.attributes(inline: inline, block: block, style: s)
            refresh(); return
        }
        edit(range) {
            var runs: [(NSRange, RichInline, RichBlock)] = []
            storage.enumerateAttributes(in: range, options: []) { attrs, r, _ in
                runs.append((r, (attrs[.wnInline] as? InlineBox)?.value ?? RichInline(), (attrs[.wnBlock] as? BlockBox)?.value ?? RichBlock()))
            }
            for (r, var inline, block) in runs where inline.image == nil {
                change(&inline)
                storage.addAttributes(RichAttributedBridge.attributes(inline: inline, block: block, style: s), range: r)
            }
        }
        refresh()
    }

    // MARK: block

    /// Changes the paragraph attributes of every paragraph the selection touches.
    func applyBlock(_ change: @escaping (inout RichBlock) -> Void) {
        guard let tv = textView, let storage, let s = style else { return }
        let ns = storage.string as NSString
        let sel = tv.selectedRange()
        if storage.length == 0 {
            var block = (tv.typingAttributes[.wnBlock] as? BlockBox)?.value ?? RichBlock()
            change(&block)
            tv.typingAttributes = RichAttributedBridge.attributes(inline: RichInline(), block: block, style: s)
            refresh(); return
        }
        let paras = ns.paragraphRange(for: NSRange(location: min(sel.location, ns.length), length: sel.length))
        edit(paras) {
            storage.enumerateAttributes(in: paras, options: []) { attrs, r, _ in
                var block = (attrs[.wnBlock] as? BlockBox)?.value ?? RichBlock()
                let inline = (attrs[.wnInline] as? InlineBox)?.value ?? RichInline()
                change(&block)
                storage.addAttributes(RichAttributedBridge.attributes(inline: inline, block: block, style: s), range: r)
            }
        }
        // A caret at the end of the text keeps the new block for what is typed next.
        if sel.length == 0 {
            var block = (tv.typingAttributes[.wnBlock] as? BlockBox)?.value ?? RichBlock()
            change(&block)
            tv.typingAttributes = RichAttributedBridge.attributes(inline: activeInline, block: block, style: s)
        }
        refresh()
    }

    func setHeader(_ level: Int?) { applyBlock { $0.header = $0.header == level ? nil : level } }
    func toggleList(_ kind: RichListKind) { applyBlock { $0.list = $0.list == kind ? nil : kind; if $0.list != nil { $0.header = nil } } }
    func toggleBlockquote() { applyBlock { $0.blockquote.toggle() } }
    func toggleCodeBlock() { applyBlock { $0.codeBlock.toggle() } }
    func setAlign(_ a: String?) { applyBlock { $0.align = $0.align == a ? nil : a } }
    func indent(_ delta: Int) { applyBlock { $0.indent = min(max($0.indent + delta, 0), 8) } }
    func setColor(_ css: String?) { applyInline { $0.color = css } }
    func setBackground(_ css: String?) { applyInline { $0.background = css } }
    func setLink(_ url: String?) { applyInline { $0.link = url } }
    func clearFormat() { applyInline { $0 = RichInline() }; applyBlock { $0 = RichBlock() } }
    func undo() { textView?.undoManager?.undo() }
    func redo() { textView?.undoManager?.redo() }

    /// Runs `body` as one undoable edit of `range`.
    private func edit(_ range: NSRange, _ body: () -> Void) {
        guard let tv = textView else { return }
        guard tv.shouldChangeText(in: range, replacementString: nil) else { return }
        storage?.beginEditing(); body(); storage?.endEditing()
        tv.didChangeText()
    }
}
