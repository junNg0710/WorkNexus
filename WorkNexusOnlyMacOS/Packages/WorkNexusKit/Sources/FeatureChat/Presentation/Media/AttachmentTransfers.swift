/// Ported from: lib/features/chat/presentation/widgets/attachment_download.dart (`openAttachment`, `chatDownloadingProvider`)
import AppKit
import CoreDomain
import Foundation
import Observation

/// What identifies one attachment download.
struct TransferKey: Hashable, Sendable {
    var accountId: String
    var content: MessageContent
}

/// Attachment downloads in flight, shared by every view of the same attachment so progress survives a list row being recycled.
@MainActor @Observable
final class AttachmentTransfers {
    static let shared = AttachmentTransfers()
    /// 0-1 progress of each running download.
    private(set) var running: [TransferKey: Double] = [:]
    private var cached: [TransferKey: Bool] = [:]

    func progress(_ key: TransferKey) -> Double? { running[key] }
    func isDownloading(_ key: TransferKey) -> Bool { running[key] != nil }

    /// Whether the attachment is already on this device (remembered once true).
    func isCached(_ key: TransferKey, _ repo: ChatRepository) async -> Bool {
        if cached[key] == true { return true }
        let hit = await repo.isAttachmentCached(accountId: key.accountId, content: key.content)
        if hit { cached[key] = true }
        return hit
    }

    /// Downloads the attachment (with progress) and returns its local path. Nil while another call is already downloading it.
    /// A cancelled download comes back as `.failure(.cancelled)` — nothing to report.
    func download(_ key: TransferKey, _ repo: ChatRepository) async -> Outcome<String>? {
        guard running[key] == nil else { return nil }
        running[key] = 0
        let watcher = Task { [weak self] in
            for await p in repo.watchDownloadProgress(accountId: key.accountId, content: key.content) {
                // A late tick after the download ended must not bring the entry back.
                if self?.running[key] != nil { self?.running[key] = p }
            }
        }
        let result = await repo.attachmentFile(accountId: key.accountId, content: key.content)
        watcher.cancel()
        running[key] = nil
        if case .success = result { cached[key] = true }
        return result
    }

    func cancel(_ key: TransferKey, _ repo: ChatRepository) { repo.cancelDownload(accountId: key.accountId, content: key.content) }
}

enum AttachmentActions {
    /// Shows a local file in Finder.
    static func reveal(path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }

    /// Asks where to save and copies the attachment there (`saveAttachmentCopy`); nil on cancel.
    @MainActor
    static func saveAs(_ key: TransferKey, name: String, _ repo: ChatRepository) async -> Outcome<Void>? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return await repo.saveAttachmentCopy(accountId: key.accountId, content: key.content, targetPath: url.path)
    }

    /// Copies the attachment into the Downloads folder, under a name not taken there, downloading it first; the path it
    /// got. Nil when it is being downloaded by another call already.
    @MainActor
    static func saveToDownloads(_ key: TransferKey, name: String, _ repo: ChatRepository) async -> Outcome<String>? {
        switch await AttachmentTransfers.shared.download(key, repo) {
        case nil: return nil
        case .failure(let f)?: return .failure(f)
        case .success?: break
        }
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
        let free = freeName(name) { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
        let target = folder.appendingPathComponent(free).path
        switch await repo.saveAttachmentCopy(accountId: key.accountId, content: key.content, targetPath: target) {
        case .success: return .success(target)
        case .failure(let f): return .failure(f)
        }
    }

    /// `name` as a file name, or "name (2).ext", "name (3).ext"... - the first one `taken` does not hold, so a copy never
    /// replaces a file already there.
    static func freeName(_ name: String, taken: (String) -> Bool) -> String {
        let safe = name.map { "/:".contains($0) ? "_" : $0 }.reduce(into: "") { $0.append($1) }.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = safe.isEmpty ? "file" : safe
        guard taken(base) else { return base }
        let ext = (base as NSString).pathExtension, stem = (base as NSString).deletingPathExtension
        var n = 2
        while true {
            let next = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            if !taken(next) { return next }
            n += 1
        }
    }

    /// The file or its saved copy in Finder; downloads first when needed.
    @MainActor
    static func reveal(_ key: TransferKey, _ repo: ChatRepository) async -> Outcome<Void> {
        if let saved = await repo.savedAttachmentCopy(accountId: key.accountId, content: key.content) { reveal(path: saved); return .success(()) }
        switch await AttachmentTransfers.shared.download(key, repo) {
        case .success(let path)?: reveal(path: path); return .success(())
        case .failure(let f)?: return .failure(f)
        case nil: return .success(())
        }
    }

    static func name(of content: MessageContent) -> String {
        switch content { case .image(let i): i.name; case .file(let f): f.name; default: "" }
    }

    static func byteCount(_ bytes: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
}
