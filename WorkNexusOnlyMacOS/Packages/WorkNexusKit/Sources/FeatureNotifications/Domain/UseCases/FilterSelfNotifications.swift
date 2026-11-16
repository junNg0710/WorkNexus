import CoreDomain
import Foundation

/// Ported from: lib/features/notifications/domain/usecases/filter_self_notifications.dart
/// Filters out notifications where the action was initiated by the current user (self-starting a task, editing,
/// closing, resolving). Only notifications for actions by other people related to the user are kept.
public struct FilterSelfNotifications: Sendable {
    public init() {}

    public func callAsFunction(_ notifications: [ZenTaoNotification], accounts: [Account],
                               realnamesByAccountId: [String: String] = [:]) -> [ZenTaoNotification] {
        if notifications.isEmpty || accounts.isEmpty { return notifications }
        var byAccount: [String: Set<String>] = [:]
        var all = Set<String>()
        for account in accounts {
            var names = Set<String>()
            let handle = account.handle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !handle.isEmpty { names.insert(handle.lowercased()) }
            if let real = realnamesByAccountId[account.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !real.isEmpty {
                names.insert(real.lowercased())
            }
            byAccount[account.id] = names
            all.formUnion(names)
        }
        if all.isEmpty { return notifications }
        let parser = ParseNotificationEvent()
        return notifications.filter { !isSelf($0, parser: parser, candidates: byAccount[$0.accountId] ?? all) }
    }

    private func isSelf(_ n: ZenTaoNotification, parser: ParseNotificationEvent, candidates: Set<String>) -> Bool {
        let summary = n.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty { return false }
        if let event = parser(summary), candidates.contains(event.actor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            return true
        }
        // Fallback if the parser did not match a known verb: the summary starts with one of the names.
        let lower = summary.lowercased()
        for candidate in candidates where !candidate.isEmpty && lower.hasPrefix(candidate) {
            guard let next = lower.dropFirst(candidate.count).unicodeScalars.first else { return true }
            // `\s` or a non-word character (anything outside ASCII word characters, incl. all non-ASCII).
            let isWord = next.isASCII && (CharacterSet.alphanumerics.contains(next) || next == "_")
            if !isWord { return true }
        }
        return false
    }
}
