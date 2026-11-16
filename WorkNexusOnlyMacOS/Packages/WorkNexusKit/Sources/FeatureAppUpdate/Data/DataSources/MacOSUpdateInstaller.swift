import Foundation

/// Ported from: lib/features/app_update/data/datasources/macos_update_installer.dart
/// Swaps `WorkNexus.app` in place. The bundle is moved aside first, so a failed move puts the old one back
/// rather than leaving no app at all.
public struct MacOSUpdateInstaller: UpdateInstaller {
    public let assetName: String
    public let installPath: String

    /// `$1` pid to wait for, `$2` installed .app, `$3` new .app, `$4` log file.
    static let script = #"""
    #!/bin/sh
    exec >>"$4" 2>&1
    set -x
    while kill -0 "$1" 2>/dev/null; do sleep 0.3; done
    backup="$2.previous"
    rm -rf "$backup"
    if mv "$2" "$backup"; then
      if mv "$3" "$2"; then
        rm -rf "$backup"
      else
        mv "$backup" "$2"
      fi
    fi
    open "$2"

    """#

    /// `installPath` defaults to the running bundle (`…/WorkNexus.app`).
    public init(assetName: String, installPath: String = Bundle.main.bundlePath) {
        self.assetName = assetName; self.installPath = installPath
    }

    public func canReplace() -> Bool { installPath.hasSuffix(".app") && isWritableDirectory() }

    public func unpack(zipPath: String, into directory: String) throws -> String {
        // ditto keeps the bundle's symlinks and signature intact; unzip does not.
        try runChecked("/usr/bin/ditto", ["-x", "-k", zipPath, directory])
        let entries = try FileManager.default.contentsOfDirectory(atPath: directory)
        guard let app = entries.first(where: { $0.hasSuffix(".app") }) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "The update holds no .app bundle"])
        }
        return (directory as NSString).appendingPathComponent(app)
    }

    public func launchSwap(stagedPath: String, scriptDir: String) throws {
        let script = (scriptDir as NSString).appendingPathComponent("install_update.sh")
        try Self.script.write(toFile: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script, "\(ProcessInfo.processInfo.processIdentifier)", installPath, stagedPath,
                       (scriptDir as NSString).appendingPathComponent("update.log")]
        // Detached: its own session so quitting this app does not take the helper with it.
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
    }
}
