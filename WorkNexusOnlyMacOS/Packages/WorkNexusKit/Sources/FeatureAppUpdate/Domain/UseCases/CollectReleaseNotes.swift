import CoreDomain

/// Ported from: lib/features/app_update/domain/usecases/collect_release_notes.dart
/// The notes of every stable release after `after` up to and including `upTo`, newest first, as one Markdown text with a
/// heading per version (`## v1.9.5`). Empty when none of them has notes.
public struct CollectReleaseNotes: Sendable {
    private let repository: UpdateRepository
    public init(_ repository: UpdateRepository) { self.repository = repository }

    public func callAsFunction(after: String, upTo: String) async -> Outcome<String> {
        await repository.fetchStableReleaseNotes().map { Self.combine($0, after: after, upTo: upTo) }
    }

    public static func combine(_ releases: [ReleaseNote], after: String, upTo: String) -> String {
        guard let from = AppVersion(after), let to = AppVersion(upTo) else { return "" }
        var seen = Set<AppVersion>()
        let picked = releases.compactMap { r -> (version: AppVersion, notes: String)? in
            let notes = r.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let v = AppVersion(r.version), !v.isPrerelease, v > from, v <= to, !notes.isEmpty else { return nil }
            return (v, notes)
        }
        .sorted { $0.version > $1.version }
        // One section per version, should two tags name the same one (`v1.2.0` and `v1.2.0+mac`).
        .filter { seen.insert($0.version).inserted }
        return picked.map { "## \($0.version.tag)\n\n\($0.notes)" }.joined(separator: "\n\n")
    }
}
