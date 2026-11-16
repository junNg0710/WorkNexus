import Foundation

/// The on-disk attachment cache (`~/Library/Caches/<bundle>/chat_files/<account>/<name>`), trimmed least-recently-used
/// down to 90 % of the limit once it exceeds it.
/// Ported from: lib/features/chat/data/datasources/chat_file_cache.dart
final class ChatFileCache: @unchecked Sendable {
    static let defaultMaxBytes = 2 * 1024 * 1024 * 1024

    private let root: URL
    private let state: Locked<(max: Int, lastTrim: Date?, trimming: Bool)>
    private let trimEvery: TimeInterval
    private let now: @Sendable () -> Date

    init(root: URL, maxBytes: Int = defaultMaxBytes, trimEvery: TimeInterval = 600, now: @escaping @Sendable () -> Date = Date.init) {
        self.root = root; self.trimEvery = trimEvery; self.now = now
        state = Locked((maxBytes, nil, false))
    }

    static func appDefault() -> ChatFileCache {
        let base = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return ChatFileCache(root: base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.worknexus.macos", isDirectory: true)
            .appendingPathComponent("chat_files", isDirectory: true))
    }

    var maxBytes: Int {
        get { state.current.max }
        set {
            guard newValue > 0 else { return }
            let shrinking = state.with { s -> Bool in if s.max == newValue { return false }; let shrink = newValue < s.max; s.max = newValue; return shrink }
            if shrinking { Task { await trim() } }
        }
    }

    static func diskName(_ name: String) -> String {
        String(name.unicodeScalars.map { "/\\:*?\"<>|".unicodeScalars.contains($0) || $0.value < 0x20 ? "_" : Character($0) })
    }

    func fileURL(_ accountId: String, _ name: String) -> URL {
        root.appendingPathComponent(Self.diskName(accountId), isDirectory: true).appendingPathComponent(Self.diskName(name))
    }

    /// The cached file (touched so trimming keeps it), nil when absent or empty.
    func open(_ accountId: String, _ name: String) -> URL? {
        let url = fileURL(accountId, name)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int), size > 0 else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
        return url
    }

    func read(_ accountId: String, _ name: String) -> Data? { open(accountId, name).flatMap { try? Data(contentsOf: $0) } }

    /// Writes beside and renames, so a crash never leaves a truncated file later reads would take for the real one.
    @discardableResult
    func write(_ accountId: String, _ name: String, _ bytes: Data) -> URL? {
        let url = fileURL(accountId, name)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let part = url.appendingPathExtension("part")
            try bytes.write(to: part, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            try FileManager.default.moveItem(at: part, to: url)
            try FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
        } catch { return nil }
        trimSoon()
        return url
    }

    /// Moves a finished file (a video recorded while it played) into the cache under `name`.
    @discardableResult
    func adopt(_ accountId: String, _ name: String, moving source: URL) -> URL? {
        let url = fileURL(accountId, name)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            try FileManager.default.moveItem(at: source, to: url)
            try FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
        } catch { try? FileManager.default.removeItem(at: source); return nil }
        trimSoon()
        return url
    }

    func trimSoon() {
        let due = state.with { s -> Bool in
            if let last = s.lastTrim, now().timeIntervalSince(last) < trimEvery { return false }
            s.lastTrim = now(); return true
        }
        if due { Task { await trim() } }
    }

    func trim() async {
        let go = state.with { s -> Bool in if s.trimming { return false }; s.trimming = true; return true }
        guard go else { return }
        defer { state.with { $0.trimming = false } }
        var entries = allFiles()
        var total = entries.reduce(0) { $0 + $1.size }
        let limit = maxBytes
        guard total > limit else { return }
        entries.sort { $0.used < $1.used }
        let target = limit * 9 / 10
        for e in entries {
            if total <= target { break }
            if (try? FileManager.default.removeItem(at: e.url)) != nil { total -= e.size }
        }
    }

    private func allFiles(in dir: URL? = nil) -> [(url: URL, size: Int, used: Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: dir ?? root, includingPropertiesForKeys: keys) else { return [] }
        return (e.allObjects as? [URL] ?? []).compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { return nil }
            return (url, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
        }
    }

    /// File name → size for one account.
    func sizes(_ accountId: String) -> [String: Int] {
        let dir = root.appendingPathComponent(Self.diskName(accountId), isDirectory: true)
        var out: [String: Int] = [:]
        for f in allFiles(in: dir) { out[f.url.lastPathComponent] = f.size }
        return out
    }

    func totalBytes() -> Int { allFiles().reduce(0) { $0 + $1.size } }

    func delete(_ accountId: String, _ names: [String]) {
        for n in names { try? FileManager.default.removeItem(at: fileURL(accountId, n)) }
    }

    func clear() { try? FileManager.default.removeItem(at: root) }
}
