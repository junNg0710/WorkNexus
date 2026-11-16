import Foundation

/// Ported from: lib/features/mini_apps/data/datasources/mini_app_icon_storage.dart (+ mini_app_icon_store.dart)
/// The icon image files of the mini apps, one per app, in a folder of the app's support directory. A file's name carries
/// a timestamp so a replaced icon is a new path (views cache images by path).
public protocol MiniAppIconStore: Sendable {
    /// Keeps `data` as app `id`'s icon, replacing any earlier one; the file's path.
    func save(id: String, data: Data, fileExtension: String) throws -> String
    /// Copies the image at `sourcePath` in as app `id`'s icon.
    func importFile(id: String, sourcePath: String) throws -> String
    /// Removes every icon file kept for app `id`.
    func delete(id: String)
}

public struct MiniAppIconStorage: MiniAppIconStore {
    private let folder: URL
    public init(folder: URL) { self.folder = folder }

    public func save(id: String, data: Data, fileExtension: String) throws -> String {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        delete(id: id)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let file = folder.appendingPathComponent("\(id)_\(stamp).\(fileExtension)")
        try data.write(to: file, options: .atomic)
        return file.path
    }

    public func importFile(id: String, sourcePath: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
        let ext = (sourcePath as NSString).pathExtension.lowercased()
        return try save(id: id, data: data, fileExtension: ext.isEmpty ? "png" : ext)
    }

    public func delete(id: String) {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for e in entries where e.lastPathComponent.hasPrefix("\(id)_") { try? FileManager.default.removeItem(at: e) }
    }
}
