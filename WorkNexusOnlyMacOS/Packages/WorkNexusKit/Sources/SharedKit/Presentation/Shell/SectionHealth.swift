import CoreDomain

/// What an account's sync status means for the section on screen (Dart: `AuthExpiredBanner` in `viewport.dart`, plus the
/// offline / error news the Flutter app only showed on the integration rows). Pure, so it is unit-tested.
///
/// - an expired session always gets its banner (cached data stays readable);
/// - offline or a failed sync get a slim, dismissible strip, because the cached data is still there;
/// - a failed sync of an account that has nothing cached yet replaces the section with an error and a Retry
///   (`SectionErrorBoundary`'s job in Dart): a blank board would say nothing.
enum SectionHealth: Equatable {
    case healthy
    case authExpired
    case offline(blocked: Bool)
    case failed(String, blocked: Bool)

    init(status: AccountSyncStatus?, hasCachedData: Bool) {
        switch status {
        case .authExpired?: self = .authExpired
        case .offline?: self = .offline(blocked: !hasCachedData)
        case .error(let m)?: self = .failed(m, blocked: !hasCachedData)
        default: self = .healthy
        }
    }

    /// The section is replaced by an error state.
    var blocksSection: Bool {
        switch self {
        case .offline(let blocked), .failed(_, let blocked): blocked
        default: false
        }
    }

    /// Stable id of the news, so a dismissed strip stays dismissed until the news changes.
    var newsKey: String {
        switch self {
        case .healthy: "healthy"
        case .authExpired: "auth"
        case .offline: "offline"
        case .failed(let m, _): "failed:\(m)"
        }
    }
}
