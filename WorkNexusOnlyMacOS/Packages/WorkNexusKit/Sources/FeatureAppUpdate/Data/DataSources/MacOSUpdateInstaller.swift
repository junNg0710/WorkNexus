import Foundation

/// Ported from: lib/features/app_update/data/datasources/macos_update_installer.dart
/// Swaps `WorkNexus.app` in place. The bundle is moved aside first, so a failed move puts the old one back
/// rather than leaving no app at all.
public struct MacOSUpdateInstaller: UpdateInstaller {
    public let assetName: String
    public let installPath: String

    /// `$1` pid to wait for, `$2` installed .app, `$3` new .app, `$4` log file. It gives up, leaving the installed app as it
    /// is, when the app has not quit after `waitLimit` seconds (a quit that never finished must not leave a helper behind).
    /// `WN_UPDATE_NO_OPEN=1` skips reopening (tests).
    static let waitLimit = 300
    static let script = #"""
    #!/bin/sh
    exec >>"$4" 2>&1
    echo "== $(date) install $3 over $2 once $1 quits"
    set -x
    waited=0
    while kill -0 "$1" 2>/dev/null; do
      sleep 0.3
      waited=$((waited + 1))
      if [ "$waited" -gt \#(waitLimit * 10 / 3) ]; then echo "the app did not quit: update not installed"; exit 1; fi
    done
    backup="$2.previous"
    rm -rf "$backup"
    if mv "$2" "$backup"; then
      if mv "$3" "$2"; then
        rm -rf "$backup"
      else
        mv "$backup" "$2"
      fi
    fi
    [ "$WN_UPDATE_NO_OPEN" = 1 ] || open "$2"

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
        try Self.spawnDetached(["/bin/sh", script, "\(ProcessInfo.processInfo.processIdentifier)", installPath, stagedPath,
                                (scriptDir as NSString).appendingPathComponent("update.log")])
    }

    /// Starts `arguments` in a session of its own (`setsid`), so whatever ends this app (a quit, a forced quit) does
    /// not end the helper with it.
    static func spawnDetached(_ arguments: [String], environment: [String: String]? = nil) throws {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for fd: Int32 in 0...2 { posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0) }
        let env = (environment ?? ProcessInfo.processInfo.environment).map { "\($0.key)=\($0.value)" }
        let argv = arguments.map { strdup($0) } + [nil], envp = env.map { strdup($0) } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, arguments[0], &actions, &attr, argv, envp)
        if status != 0 { throw POSIXError(POSIXErrorCode(rawValue: status) ?? .EPERM) }
    }
}
