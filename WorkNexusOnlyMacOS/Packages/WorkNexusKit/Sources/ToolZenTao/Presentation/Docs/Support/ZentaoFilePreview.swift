/// Ported from: lib/tools/zentao/presentation/util/zentao_file_preview.dart
import CoreDomain
import Foundation

/// How an attached file can be shown in place, if at all.
public enum ZentaoFilePreview: Equatable, Sendable {
    case markdown, text, image, none

    private static let markdownExts: Set<String> = ["md", "markdown"]
    private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp"]
    private static let textExts: Set<String> = [
        "txt", "log", "json", "yaml", "yml", "xml", "csv", "tsv", "sql", "ini", "toml", "env", "sh", "proto", "go", "dart",
        "js", "ts", "java", "kt", "swift", "py", "rb", "php", "html", "css",
    ]

    /// What `file` previews as. The name's own extension wins over the one ZenTao reports: it files a `.md` upload as
    /// `txt`, which would show the Markdown as raw text.
    public static func of(_ file: TicketAttachment) -> ZentaoFilePreview {
        for ext in [extensionOf(file.title), file.extension?.lowercased()] {
            guard let ext else { continue }
            if markdownExts.contains(ext) { return .markdown }
            if imageExts.contains(ext) { return .image }
            if textExts.contains(ext) { return .text }
        }
        return .none
    }

    private static func extensionOf(_ name: String) -> String? {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex, name.index(after: dot) != name.endIndex else { return nil }
        return name[name.index(after: dot)...].lowercased()
    }
}
