/// Ported from: lib/features/chat/presentation/widgets/message_jump.dart + message_list_paging.dart (jumpTo)
import CoreDomain
import Foundation

/// Jumps to a message: in place when it is loaded, else through a window fetched around it.
extension MessageTimelineModel {
    /// How many older pages a jump may load to find its message.
    static let maxJumpPages = 20
    static var highlightFor: Duration = .seconds(2)

    /// Scrolls to message `serverId` and highlights it. Not loaded yet: a window is fetched around it (stepping back
    /// page by page only when it cannot be placed that way).
    func jump(to serverId: Int) async {
        await waitForFirstPage()
        var target = shownMessage(serverId: serverId)
        if target == nil {
            let local = await firstValue(of: services.chat.watchMessage(accountId: accountId, chatGid: chatGid, serverId: serverId))
            if let index = local??.index, index > 0 {
                resetPaging()
                window = .around(index: index)
                target = await waitUntilShown(serverId)
            }
            if target == nil {
                let around = await LoadMessagesAround(services.chat)(accountId: accountId, chatGid: chatGid, serverId: serverId)
                if case .success(let span?) = around {
                    resetPaging()
                    window = .around(from: span.from, to: span.to)
                    target = await waitUntilShown(serverId)
                } else {
                    target = await stepBack(to: serverId)
                }
            }
        }
        guard let target else { report(L.jumpNotFound); return }
        scroll(to: .message(gid: target.gid))
        await flash(serverId)
    }

    /// Highlights `serverId` for a moment.
    func flash(_ serverId: Int) async {
        highlighted = serverId
        try? await Task.sleep(for: Self.highlightFor)
        if highlighted == serverId { highlighted = nil }
    }

    /// Loads older pages until message `serverId` is shown, within `maxJumpPages`; nil when it never turns up.
    private func stepBack(to serverId: Int) async -> ChatMessage? {
        for _ in 0..<Self.maxJumpPages {
            if let found = shownMessage(serverId: serverId) { return found }
            if reachedStart || loadFailed || Task.isCancelled { return nil }
            await loadOlder()
            try? await Task.sleep(for: .milliseconds(80))
        }
        return shownMessage(serverId: serverId)
    }

    /// Waits (briefly) for the stream of a new window to deliver the message.
    private func waitUntilShown(_ serverId: Int) async -> ChatMessage? {
        for _ in 0..<60 {
            if let m = shownMessage(serverId: serverId) { return m }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    /// A chat just opened: its first page may still be on its way.
    private func waitForFirstPage() async {
        for _ in 0..<100 where !loaded { try? await Task.sleep(for: .milliseconds(50)) }
    }

    private func firstValue<T: Sendable>(of stream: AsyncStream<T>) async -> T? {
        for await v in stream { return v }
        return nil
    }
}
