import Foundation

/// Ported from: lib/features/app_update/data/datasources/update_installer.dart
/// Platform half of an update: unpacking a downloaded build and swapping it in for the running one.
public protocol UpdateInstaller: Sendable {
    /// The release asset holding this platform's build.
    var assetName: String { get }
    /// Where the running build lives (the `.app`), which `launchSwap` replaces.
    var installPath: String { get }
    /// Unpacks `zipPath` into `directory` and returns the new `.app`'s path.
    func unpack(zipPath: String, into directory: String) throws -> String
    /// Starts a detached helper that waits for this process to exit, replaces `installPath` with `stagedPath` and reopens.
    func launchSwap(stagedPath: String, scriptDir: String) throws
    /// Whether the swap can write where the app bundle lives.
    func canReplace() -> Bool
}

public extension UpdateInstaller {
    /// The folder the swap writes into: where the app bundle is moved within.
    var writableDirectory: String { (installPath as NSString).deletingLastPathComponent }

    /// Whether `writableDirectory` can be changed by this user; it cannot when the app was installed by an admin or
    /// runs translocated.
    func isWritableDirectory() -> Bool {
        let probe = (writableDirectory as NSString).appendingPathComponent(".worknexus-update-probe")
        guard FileManager.default.createFile(atPath: probe, contents: Data()) else { return false }
        try? FileManager.default.removeItem(atPath: probe)
        return true
    }

    func canReplace() -> Bool { isWritableDirectory() }
}

struct ProcessFailure: Error, CustomStringConvertible {
    let executable: String; let status: Int32; let stderr: String
    var description: String { "\(executable) exited \(status): \(stderr)" }
}

/// Runs `executable` and throws when it fails, so callers map one error.
func runChecked(_ executable: String, _ arguments: [String]) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = arguments
    let err = Pipe()
    p.standardError = err
    p.standardOutput = FileHandle.nullDevice
    try p.run()
    let data = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    if p.terminationStatus != 0 {
        throw ProcessFailure(executable: executable, status: p.terminationStatus,
                             stderr: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
