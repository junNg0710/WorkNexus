import Foundation

/// Where the shell keeps which workspace the user joined, so a restart opens the same one. (The Flutter app holds this in
/// memory only and falls back to the first workspace every launch; here it is remembered.)
public protocol ActiveWorkspaceStoring: Sendable {
    func load() -> String?
    func save(_ workspaceId: String?)
}

/// Nothing is remembered (tests, previews, the default of a bare `ShellModel`).
public struct NoActiveWorkspaceStore: ActiveWorkspaceStoring {
    public init() {}
    public func load() -> String? { nil }
    public func save(_ workspaceId: String?) {}
}

/// The id in a small text file of the support folder (`active_workspace.txt`). A missing / unreadable file is "no choice".
public struct FileActiveWorkspaceStore: ActiveWorkspaceStoring {
    private let file: URL
    public init(file: URL) { self.file = file }

    public func load() -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let id = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    public func save(_ workspaceId: String?) {
        do {
            if let workspaceId {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try workspaceId.write(to: file, atomically: true, encoding: .utf8)
            } else if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        } catch {}   // cosmetic: the choice just is not remembered
    }
}
