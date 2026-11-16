/// Ported from: lib/features/chat/presentation/widgets/message_actions.dart
import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// One action on a message, offered on hover and in its right-click menu. `destructive` ones (retract) come last.
struct MessageAction: Identifiable {
    var id: String
    var icon: String
    var title: String
    var destructive = false
    /// Starts a group of its own in the menus (a divider before it).
    var sectionStart = false
    var run: () -> Void
}

extension ThreadContext {
    /// The actions a message offers: reply, open its thread, forward, copy text, translate, save an image as a sticker,
    /// pin/unpin (where allowed), make a ZenTao bug / task / todo of it, pick several messages and — for your own
    /// recent messages — retract.
    func actions(for message: ChatMessage, settings: ChatSettings, inThread: Bool) -> [MessageAction] {
        let serverId = message.serverId
        let chat = services.chat, report = model.report, state = state
        var out: [MessageAction] = []
        if serverId != nil, !message.deleted {
            out.append(MessageAction(id: "reply", icon: "quote.opening", title: L.reply) { state.replyDraft = message })
        }
        if inThread, let serverId {
            out.append(MessageAction(id: "thread", icon: "bubble.left.and.bubble.right", title: L.openThread) { state.sidePanel = .thread(rootServerId: serverId) })
        }
        if let forward = actions.forward, canForward(message) {
            out.append(MessageAction(id: "forward", icon: "arrowshape.turn.up.right", title: L.forward) { forward(message) })
        }
        let text = message.deleted ? nil : message.content.asText?.text
        let copy = ChatMessageExport.text(of: message)
        if let copy {
            out.append(MessageAction(id: "copy", icon: "doc.on.doc", title: L.copy) { Self.copy(copy); model.notify(L.copied) })
        }
        out += translateActions(message, settings: settings, hasText: text != nil)
        if message.content.asImage != nil, serverId != nil, !message.deleted, let save = actions.saveAsSticker {
            out.append(MessageAction(id: "sticker", icon: "face.smiling", title: L.saveSticker) { save(message) })
        }
        if let serverId, !message.deleted, PinChatMessage(chat).canPin(state.chat, selfUserId: state.selfUserId, selfAccount: state.selfAccount) {
            let pinned = state.chat.pinnedMessageIds.contains(serverId)
            out.append(MessageAction(id: "pin", icon: pinned ? "pin.slash" : "pin", title: pinned ? L.unpin : L.pin) {
                Task { @MainActor in if case .failure(let f) = await PinChatMessage(chat)(message, pinned: !pinned) { report(f.message) } }
            })
        }
        if copy != nil, let create = actions.createTicket {
            out.append(MessageAction(id: "createBug", icon: "ladybug", title: L.createBug, sectionStart: true) { create(.bug, [message]) })
            out.append(MessageAction(id: "createTask", icon: "checklist", title: L.createTask) { create(.task, [message]) })
            out.append(MessageAction(id: "createTodo", icon: "calendar.badge.plus", title: L.createTodo) { create(.todo, [message]) })
        }
        if ChatThreadState.canSelect(message) {
            out.append(MessageAction(id: "select", icon: "checkmark.circle", title: L.selectMultiple, sectionStart: true) {
                state.beginSelection(with: message)
            })
        }
        if RetractMessage(chat).canRetract(message) {
            out.append(MessageAction(id: "retract", icon: "arrow.uturn.backward", title: L.retract, destructive: true) {
                Task { @MainActor in if case .failure(let f) = await RetractMessage(chat)(message) { report(f.message) } }
            })
        }
        return out
    }

    private func translateActions(_ message: ChatMessage, settings: ChatSettings, hasText: Bool) -> [MessageAction] {
        let tr = model.translation
        guard hasText, tr.available else { return [] }
        let shown = tr.isShown(message.gid)
        var out = [MessageAction(id: "translate", icon: "character.bubble", title: shown ? L.hideTranslation : L.translate) {
            Task { @MainActor in
                if shown { await tr.hide(message, lang: settings.translationLang) }
                else { await tr.translate(message, lang: settings.translationLang, model: settings.translationModel) }
            }
        }]
        if tr.hasDone(message.gid) {
            out.append(MessageAction(id: "retranslate", icon: "arrow.clockwise", title: L.retranslate) {
                Task { @MainActor in await tr.translate(message, lang: settings.translationLang, model: settings.translationModel, force: true) }
            })
        }
        return out
    }

    /// Whether a message can be forwarded: stored, not retracted.
    func canForward(_ message: ChatMessage) -> Bool { message.serverId != nil && !message.deleted && message.sendState == .sent }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
