import Foundation

/// `chat_local_api.json`: how local tools reach the running API — `{version, port, token, pid}`. It sits beside the database,
/// where the bundled MCP server looks for it, and only the user may read it (mode 0600 from the moment it exists; written
/// to a temporary file, then renamed into place). The MCP server ignores a file whose `pid` is no longer running.
/// Ported from: lib/features/chat/data/datasources/chat_local_api_server.dart (`_writeDiscovery`)
enum LocalApiDiscoveryFile {
    static let fileName = "chat_local_api.json"

    static func url(in directory: URL) -> URL { directory.appendingPathComponent(fileName) }

    static func write(in directory: URL, port: UInt16, token: String, pid: Int32) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let info: [String: Any] = ["version": 1, "port": Int(port), "token": token, "pid": Int(pid)]
        let data = try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys])
        let target = url(in: directory), temp = directory.appendingPathComponent(fileName + ".tmp")
        try? FileManager.default.removeItem(at: temp)
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        // The umask cannot widen 0600, but a mode set explicitly leaves no doubt.
        let wrote = fchmod(fd, S_IRUSR | S_IWUSR) == 0 && data.withUnsafeBytes { raw in
            Darwin.write(fd, raw.baseAddress, raw.count) == raw.count
        } && fsync(fd) == 0
        close(fd)
        guard wrote, rename(temp.path, target.path) == 0 else {
            try? FileManager.default.removeItem(at: temp)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static func remove(in directory: URL) {
        try? FileManager.default.removeItem(at: url(in: directory))
    }
}
