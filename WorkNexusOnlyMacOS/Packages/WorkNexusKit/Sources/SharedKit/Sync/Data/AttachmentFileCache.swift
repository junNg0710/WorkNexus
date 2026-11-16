import Foundation

/// Ported from: lib/shared/sync/data/attachment_file_cache.dart
/// On-disk cache for downloaded ticket attachments (repro videos, screenshots) so the viewer reads a local file.
/// `purge()` wipes the directory once at startup (per-session cache); `store` enforces `maxBytes` by evicting the
/// oldest files so one long session can't fill the disk.
public final class AttachmentFileCache: @unchecked Sendable {
    public let root: URL
    public let maxBytes: Int

    public init(root: URL? = nil, maxBytes: Int = 2 * 1024 * 1024 * 1024) {
        self.root = root ?? FileManager.default.temporaryDirectory.appendingPathComponent("worknexus_attachments", isDirectory: true)
        self.maxBytes = maxBytes
    }

    private func file(_ id: String, _ safeName: String) -> URL { root.appendingPathComponent("\(id)_\(safeName)") }

    /// The cached path for `id`+`safeName` if it is already on disk (non-empty), or nil when it needs downloading.
    public func existing(_ id: String, _ safeName: String) -> String? {
        let url = file(id, safeName)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0 ? url.path : nil
    }

    /// Writes `bytes`, evicts oldest files to stay under `maxBytes`, and returns the local path.
    public func store(_ id: String, _ safeName: String, _ bytes: Data) throws -> String {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = file(id, safeName)
        try bytes.write(to: url, options: .atomic)
        enforceCap()
        return url.path
    }

    /// Bytes the cached files take.
    public func sizeBytes() -> Int {
        entries().reduce(0) { $0 + $1.size }
    }

    /// Deletes the entire cache directory (best-effort).
    public func purge() { try? FileManager.default.removeItem(at: root) }

    private func entries() -> [(url: URL, size: Int, modified: Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys) else { return [] }
        return urls.compactMap { u in
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { return nil }
            return (u, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
        }
    }

    private func enforceCap() {
        var list = entries()
        var total = list.reduce(0) { $0 + $1.size }
        if total <= maxBytes { return }
        list.sort { $0.modified < $1.modified }   // oldest download first, so the fresh file survives
        for e in list where total > maxBytes {
            if (try? FileManager.default.removeItem(at: e.url)) != nil { total -= e.size }
        }
    }
}
