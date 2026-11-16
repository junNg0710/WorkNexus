import CoreDomain
import Foundation

/// Ported from: lib/features/app_update/data/repositories/local_auto_update_preference.dart (+ auto_update_marker_file.dart)
/// The choice kept as a marker file: present means automatic updates are off, so a build that never saved the choice
/// behaves as before (on).
public struct MarkerFileAutoUpdatePreference: AutoUpdatePreference {
    private let file: URL

    public init(file: URL) { self.file = file }

    /// `~/Library/Application Support/<bundle id>/auto_update.txt`
    public static func inApplicationSupport(bundleId: String = Bundle.main.bundleIdentifier ?? "com.worknexus.macos") -> Self {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return Self(file: base.appendingPathComponent(bundleId, isDirectory: true).appendingPathComponent("auto_update.txt"))
    }

    public func isEnabled() async -> Outcome<Bool> { .success(!FileManager.default.fileExists(atPath: file.path)) }

    public func setEnabled(_ enabled: Bool) async -> Outcome<Void> {
        let fm = FileManager.default
        do {
            if enabled {
                if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
            } else {
                try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try "off".write(to: file, atomically: true, encoding: .utf8)
            }
            return .success(())
        } catch {
            return .failure(.storage("Could not save the automatic update choice"))
        }
    }
}
