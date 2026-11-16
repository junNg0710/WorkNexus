/// Ported from: lib/features/chat/presentation/providers/chat_typing_sender.dart (+ chat_typing_providers.dart)
import Foundation

/// Turns composer edits into typing signals: "typing" at most once per `interval` while the text changes, then "stopped" once
/// when the text is sent or cleared, or the chat is closed (`stop`).
@MainActor
final class ChatTypingSender {
    typealias Send = @MainActor (ChatConversation, _ typing: Bool) -> Void
    private let send: Send
    private let chat: () -> ChatConversation?
    private let enabled: () -> Bool
    private let now: () -> Date
    private let interval: TimeInterval
    private var text = ""
    private var lastTyping: Date?
    /// The chat the current burst was announced in, so the stop reaches it even once the chat itself is gone.
    private var announced: ChatConversation?

    init(send: @escaping Send, chat: @escaping () -> ChatConversation?, enabled: @escaping () -> Bool,
         now: @escaping () -> Date = Date.init, interval: TimeInterval = 3) {
        self.send = send; self.chat = chat; self.enabled = enabled; self.now = now; self.interval = interval
    }

    /// Called on every composer change with its text.
    func changed(_ next: String) {
        // Selection moves notify too; only an edit counts as typing.
        guard next != text else { return }
        text = next
        if next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return stop() }
        let t = now()
        if let last = lastTyping, t.timeIntervalSince(last) < interval { return }
        guard enabled(), let c = announced ?? chat() else { return }
        announced = c
        lastTyping = t
        send(c, true)
    }

    /// Ends the burst, if one was announced.
    func stop() {
        let c = announced
        announced = nil; lastTyping = nil
        if let c { send(c, false) }
    }
}
