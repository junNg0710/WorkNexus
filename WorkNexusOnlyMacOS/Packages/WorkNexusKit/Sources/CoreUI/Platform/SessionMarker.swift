/// Not in the Flutter app.
import Foundation

/// The file that says a session of the app is running: made at launch, touched every minute, removed at quit. A marker
/// still there at the next launch is a session that never quit - a crash, a forced quit or a restart - and its dates say
/// when that session started and when it was last alive.
public struct SessionMarker: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// The session that left the marker behind; nil when the last session quit.
    public func previous() -> (started: Date, lastSeen: Date)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let started = attributes[.creationDate] as? Date else { return nil }
        return (started, attributes[.modificationDate] as? Date ?? started)
    }

    /// A new session starts: a fresh marker (made anew, so its creation date is this launch).
    public func begin() {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: url)
        fm.createFile(atPath: url.path, contents: nil)
    }

    /// Still alive.
    public func touch(now: Date = Date()) {
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
    }

    /// The session quits.
    public func end() { try? FileManager.default.removeItem(at: url) }

    /// The log's line about a session that never quit. A marker never touched (a version without the heartbeat) says
    /// only when the session started.
    public static func describe(started: Date, lastSeen: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var line = "The previous session ended without quitting (a crash, a forced quit or a restart). It started at \(format.string(from: started))"
        if lastSeen.timeIntervalSince(started) > 5 { line += " and was last alive at \(format.string(from: lastSeen))" }
        return line
    }
}
