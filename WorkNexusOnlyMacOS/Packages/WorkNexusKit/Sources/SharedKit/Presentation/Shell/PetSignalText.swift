import CoreDomain
import CoreUI
import Foundation

/// What the pet says about what goes on in the app: a line for each reaction (so it can be read, not only seen) and a
/// summary of the state of things for when the pointer rests on it. Not in the Flutter app.
enum PetSignalText {
    /// The line for a new mood, when it is news (nothing for calm: "all synced" is said by `synced`).
    static func mood(_ mood: PetDirector.Mood, statuses: some Collection<AccountSyncStatus>, waiting: Int) -> String? {
        switch mood {
        case .calm: nil
        case .busy: appString("petSaySyncing", "Syncing your work…")
        case .offline: appString("petSayOffline", "Offline — waiting for the connection")
        case .trouble: trouble(statuses)
        case .attention: self.waiting(waiting)
        }
    }

    static func trouble(_ statuses: some Collection<AccountSyncStatus>) -> String {
        statuses.contains(.authExpired)
            ? appString("petSayAuthExpired", "Sign-in expired — sign in again in Connections")
            : appString("petSaySyncFailed", "Sync failed — see Connections")
    }

    static func waiting(_ count: Int) -> String {
        count == 1 ? appString("petSayWaitingOne", "1 notification is waiting for you")
            : appString("petSayWaitingOther", "%1$@ notifications are waiting for you").replacingOccurrences(of: "%1$@", with: "\(count)")
    }

    static func newChats(_ added: Int) -> String {
        added == 1 ? appString("petSayChatOne", "New chat message")
            : appString("petSayChatOther", "%1$@ new chat messages").replacingOccurrences(of: "%1$@", with: "\(added)")
    }

    static func unreadChats(_ count: Int) -> String {
        count == 1 ? appString("petSayUnreadChatOne", "1 unread chat message")
            : appString("petSayUnreadChatOther", "%1$@ unread chat messages").replacingOccurrences(of: "%1$@", with: "\(count)")
    }

    static var synced: String { appString("petSaySynced", "All synced") }
    static var celebrated: String { appString("petSayResolved", "Ticket resolved — nice work!") }

    /// The state of things, a line each: the sync when it is not fine, unread chats, notifications waiting; "all quiet"
    /// when there is nothing.
    static func status(mood: PetDirector.Mood, statuses: some Collection<AccountSyncStatus>, unreadChats: Int, waiting: Int) -> String {
        var lines: [String] = []
        switch mood {
        case .busy: lines.append(appString("petSaySyncing", "Syncing your work…"))
        case .offline: lines.append(appString("petSayOffline", "Offline — waiting for the connection"))
        case .trouble: lines.append(trouble(statuses))
        case .calm, .attention: break
        }
        if unreadChats > 0 { lines.append(self.unreadChats(unreadChats)) }
        if waiting > 0 { lines.append(self.waiting(waiting)) }
        return lines.isEmpty ? appString("petSayAllQuiet", "All quiet — nothing waiting") : lines.joined(separator: "\n")
    }
}
