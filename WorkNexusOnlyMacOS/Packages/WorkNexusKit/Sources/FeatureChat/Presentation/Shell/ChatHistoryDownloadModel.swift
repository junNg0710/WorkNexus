import CoreDomain
import Foundation
import Observation

/// Search sees only stored messages: while a chat is searched and its stored history does not yet go back as far as the
/// search period, this downloads the rest and reports its progress until it is done, stopped or failed.
/// Ported from: lib/features/chat/presentation/providers/chat_history_download.dart
@MainActor @Observable
final class ChatHistoryDownloadModel {
    enum Phase: Equatable { case idle, running(ChatHistoryProgress?), done, cancelled, failed(String) }

    private(set) var phase: Phase = .idle
    @ObservationIgnored private let accountId: String
    @ObservationIgnored private let chatGid: String
    @ObservationIgnored private let repository: ChatRepository
    @ObservationIgnored private let period: () -> ChatSearchPeriod
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Told after each page (the search runs again over what arrived) and when it ends.
    @ObservationIgnored var onProgress: () -> Void = {}

    init(accountId: String, chatGid: String, repository: ChatRepository, period: @escaping () -> ChatSearchPeriod) {
        self.accountId = accountId; self.chatGid = chatGid; self.repository = repository; self.period = period
    }

    /// Starts the download once the search needs it: not while searching nothing, nor when the history is already complete.
    func ensure(searching: Bool) async {
        guard searching, phase == .idle else { return }
        let since = period().since(Date())
        if case .success(let extent) = await repository.timelineExtent(accountId: accountId, chatGid: chatGid), extent.reaches(since) {
            return
        }
        guard phase == .idle, !Task.isCancelled else { return }
        start()
    }

    func start() {
        guard task == nil else { return }
        phase = .running(nil)
        let stream = DownloadChatHistory(repository)(accountId: accountId, chatGid: chatGid, since: period().since(Date()))
        task = Task { [weak self] in
            for await outcome in stream {
                guard let self, !Task.isCancelled else { return }
                self.receive(outcome)
            }
            self?.task = nil
        }
    }

    private func receive(_ outcome: Outcome<ChatHistoryProgress>) {
        switch outcome {
        case .success(let p) where p.complete: finish(.done)
        case .success(let p): phase = .running(p); onProgress()
        case .failure(let f): finish(.failed(f.message))
        }
    }

    private func finish(_ next: Phase) {
        task?.cancel(); task = nil; phase = next; onProgress()
    }

    /// Stops after the page in flight; what arrived so far stays stored.
    func cancel() { if task != nil { finish(.cancelled) } }

    /// Another period asks for another download: start over.
    func reset() { task?.cancel(); task = nil; phase = .idle }

    /// The search bar closed: stops the download and forgets where it stood (as the Flutter provider is disposed), so the
    /// next search checks the stored history again and resumes the download. Left "running", every later search took
    /// the download as under way and never started it again.
    func teardown() { task?.cancel(); task = nil; phase = .idle }
}
