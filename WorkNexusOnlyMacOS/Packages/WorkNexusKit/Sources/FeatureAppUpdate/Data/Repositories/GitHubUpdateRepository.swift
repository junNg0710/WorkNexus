import CoreDomain
import Foundation

/// Ported from: lib/features/app_update/data/repositories/github_update_repository.dart
/// Updates from the repository's GitHub Releases: the archive CI attaches for this platform, checked against the
/// release's checksum file.
public final class GitHubUpdateRepository: UpdateRepository, @unchecked Sendable {
    private let releases: GitHubReleaseSource
    /// Nil on a platform with no in-app install: updates then only point at the release page.
    private let installer: UpdateInstaller?
    private let config: AppUpdateConfig
    private let version: String
    private let stagingRoot: @Sendable () throws -> URL
    private let quit: @Sendable () -> Void

    public init(releases: GitHubReleaseSource, installer: UpdateInstaller?, config: AppUpdateConfig, currentVersion: String,
                stagingRoot: @escaping @Sendable () throws -> URL = GitHubUpdateRepository.defaultStagingRoot,
                quit: @escaping @Sendable () -> Void = { exit(0) }) {
        self.releases = releases; self.installer = installer; self.config = config; self.version = currentVersion
        self.stagingRoot = stagingRoot; self.quit = quit
    }

    public static let defaultStagingRoot: @Sendable () throws -> URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("worknexus_update", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func currentVersion() -> String { version }

    public func fetchLatestStableRelease() async -> Outcome<UpdateVersionSnapshot?> {
        do {
            let release = try await releases.fetchLatestStableRelease()
            let assetName = installer?.assetName
            let downloadUrl = assetName.flatMap { Self.assetUrl(release.assets, $0) }
            let sumsUrl = Self.assetUrl(release.assets, config.checksumsAsset)
            var sha: String?
            if let assetName, downloadUrl != nil, let sumsUrl {
                sha = Self.checksumFor(assetName, sums: try await releases.readText(sumsUrl))
            }
            return .success(UpdateVersionSnapshot(
                currentVersion: version, latestVersion: release.tagName, releaseUrl: release.htmlUrl,
                releaseNotes: release.notes,
                // Never offer a download that cannot be verified.
                downloadUrl: sha == nil ? nil : downloadUrl, sha256: sha))
        } catch let e as ReleaseHTTPError where e.status == 404 {
            return .success(nil)
        } catch is ReleaseFormatError {
            return .failure(.parse("Could not read the latest release"))
        } catch is CancellationError {
            return .failure(.cancelled("cancelled"))
        } catch let e as ReleaseHTTPError {
            return .failure(.network("Could not check for updates (HTTP \(e.status))"))
        } catch is URLError {
            return .failure(.network("Could not check for updates"))
        } catch {
            return .failure(.unexpected("Could not check for updates: \(error)"))
        }
    }

    public func fetchStableReleaseNotes() async -> Outcome<[ReleaseNote]> {
        do {
            return .success(try await releases.fetchStableReleases()
                .filter { config.isOwnRelease($0.tagName) }
                .map { ReleaseNote(version: $0.tagName, notes: $0.notes) })
        } catch is ReleaseFormatError {
            return .failure(.parse("Could not read the release notes"))
        } catch is CancellationError {
            return .failure(.cancelled("cancelled"))
        } catch let e as ReleaseHTTPError {
            return .failure(.network("Could not read the release notes (HTTP \(e.status))"))
        } catch is URLError {
            return .failure(.network("Could not read the release notes"))
        } catch {
            return .failure(.unexpected("Could not read the release notes: \(error)"))
        }
    }

    public func download(_ update: AvailableUpdate, onProgress: @escaping @Sendable (Double) -> Void) async -> Outcome<String> {
        guard let installer, let url = update.downloadUrl, let expected = update.sha256 else {
            return .failure(.unexpected("This update cannot be installed"))
        }
        let fm = FileManager.default
        do {
            let dir = try stagingRoot().appendingPathComponent(update.latestVersion, isDirectory: true)
            // A leftover from an interrupted try would mix two builds.
            if fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)

            let zip = dir.appendingPathComponent(installer.assetName).path
            try await releases.downloadFile(url, to: zip, onProgress: onProgress)
            let actual = try releases.sha256Of(zip)
            if actual != expected.lowercased() {
                try? fm.removeItem(at: dir)
                return .failure(.parse("Checksum mismatch for \(update.latestVersion): expected \(expected), got \(actual)"))
            }
            let unpacked = dir.appendingPathComponent("build", isDirectory: true)
            try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
            return .success(try installer.unpack(zipPath: zip, into: unpacked.path))
        } catch is CancellationError {
            return .failure(.cancelled("cancelled"))
        } catch is URLError {
            return .failure(.network("Downloading the update failed"))
        } catch is ReleaseHTTPError {
            return .failure(.network("Downloading the update failed"))
        } catch {
            // Includes a failed unpack (ProcessFailure) and file errors.
            return .failure(.storage("Preparing the update failed: \(error)"))
        }
    }

    public func install(stagedPath: String) async -> Outcome<Void> {
        guard let installer else { return .failure(.unexpected("This update cannot be installed")) }
        guard installer.canReplace() else {
            return .failure(.storage("No write access to \((installer.installPath as NSString).deletingLastPathComponent)"))
        }
        do {
            try installer.launchSwap(stagedPath: stagedPath, scriptDir: try stagingRoot().path)
        } catch {
            return .failure(.storage("Starting the installer failed: \(error)"))
        }
        quit()
        return .success(())
    }

    /// The download URL of the asset called `name`; matched case-insensitively, as GitHub treats asset names.
    static func assetUrl(_ assets: [String: String], _ name: String) -> String? {
        let wanted = name.lowercased()
        return assets.first { $0.key.lowercased() == wanted }?.value
    }

    /// The hash on the `<sha256>  <name>` line for `asset`, as `sha256sum` writes it; nil when not listed.
    static func checksumFor(_ asset: String, sums: String) -> String? {
        let wanted = asset.lowercased()
        for line in sums.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard parts.count == 2 else { continue }
            var name = String(parts[1])
            if name.hasPrefix("*") { name.removeFirst() }
            if name.lowercased() == wanted { return parts[0].lowercased() }
        }
        return nil
    }
}
