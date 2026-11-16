/// Ported from: lib/features/chat/presentation/widgets/{chat_composer_field,chat_composer_input,chat_composer_plain_input,chat_editor_styles}.dart
import AppKit
import SwiftUI

/// A key the composer takes before the text view does.
enum ComposerKeyEvent { case enter, tab, up, down, escape, toggleMarkdown }

final class ComposerNSTextView: NSTextView {
    var onKey: ((ComposerKeyEvent) -> Bool)?
    var onPaste: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        // An IME composing (Unikey, Pinyin…) owns the keys until it commits.
        if !hasMarkedText(), let key = Self.composerKey(event) {
            // Holding Enter must not type line breaks after the send.
            if onKey?(key) == true || (key == .enter && event.isARepeat) { return }
        }
        super.keyDown(with: event)
    }

    private static func composerKey(_ e: NSEvent) -> ComposerKeyEvent? {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch e.keyCode {
        case 36, 76: return flags.contains(.shift) || flags.contains(.option) ? nil : .enter
        case 48: return flags.isEmpty ? .tab : nil
        case 125: return flags.isEmpty ? .down : nil
        case 126: return flags.isEmpty ? .up : nil
        case 53: return .escape
        case 7: return flags.contains(.command) && flags.contains(.shift) ? .toggleMarkdown : nil   // X
        default: return nil
        }
    }

    /// Attachments on the clipboard are staged; plain text is inserted without its formatting.
    override func paste(_ sender: Any?) {
        if onPaste?() == true { return }
        pasteAsPlainText(sender)
    }
}

/// The multiline input: an `NSTextView` so IMEs, undo and spelling behave natively, bound to a `ChatComposerModel`.
struct ChatComposerTextView: NSViewRepresentable {
    let model: ChatComposerModel
    var font: NSFont
    var textColor: NSColor
    var accent: NSColor
    var revision: Int
    var focusTick: Int
    var resetUndoTick: Int
    var onKey: (ComposerKeyEvent) -> Bool
    var onPaste: () -> Bool
    var onChange: () -> Void
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = ComposerNSTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 0, height: 6)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        // Files dropped on the composer are handled by SwiftUI (staged), not pasted as paths.
        tv.unregisterDraggedTypes()
        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? ComposerNSTextView else { return }
        let c = context.coordinator
        c.parent = self
        tv.onKey = onKey
        tv.onPaste = onPaste
        if tv.font != font { tv.font = font }
        tv.textColor = textColor
        if tv.string != model.text, !tv.hasMarkedText() {
            c.applying = true
            let full = NSRange(location: 0, length: (tv.string as NSString).length)
            // Through the undo-aware path, so toolbar edits can be undone.
            if tv.shouldChangeText(in: full, replacementString: model.text) {
                tv.textStorage?.replaceCharacters(in: full, with: model.text)
                tv.didChangeText()
            }
            c.applying = false
        }
        let len = (tv.string as NSString).length
        let want = model.selection
        if NSMaxRange(want) <= len, want != tv.selectedRange(), !tv.hasMarkedText() {
            c.applying = true; tv.setSelectedRange(want); c.applying = false
        }
        c.restyle(tv)
        if c.lastFocus != focusTick { c.lastFocus = focusTick; DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) } }
        if c.lastReset != resetUndoTick { c.lastReset = resetUndoTick; tv.undoManager?.removeAllActions() }
        c.measure(tv)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatComposerTextView
        var applying = false
        var lastFocus = -1
        var lastReset = 0
        init(_ parent: ChatComposerTextView) { self.parent = parent }

        func textDidChange(_ n: Notification) {
            guard !applying, let tv = n.object as? NSTextView else { return }
            if let fix = parent.model.textChanged(tv.string, caret: tv.selectedRange().location, composing: tv.hasMarkedText()) {
                applying = true
                tv.string = fix.text
                tv.setSelectedRange(NSRange(location: fix.caret, length: 0))
                applying = false
            }
            restyle(tv); measure(tv)
            parent.onChange()
        }

        func textViewDidChangeSelection(_ n: Notification) {
            guard !applying, let tv = n.object as? NSTextView else { return }
            if parent.model.selection != tv.selectedRange() { parent.model.selection = tv.selectedRange() }
            parent.onChange()
        }

        /// Base look everywhere, the accent on each mention (left alone while an IME is composing).
        func restyle(_ tv: NSTextView) {
            guard !tv.hasMarkedText(), let storage = tv.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([.font: parent.font, .foregroundColor: parent.textColor], range: full)
            let bold = NSFontManager.shared.convert(parent.font, toHaveTrait: .boldFontMask)
            for m in parent.model.mentions where NSMaxRange(NSRange(location: m.start, length: m.end - m.start)) <= storage.length {
                storage.addAttributes([.foregroundColor: parent.accent, .font: bold], range: NSRange(location: m.start, length: m.end - m.start))
            }
            storage.endEditing()
            tv.typingAttributes = [.font: parent.font, .foregroundColor: parent.textColor]
        }

        func measure(_ tv: NSTextView) {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let h = ceil(lm.usedRect(for: tc).height + tv.textContainerInset.height * 2)
            if abs(h - parent.contentHeight) > 0.5 { DispatchQueue.main.async { self.parent.contentHeight = h } }
        }
    }
}
