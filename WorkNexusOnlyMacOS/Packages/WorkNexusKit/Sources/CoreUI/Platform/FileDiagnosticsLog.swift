/// Not in the Flutter app.
import CoreDomain
import Foundation
import os

/// The diagnostics log as plain-text files on this Mac (`<Application Support>/Logs`), also mirrored to the system log
/// (Console.app, subsystem `com.worknexus`). The file grows to `maxBytes`, then becomes `worknexus.1.log` (and so on, up
/// to `keptFiles`); files older than `maxAge` are removed.
public final class FileDiagnosticsLog: DiagnosticsSink, @unchecked Sendable {
    public let directory: URL
    public let maxBytes: Int
    public let keptFiles: Int
    public let maxAge: TimeInterval
    private let queue = DispatchQueue(label: "com.worknexus.diagnostics")
    private let now: @Sendable () -> Date

    public static let fileName = "worknexus.log"
    public var currentFile: URL { directory.appendingPathComponent(Self.fileName) }

    public init(directory: URL, maxBytes: Int = 1_000_000, keptFiles: Int = 5, maxAge: TimeInterval = 7 * 24 * 3600,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory; self.maxBytes = maxBytes; self.keptFiles = keptFiles; self.maxAge = maxAge; self.now = now
        queue.async { [self] in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            pruneOld()
        }
    }

    public func write(_ entry: DiagnosticEntry, trail: [String]) {
        let logger = Logger(subsystem: "com.worknexus", category: entry.area)
        switch entry.level {
        case .error: logger.error("\(entry.message, privacy: .public)")
        case .warning: logger.warning("\(entry.message, privacy: .public)")
        case .info: logger.info("\(entry.message, privacy: .public)")
        }
        let text = Self.lines(entry, trail: trail)
        queue.async { [self] in append(text) }
    }

    public func flush() { queue.sync {} }

    /// Every log file, newest first.
    public func files() -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return all.filter { $0.lastPathComponent.hasPrefix("worknexus") || $0.pathExtension == "json" }
            .sorted { modified($0) > modified($1) }
    }

    /// How much the logs take on disk.
    public func totalBytes() -> Int {
        files().reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Removes every log (the user's "Clear").
    public func clear() {
        queue.sync { for f in files() { try? FileManager.default.removeItem(at: f) } }
    }

    // MARK: Writing

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZ"
        return f
    }()

    static func lines(_ e: DiagnosticEntry, trail: [String]) -> String {
        var out = "\(stamp.string(from: e.date))  \(e.level.rawValue.uppercased().padding(toLength: 7, withPad: " ", startingAt: 0))[\(e.area)] \(e.message)\n"
        if !trail.isEmpty { out += "    after: \(trail.joined(separator: " › "))\n" }
        return out
    }

    private func append(_ text: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if let size = try? currentFile.resourceValues(forKeys: [.fileSizeKey]).fileSize, size + text.utf8.count > maxBytes { rotate() }
        let data = Data(text.utf8)
        if let handle = try? FileHandle(forWritingTo: currentFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: currentFile)
        }
    }

    /// worknexus.log → worknexus.1.log → … ; the oldest beyond `keptFiles` goes.
    private func rotate() {
        let fm = FileManager.default
        func numbered(_ i: Int) -> URL { directory.appendingPathComponent("worknexus.\(i).log") }
        try? fm.removeItem(at: numbered(keptFiles - 1))
        if keptFiles > 1 {
            for i in stride(from: keptFiles - 2, through: 1, by: -1) where fm.fileExists(atPath: numbered(i).path) {
                try? fm.moveItem(at: numbered(i), to: numbered(i + 1))
            }
        }
        try? fm.moveItem(at: currentFile, to: numbered(1))
    }

    private func pruneOld() {
        let limit = now().addingTimeInterval(-maxAge)
        for f in files() where f != currentFile && modified(f) < limit { try? FileManager.default.removeItem(at: f) }
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

/// Packs the logs and a description of this Mac into one zip to attach to a bug report.
public enum DiagnosticsArchive {
    /// Writes `<logs> + about.txt` as a zip at `destination` (replacing it).
    public static func export(logs: [URL], about: String, to destination: URL) throws {
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("WorkNexus-diagnostics-\(UUID().uuidString)", isDirectory: true)
        let folder = stage.appendingPathComponent("WorkNexus diagnostics", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        for log in logs where fm.fileExists(atPath: log.path) {
            try fm.copyItem(at: log, to: folder.appendingPathComponent(log.lastPathComponent))
        }
        try Data(about.utf8).write(to: folder.appendingPathComponent("about.txt"))
        var failure: Error?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinatorError) { zip in
            do {
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.copyItem(at: zip, to: destination)
            } catch { failure = error }
        }
        if let e = coordinatorError ?? failure { throw e }
    }

    /// The app's version and this Mac's system, for `about.txt`.
    public static func about(now: Date = Date()) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?", build = info["CFBundleVersion"] as? String ?? "?"
        var sys = utsname(); uname(&sys)
        let arch = withUnsafeBytes(of: &sys.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return """
        WorkNexus Mac \(version) (\(build))
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(arch)
        Exported \(ISO8601DateFormatter().string(from: now))
        """
    }
}
