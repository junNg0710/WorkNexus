import Foundation

/// Copies the MCP server the app bundles (`Mcp/worknexus-mcp.mjs` in its resources) to a fixed file AI tools can be pointed
/// at: the copy inside the app bundle moves with the app and is replaced on every update, so it cannot be registered directly.
/// Ported from: lib/features/chat/data/datasources/mcp_script_installer.dart
struct McpScriptInstaller: Sendable {
    static let fileName = "worknexus-mcp.mjs"

    /// The bundled script; nil when this build has none.
    let source: URL?
    /// Where the copy goes (`<app support>/mcp`).
    let directory: URL

    enum InstallError: Error { case notBundled }

    var installedFile: URL { directory.appendingPathComponent(Self.fileName) }

    /// The installed script's path. Rewrites it only when this build bundles a different version, so a tool running it is
    /// not disturbed for nothing.
    func install() throws -> String { try write(installedFile) }

    /// Brings a copy installed earlier up to this build's version, so AI tools registered before an app update run the new
    /// server; nil (and nothing written) when the user never set one up.
    func refresh() throws -> String? {
        FileManager.default.fileExists(atPath: installedFile.path) ? try write(installedFile) : nil
    }

    private func write(_ file: URL) throws -> String {
        guard let source, let bytes = try? Data(contentsOf: source) else { throw InstallError.notBundled }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let existing = try? Data(contentsOf: file), existing == bytes { return file.path }
        try bytes.write(to: file, options: .atomic)
        // The script starts with `#!/usr/bin/env node`; executable, so it can also be run as a command.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file.path
    }
}
