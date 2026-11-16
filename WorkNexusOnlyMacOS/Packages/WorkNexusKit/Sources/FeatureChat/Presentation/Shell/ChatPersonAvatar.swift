import CoreDomain
import CoreUI
import Observation
import SwiftUI

/// Chat users of every ZenTao account, loaded once and shared, so a board full of assignee chips does not open one
/// database observation each. `person(accountId:name:)` matches a ZenTao display name against the chat's users.
@MainActor @Observable
final class ChatPersonDirectory {
    static let shared = ChatPersonDirectory()
    private(set) var users: [String: [ChatUser]] = [:]
    @ObservationIgnored private var watching: [String: Task<Void, Never>] = [:]

    func ensure(_ accountId: String, _ repository: ChatRepository) {
        guard watching[accountId] == nil else { return }
        watching[accountId] = Task { [weak self] in
            for await list in repository.watchUsers(accountId: accountId) { self?.users[accountId] = list }
        }
    }

    /// The chat user `name` refers to: by login handle first (unique), then by display name; deleted accounts are skipped.
    func person(accountId: String, name: String) -> ChatUser? { Self.find(users[accountId] ?? [], name) }

    static func find(_ users: [ChatUser], _ name: String) -> ChatUser? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }
        var byName: ChatUser?
        for u in users where !u.deleted {
            if u.account.lowercased() == key { return u }
            if byName == nil, u.realname.trimmingCharacters(in: .whitespaces).lowercased() == key { byName = u }
        }
        return byName
    }
}

/// A ZenTao person's avatar with the chat photo and role check when the chat knows them (the app injects this as the
/// shared `\.personAvatar` hook); else initials. Needs `\.chatServices`.
public struct ChatPersonAvatar: View {
    @Environment(\.chatServices) private var services
    let accountId: String; let name: String; let diameter: CGFloat

    public init(accountId: String, name: String, diameter: CGFloat) { self.accountId = accountId; self.name = name; self.diameter = diameter }

    public var body: some View {
        let dir = ChatPersonDirectory.shared
        let user = dir.person(accountId: accountId, name: name)
        ChatAvatarView(name: name, style: ChatAvatarStyle(imageUrl: user?.avatarUrl),
                       verified: user.flatMap { ChatShellLabels.verifiedBadge([$0.userId: $0], $0.userId) }, diameter: diameter)
            .frame(width: diameter, height: diameter)
            .task(id: accountId) { if let services { dir.ensure(accountId, services.chat) } }
    }
}

/// A ZenTao person as chat knows them: their photo with presence and the "verified" check, and a tap that opens the one-to-one
/// chat with them (the app injects this as the shared `\.personChip` hook). Someone chat doesn't know (yet) is drawn the same,
/// without the tap.
/// Ported from: lib/features/chat/presentation/widgets/chat_person_chip.dart (ChatPersonChip)
public struct ChatPersonChip: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    let accountId: String; let name: String; let diameter: CGFloat

    public init(accountId: String, name: String, diameter: CGFloat) { self.accountId = accountId; self.name = name; self.diameter = diameter }

    public var body: some View {
        let dir = ChatPersonDirectory.shared
        let user = dir.person(accountId: accountId, name: name)
        let shown = user.flatMap { $0.realname.isEmpty ? nil : $0.realname } ?? name
        let chip = HoverSurface(onTap: user.flatMap { u in services.map { s in { ChatPersonOpener.open(s, accountId: accountId, userId: u.userId) } } },
                                cornerRadius: theme.radii.pill) {
            HStack(spacing: theme.spacing.s6) {
                ChatAvatarView(name: shown, style: ChatAvatarStyle(imageUrl: user?.avatarUrl),
                               presence: user?.status.map { ChatPresence.from(status: $0) },
                               verified: user.flatMap { ChatShellLabels.verifiedBadge([$0.userId: $0], $0.userId) }, diameter: diameter)
                Text(shown).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx).lineLimit(1)
            }
            .padding(EdgeInsets(top: theme.spacing.s2, leading: theme.spacing.s2, bottom: theme.spacing.s2, trailing: theme.spacing.s8))
        }
        .task(id: accountId) { if let services { dir.ensure(accountId, services.chat) } }
        if user != nil { chip.help(shellString("chatWithPerson", "Message {name}", ["name": shown])) } else { chip }
    }
}

/// A small "message" button opening a direct chat with the ZenTao person `name`; nothing for someone chat doesn't know (the app
/// injects it as `\.zentaoDocPersonAction`).
/// Ported from: lib/features/chat/presentation/widgets/chat_person_chip.dart (ChatPersonChatButton)
public struct ChatPersonChatButton: View {
    @Environment(\.chatServices) private var services
    let accountId: String; let name: String

    public init(accountId: String, name: String) { self.accountId = accountId; self.name = name }

    public var body: some View {
        let dir = ChatPersonDirectory.shared
        Group {
            if let user = dir.person(accountId: accountId, name: name), let services {
                let shown = user.realname.isEmpty ? name : user.realname
                AppButton(shellString("personMessage", "Message"), systemImage: "message") { ChatPersonOpener.open(services, accountId: accountId, userId: user.userId) }
                    .help(shellString("chatWithPerson", "Message {name}", ["name": shown]))
            }
        }
        .task(id: accountId) { if let services { dir.ensure(accountId, services.chat) } }
    }
}

/// Opens (creating on first use) the one-to-one chat with a user and asks the host to show it.
enum ChatPersonOpener {
    @MainActor static func open(_ services: ChatServices, accountId: String, userId: Int) {
        Task { @MainActor in
            if case .success(let gid) = await OpenDirectChat(services.chat)(accountId: accountId, userId: userId) { services.showChat?(accountId, gid) }
        }
    }
}
