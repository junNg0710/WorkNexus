import Foundation

/// Ported from: lib/core/util/dropped_files.dart
/// A file dragged in from the OS: its name and contents.
public struct DroppedFile: Sendable, Equatable {
    public var name: String
    public var bytes: Data
    public init(name: String, bytes: Data) { self.name = name; self.bytes = bytes }
}

public enum DroppedFiles {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp"]

    /// Whether `name` is an image the rich-text editor can show inline.
    public static func isInlineImageName(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: ".") else { return false }
        return imageExtensions.contains(name[name.index(after: dot)...].lowercased())
    }

    /// `files` split into inline images and everything else, each in order.
    public static func split(_ files: [DroppedFile]) -> (images: [DroppedFile], others: [DroppedFile]) {
        (files.filter { isInlineImageName($0.name) }, files.filter { !isInlineImageName($0.name) })
    }

    /// Reads the files behind dropped file URLs (folders are skipped); nil when one of them cannot be read.
    public static func read(_ urls: [URL]) async -> [DroppedFile]? {
        await Task.detached(priority: .userInitiated) { () -> [DroppedFile]? in
            var out: [DroppedFile] = []
            for url in urls where url.isFileURL {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
                guard let data = try? Data(contentsOf: url) else { return nil }
                out.append(DroppedFile(name: url.lastPathComponent, bytes: data))
            }
            return out
        }.value
    }
}
