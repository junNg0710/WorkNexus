/// Not in the Flutter app.
import AppKit
import CoreUI
import SwiftUI

extension ThreadContext {
    /// What a right-click on a message's text offers, instead of the text system's menu (Font, Spelling, Writing Direction,
    /// Services…): copy the words picked, copy the message, reply, forward, translate. The rest stays under "…".
    func textMenu(for message: ChatMessage, settings: ChatSettings, selection: String?) -> [AppNativeMenu.Item] {
        var items: [AppNativeMenu.Item] = []
        if let selection, !selection.isEmpty {
            items.append(AppNativeMenu.Item(L.copySelection, icon: "text.cursor") { Self.copy(selection) })
        }
        let wanted = ["copy", "reply", "forward", "translate", "retranslate", "translateTo"]
        let actions = actions(for: message, settings: settings, inThread: false).filter { wanted.contains($0.id) }
            .sorted { wanted.firstIndex(of: $0.id)! < wanted.firstIndex(of: $1.id)! }
        for (i, a) in actions.enumerated() {
            items.append(a.nativeMenuItem(dividerBefore: i == 0 || a.id == "reply"))
        }
        return items
    }
}

extension ThreadContext {
    /// The message's whole menu as a native one (what its "…" and the SwiftUI context menu list): React first, then the
    /// actions, reply apart and destructive ones last.
    func messageMenu(for message: ChatMessage, settings: ChatSettings, inThread: Bool, react: @escaping () -> Void) -> [AppNativeMenu.Item] {
        var items: [AppNativeMenu.Item] = []
        if canReact(to: message) { items.append(AppNativeMenu.Item(L.react, icon: "face.smiling", action: react)) }
        let actions = actions(for: message, settings: settings, inThread: inThread)
        let firstDestructive = actions.firstIndex { $0.destructive }
        for (i, a) in actions.enumerated() {
            items.append(a.nativeMenuItem(dividerBefore: (i == 1 && !items.isEmpty) || i == firstDestructive || (a.sectionStart && i > 1)
                                          || (i == 0 && !items.isEmpty)))
        }
        return items
    }
}

extension MessageAction {
    /// The action as a native menu item, its children as a submenu.
    func nativeMenuItem(dividerBefore: Bool = false) -> AppNativeMenu.Item {
        children.isEmpty
            ? AppNativeMenu.Item(title, icon: icon, destructive: destructive, dividerBefore: dividerBefore, action: run)
            : AppNativeMenu.Item(title, icon: icon, dividerBefore: dividerBefore, children: children.map { $0.nativeMenuItem() })
    }
}

/// Answers a right-click inside the message it is put behind (the pointer is over it): on its text (or its translation),
/// the short text menu (`items(selection, true)`); anywhere else on it, the message's whole menu (`items(nil, false)`).
/// Either way the app's menu, never the text system's (Font, Spelling, Services…). Watched through `ChatRightClick`.
struct MessageTextRightClick: NSViewRepresentable {
    let active: Bool
    let items: (_ selection: String?, _ onText: Bool) -> [AppNativeMenu.Item]

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.items = items
        if active { ChatRightClick.shared.add(view) } else { ChatRightClick.shared.remove(view) }
    }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) { ChatRightClick.shared.remove(view) }

    final class CatcherView: NSView {
        var items: ((String?, Bool) -> [AppNativeMenu.Item])?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Behind the message list: a right-click on text there that no message took (the pointer had not been seen over it,
/// after a scroll for one) still gets the app's menu - copying the words picked, or the text - not the text system's.
struct MessageListRightClick: NSViewRepresentable {
    func makeNSView(context: Context) -> AreaView { let v = AreaView(); ChatRightClick.shared.addArea(v); return v }
    func updateNSView(_ view: AreaView, context: Context) {}
    static func dismantleNSView(_ view: AreaView, coordinator: ()) { ChatRightClick.shared.removeArea(view) }

    final class AreaView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// The one watcher of right-clicks in the chat's message lists, for the message under the pointer (`MessageTextRightClick`)
/// and, failing that, the list itself (`MessageListRightClick`). Watches only while there is something to answer for.
@MainActor
final class ChatRightClick {
    static let shared = ChatRightClick()
    private var rows: [WeakView<MessageTextRightClick.CatcherView>] = []
    private var areas: [WeakView<MessageListRightClick.AreaView>] = []
    private var monitor: Any?

    func add(_ row: MessageTextRightClick.CatcherView) {
        rows.removeAll { $0.view == nil || $0.view === row }
        rows.append(WeakView(row)); watch()
    }
    func remove(_ row: MessageTextRightClick.CatcherView) { rows.removeAll { $0.view == nil || $0.view === row }; watch() }
    func addArea(_ area: MessageListRightClick.AreaView) { areas.removeAll { $0.view == nil }; areas.append(WeakView(area)); watch() }
    func removeArea(_ area: MessageListRightClick.AreaView) { areas.removeAll { $0.view == nil || $0.view === area }; watch() }

    private func watch() {
        let needed = rows.contains { $0.view != nil } || areas.contains { $0.view != nil }
        if needed, monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
                MainActor.assumeIsolated { ChatRightClick.shared.answer(event) ? nil : event }
            }
        } else if !needed, let m = monitor {
            NSEvent.removeMonitor(m); monitor = nil
        }
    }

    /// Shows the app's menu for a right-click it is for; false leaves the click as it was.
    private func answer(_ event: NSEvent) -> Bool {
        guard let window = event.window, let items = menu(at: event.locationInWindow, in: window) else { return false }
        AppNativeMenu.popUp(items)
        return true
    }

    /// The app's menu for a right-click at `point` (window coordinates), or nil when the click is not one of the chat's.
    func menu(at point: NSPoint, in window: NSWindow) -> [AppNativeMenu.Item]? {
        let text = Self.textView(at: point, in: window)
        for row in rows.compactMap(\.view) where row.window === window && Self.contains(row, point) {
            if let items = row.items?(text.flatMap(Self.selection(of:)), text != nil), !items.isEmpty { return items }
        }
        // Text in a message list that no message answered for: copying is what it offers.
        guard let text, areas.compactMap(\.view).contains(where: { $0.window === window && Self.contains($0, point) }) else { return nil }
        let items = Self.copyItems(text)
        return items.isEmpty ? nil : items
    }

    private static func contains(_ view: NSView, _ point: NSPoint) -> Bool { view.bounds.contains(view.convert(point, from: nil)) }

    static func copyItems(_ text: NSView) -> [AppNativeMenu.Item] {
        var items: [AppNativeMenu.Item] = []
        if let picked = selection(of: text) { items.append(AppNativeMenu.Item(L.copySelection, icon: "text.cursor") { ThreadContext.copy(picked) }) }
        if let all = (text as? NSTextView)?.string ?? text.accessibilityValue() as? String, !all.isEmpty {
            items.append(AppNativeMenu.Item(L.copy, icon: "doc.on.doc") { ThreadContext.copy(all) })
        }
        return items
    }

    /// The view of the text under the pointer, if it is on text: selectable SwiftUI text is drawn by a private AppKit view
    /// that reads as static text to accessibility (an `NSTextView` elsewhere).
    static func textView(at point: NSPoint, in window: NSWindow) -> NSView? {
        guard let content = window.contentView else { return nil }
        // `hitTest` takes the point in its superview's coordinates: given in the content's own (flipped, as SwiftUI's
        // hosting view is) it looked at the mirrored height, and text was found only where it happened to sit there too.
        var view = content.hitTest(content.superview?.convert(point, from: nil) ?? point)
        while let v = view {
            if v is NSTextView || v.accessibilityRole() == .staticText { return v }
            view = v.superview
        }
        return nil
    }

    /// The words picked in it, if any.
    static func selection(of view: NSView) -> String? {
        if let text = view as? NSTextView {
            let string = text.string as NSString
            let picked = text.selectedRanges.map(\.rangeValue).filter { $0.length > 0 && NSMaxRange($0) <= string.length }
            return picked.isEmpty ? nil : picked.map { string.substring(with: $0) }.joined(separator: "\n")
        }
        return view.accessibilitySelectedText().flatMap { $0.isEmpty ? nil : $0 }
    }
}

private struct WeakView<V: NSView> {
    weak var view: V?
    init(_ v: V) { view = v }
}
