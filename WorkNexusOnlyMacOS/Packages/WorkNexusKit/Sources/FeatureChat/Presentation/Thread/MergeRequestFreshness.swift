/// Ported from: lib/features/chat/presentation/providers/merge_request_providers.dart (`_kFresh`, the resume refetch rule)
import CoreDomain
import Foundation

/// When a linked MR/PR/issue is fetched again: a state fetched less than five minutes ago is trusted by every card of the same
/// link; merged and closed are final; anything else (or a failed load) may have changed while the user was away, so coming
/// back to the app refetches it.
struct MergeRequestFreshness {
    static let fresh: TimeInterval = 5 * 60
    private var fetchedAt: [String: Date] = [:]

    /// Whether the card of `url` should fetch from the provider now. `resumed`: the app came back to the front.
    func needsFetch(_ url: String, stored: Ticket?, resumed: Bool, now: Date = Date()) -> Bool {
        if Self.isFinal(stored) { return false }
        if resumed { return true }
        guard stored != nil, let at = fetchedAt[url] else { return true }
        return now.timeIntervalSince(at) >= Self.fresh
    }

    mutating func fetched(_ url: String, at: Date = Date()) { fetchedAt[url] = at }

    /// Merged and closed items do not change any more.
    static func isFinal(_ t: Ticket?) -> Bool { t.map { ["merged", "closed"].contains($0.providerStatus.lowercased()) } ?? false }
}
