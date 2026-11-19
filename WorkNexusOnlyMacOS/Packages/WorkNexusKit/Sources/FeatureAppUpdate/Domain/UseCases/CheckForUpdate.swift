import CoreDomain

/// Ported from: lib/features/app_update/domain/usecases/check_for_update.dart
public struct CheckForUpdate: Sendable {
    private let repository: UpdateRepository
    public init(_ repository: UpdateRepository) { self.repository = repository }

    public func callAsFunction() async -> Outcome<AvailableUpdate?> {
        switch await repository.fetchLatestStableRelease() {
        case .failure(let f): return .failure(f)
        case .success(nil): return .success(nil)
        case .success(let s?):
            guard let current = AppVersion(s.currentVersion), let latest = AppVersion(s.latestVersion) else {
                return .failure(.parse("GitHub returned an invalid stable release version"))
            }
            // A tag with a pre-release suffix but `prerelease: false` on GitHub is "no stable update", not an error.
            if latest.isPrerelease || latest <= current { return .success(nil) }
            // The notes of every release since the running one, not only the latest's: jumping from 1.0 to 1.9 shows
            // what all of them brought. The latest's own notes stay when the others cannot be read.
            let since = await CollectReleaseNotes(repository)(after: s.currentVersion, upTo: s.latestVersion).value ?? ""
            return .success(AvailableUpdate(
                currentVersion: s.currentVersion, latestVersion: s.latestVersion, releaseUrl: s.releaseUrl,
                releaseNotes: since.isEmpty ? s.releaseNotes : since, downloadUrl: s.downloadUrl, sha256: s.sha256))
        }
    }
}
