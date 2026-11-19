import CoreDomain

/// What the running version brought since the one this computer ran last.
public struct WhatsNew: Sendable, Equatable, Identifiable {
    public var from: String
    public var to: String
    /// Markdown, a heading per version (`CollectReleaseNotes`).
    public var notes: String
    public var id: String { "\(from)→\(to)" }
    public init(from: String, to: String, notes: String) { self.from = from; self.to = to; self.notes = notes }
}

/// Ported from: lib/features/app_update/domain/usecases/find_whats_new.dart
/// At launch: the notes of every release since the last version seen, when the app was just updated; nil otherwise
/// (first launch, same version, a downgrade, or nothing written for those releases). The running version is remembered
/// only once the notes are known, so a failed fetch is tried again next launch.
public struct FindWhatsNew: Sendable {
    private let releases: UpdateRepository
    private let seen: SeenVersionStore

    public init(releases: UpdateRepository, seen: SeenVersionStore) { self.releases = releases; self.seen = seen }

    public func callAsFunction() async -> Outcome<WhatsNew?> {
        let current = releases.currentVersion()
        let last: String?
        switch await seen.lastSeen() {
        case .failure(let f): return .failure(f)
        case .success(let v): last = v
        }
        guard let last, let from = AppVersion(last), let to = AppVersion(current), to > from else {
            // First launch, a downgrade or the same build: nothing to tell.
            return last == current ? .success(nil) : await remember(current, nil)
        }
        switch await CollectReleaseNotes(releases)(after: last, upTo: current) {
        case .failure(let f): return .failure(f)
        case .success(let notes):
            return await remember(current, notes.isEmpty ? nil : WhatsNew(from: last, to: current, notes: notes))
        }
    }

    private func remember(_ version: String, _ news: WhatsNew?) async -> Outcome<WhatsNew?> {
        await seen.setLastSeen(version).map { news }
    }
}
