/// Ported from: lib/features/app_update/presentation/providers/update_state.dart
/// Where the background install of the latest stable release stands.
public enum UpdateState: Sendable, Equatable {
    /// No newer release is known (or none has been looked for yet).
    case idle
    /// The release carries no verifiable build for this platform; it can only be fetched by hand from its page.
    case manual(AvailableUpdate)
    case downloading(AvailableUpdate, progress: Double)
    /// Downloaded and verified; installs once the user restarts.
    case ready(AvailableUpdate, stagedPath: String)
    case installing(AvailableUpdate)
    /// Download or install failed; `message` is for the log, the UI words it.
    case failed(AvailableUpdate, message: String)

    public var update: AvailableUpdate? {
        switch self {
        case .idle: nil
        case .manual(let u), .downloading(let u, _), .ready(let u, _), .installing(let u), .failed(let u, _): u
        }
    }
}
