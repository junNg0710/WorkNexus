/// Ported from: lib/features/chat/presentation/widgets/message_list_paging.dart (MessageListPaging)
import CoreDomain
import Foundation

/// Older pages at the top, newer ones at the bottom of a jump window.
extension MessageTimelineModel {
    func resetPaging() {
        loadingOlder = false
        reachedStart = false
        loadingNewer = false
        newerExhausted = false
        loadFailed = false
    }

    /// Records where the reader was before older rows were added above, so the list can keep them in place.
    func notePrepended(_ before: [ChatMessage], _ after: [ChatMessage]) {
        guard let oldFirst = before.first?.gid, let at = after.firstIndex(where: { $0.gid == oldFirst }), at > 0 else { return }
        prependedAnchor = oldFirst
        prependCount += 1
    }

    /// Starts fetching the next older page right away (the busy flag is up before this returns, so a burst of scroll
    /// events asks once).
    func beginLoadOlder() {
        guard !loadingOlder else { return }
        loadingOlder = true
        Task { await fetchOlder() }
    }

    /// Starts fetching the next newer page of a jump window right away.
    func beginLoadNewer() {
        guard !loadingNewer else { return }
        loadingNewer = true
        Task { await fetchNewer() }
    }

    /// Reveals the next older page: from storage when it holds one, else from the server.
    func loadOlder() async {
        guard !loadingOlder else { return }
        loadingOlder = true
        await fetchOlder()
    }

    private func fetchOlder() async {
        let shown = messages
        let inWindow = window.isAround
        loadFailed = false
        let repo = services.chat, account = accountId, gid = chatGid
        let result = await PerformanceLog.measure("chat: load older messages", slowerThan: 0.3) {
            await LoadOlderMessages(repo)(accountId: account, chatGid: gid, oldestShown: shown.first, inWindow: inWindow)
        }
        switch result {
        case .success(let n) where n > 0:
            let grown = window.growingOlder(shown: messages.count, by: min(n, ChatMessageWindow.pageSize))
            if grown != window { grow(to: grown); return }
        // Nothing was cached yet: that call fetched the latest page, which is not the start of the chat.
        case .success where shown.isEmpty: break
        case .success: reachedStart = true
        case .failure(let f): loadFailed = true; report(f.message)
        }
        loadingOlder = false
    }

    /// Sets the grown window. The busy flags stay up until its messages are in, so a burst of scroll events does not ask
    /// again meanwhile (and a stream that never answers cannot keep them up for long).
    private func grow(to next: ChatMessageWindow) {
        awaitingGrowth = true
        window = next
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.awaitingGrowth else { return }
            self.awaitingGrowth = false; self.loadingOlder = false; self.loadingNewer = false
        }
    }

    /// In a jump window, fetches the messages after the newest one shown; with none left, the window joins the timeline
    /// and reads on as usual.
    func loadNewer() async {
        guard !loadingNewer else { return }
        loadingNewer = true
        await fetchNewer()
    }

    private func fetchNewer() async {
        guard case .around(let from, _) = window, let newest = messages.last else { loadingNewer = false; return }
        let repo = services.chat, account = accountId, gid = chatGid
        let result = await PerformanceLog.measure("chat: load newer messages", slowerThan: 0.3) {
            await LoadNewerMessages(repo)(accountId: account, chatGid: gid, newestShown: newest, windowFrom: from)
        }
        switch result {
        case .success(let v) where v.added > 0: grow(to: window.growingNewer(by: v.added)); return
        case .success(let v):
            if let joined = v.joined { grow(to: .live(limit: joined)); return }
            newerExhausted = true
        case .failure(let f): newerExhausted = true; report(f.message)
        }
        loadingNewer = false
    }

    /// Leaves a jump window for the newest messages, scrolled to the bottom.
    func backToLatest() {
        window = .initial
        resetPaging()
        scroll(to: .bottom, animated: false)
    }

    /// Whether scrolling near the top should fetch older messages now.
    var canAutoLoadOlder: Bool { loaded && !loadingOlder && !reachedStart && !loadFailed }

    /// Whether scrolling near the bottom of a jump window should fetch newer messages now.
    var canAutoLoadNewer: Bool { loaded && window.isAround && !loadingNewer && !newerExhausted && !loadFailed }
}
