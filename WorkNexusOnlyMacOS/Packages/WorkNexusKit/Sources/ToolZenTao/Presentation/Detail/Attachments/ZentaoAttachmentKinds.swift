/// Ported from: lib/tools/zentao/presentation/util/zentao_file_preview.dart
import CoreDomain
import Foundation

/// How an attached file can be shown in place, if at all.
public enum ZentaoAttachmentPreview: Equatable { case markdown, text, image, video, none }

public enum ZentaoFileKinds {
    static let markdown: Set<String> = ["md", "markdown"]
    static let image: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic"]
    static let video: Set<String> = ["mp4", "mov", "m4v", "webm", "avi", "mkv"]
    /// What the in-app player plays (the rest opens in another app).
    static let playable: Set<String> = ["mp4", "mov", "m4v"]
    static let text: Set<String> = [
        "txt", "log", "json", "yaml", "yml", "xml", "csv", "tsv", "sql", "ini", "toml", "env", "sh", "proto", "go", "dart",
        "js", "ts", "java", "kt", "swift", "py", "rb", "php", "html", "css",
    ]

    /// What `file` previews as. The name's own extension wins over the one ZenTao reports: it files a `.md` upload as
    /// `txt`, which would show the Markdown as raw text.
    public static func preview(of file: TicketAttachment) -> ZentaoAttachmentPreview {
        for ext in [extensionOf(file.title), file.`extension`?.lowercased()] {
            guard let ext else { continue }
            if markdown.contains(ext) { return .markdown }
            if image.contains(ext) { return .image }
            // Any video: the player plays what AVFoundation can and offers "open in another app" for the rest.
            if video.contains(ext) { return .video }
            if text.contains(ext) { return .text }
        }
        return .none
    }

    /// The lower-cased extension of a file name, nil when it has none.
    public static func extensionOf(_ name: String) -> String? {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex, name.index(after: dot) != name.endIndex else { return nil }
        return name[name.index(after: dot)...].lowercased()
    }

    /// The extension the attachment goes by (its name's, else ZenTao's).
    public static func ext(of file: TicketAttachment) -> String { extensionOf(file.title) ?? file.`extension`?.lowercased() ?? "" }

    /// Whether the viewer can show it (image, video it can play, text, Markdown).
    public static func isViewable(_ file: TicketAttachment) -> Bool { preview(of: file) != .none }

    /// The SF Symbol of an attachment's kind.
    public static func icon(of file: TicketAttachment) -> String {
        let e = ext(of: file)
        if video.contains(e) { return "video" }
        if image.contains(e) { return "photo" }
        if e == "pdf" { return "doc.text" }
        if ["zip", "rar", "7z"].contains(e) { return "doc.zipper" }
        return "doc"
    }
}

/// Saves files to the user's Downloads folder.
public enum ZentaoDownloads {
    /// A file name in `directory` that is not taken: `shot.png`, `shot 2.png`, ...
    public static func freeName(_ name: String, in directory: URL, fm: FileManager = .default) -> String {
        let safe = name.replacingOccurrences(of: "/", with: "_")
        guard fm.fileExists(atPath: directory.appendingPathComponent(safe).path) else { return safe }
        let ns = safe as NSString
        let stem = ns.deletingPathExtension, ext = ns.pathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            if !fm.fileExists(atPath: directory.appendingPathComponent(candidate).path) { return candidate }
            n += 1
        }
    }

    /// Writes `data` as `name` into `directory` (Downloads by default); returns the saved path.
    public static func save(_ data: Data, as name: String, in directory: URL? = nil) -> String? {
        let fm = FileManager.default
        guard let dir = directory ?? fm.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return nil }
        let url = dir.appendingPathComponent(freeName(name, in: dir, fm: fm))
        do { try data.write(to: url); return url.path } catch { return nil }
    }
}
