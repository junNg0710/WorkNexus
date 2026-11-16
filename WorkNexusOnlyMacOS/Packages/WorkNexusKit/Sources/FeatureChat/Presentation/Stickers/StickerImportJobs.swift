/// Ported from: lib/features/chat/presentation/providers/sticker_import_jobs.dart (+ sticker_import_listener.dart)
import CoreDomain
import Foundation
import Observation

/// One sticker-set import running in the background.
struct StickerImportJob: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var done = 0
    var total = 0
    var finished = false
    var failure: String?
}

/// Imports of Telegram sticker sets, kept beyond the dialog that started them so the user can keep chatting. Shared per process.
@MainActor @Observable
final class StickerImportJobs {
    static let shared = StickerImportJobs()
    private(set) var jobs: [StickerImportJob] = []
    /// Bumped when an import added stickers, so open panels reload.
    private(set) var importedTick = 0

    var running: [StickerImportJob] { jobs.filter { !$0.finished } }

    /// Starts importing `link`; `onListed` gets the set's title as soon as Telegram answers (nil on failure, with the failure).
    func start(link: String, token: String, using importPack: ImportStickerPack, tokens: TelegramTokenStore?,
               onListed: @escaping @MainActor (Outcome<String>) -> Void) {
        let job = StickerImportJob(title: link)
        jobs.append(job)
        let id = job.id
        Task {
            var listed = false
            let result = await importPack(link, token: token, onListed: { title, total in
                Task { @MainActor in
                    listed = true
                    self.update(id) { $0.title = title; $0.total = total }
                    onListed(.success(title))
                }
            }, onProgress: { done, total in
                Task { @MainActor in self.update(id) { $0.done = done; $0.total = total } }
            })
            switch result {
            case .success:
                if let tokens { await tokens.write(token) }
                update(id) { $0.finished = true }
                importedTick += 1
            case .failure(let f):
                update(id) { $0.finished = true; $0.failure = f.message }
                if !listed { onListed(.failure(f)) }
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout StickerImportJob) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i])
    }
}
