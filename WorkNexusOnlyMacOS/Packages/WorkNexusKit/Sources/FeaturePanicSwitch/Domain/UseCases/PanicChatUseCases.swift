import CoreDomain
import Foundation

/// Ported from: lib/features/panic_switch/domain/usecases/find_panic_switch_account.dart
/// The ZenTao account the panic switch works through, or nil when the user is not signed in to the ZenTao it is offered
/// for — then the feature is off.
public struct FindPanicSwitchAccount: Sendable {
    public init() {}

    public func callAsFunction(_ accounts: [Account]) -> Account? {
        let wanted = Self.normalize(PanicSwitchConstants.zentaoBaseUrl)
        return accounts.first { $0.providerType == .zentao && $0.baseUrl.map(Self.normalize) == wanted }
    }

    /// Users type the URL with or without a trailing slash, in any case.
    static func normalize(_ url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

/// Not in the Flutter app: whether the user is in the team's group (`PanicSwitchConstants.defaultGroupName`) among
/// their chats, which is who the switch is offered to. A group they have hidden still counts: they are in it.
public struct IsInPanicTeam: Sendable {
    public init() {}
    public func callAsFunction(_ conversations: [PanicChatRef]) -> Bool { PickDefaultPanicGroup()(conversations) != nil }
}

/// Ported from: lib/features/panic_switch/domain/usecases/pick_default_panic_group.dart
/// The group to use before the user picks one: the one named `PanicSwitchConstants.defaultGroupName`, when the account is
/// in it. Only letters and digits are compared — the team's group is "VN Mobile+Tester".
public struct PickDefaultPanicGroup: Sendable {
    public init() {}

    public func callAsFunction(_ conversations: [PanicChatRef]) -> String? {
        let wanted = Self.key(PanicSwitchConstants.defaultGroupName)
        return conversations.first { $0.kind == .group && Self.key($0.name) == wanted }?.gid
    }

    static func key(_ name: String) -> String {
        String(String.UnicodeScalarView(name.lowercased().unicodeScalars.filter { s in
            switch s.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .decimalNumber, .letterNumber, .otherNumber: true
            default: false
            }
        }))
    }
}

/// Ported from: lib/features/panic_switch/domain/usecases/list_panic_chats.dart
/// The chats the sticker can go to — groups and one-to-one chats, by title — after the user's own chat ("My Cloud", shown
/// as `selfTitle`), which is for trying the switch alone.
public struct ListPanicChats: Sendable {
    public init() {}

    public func callAsFunction(_ conversations: [PanicChatRef], _ usersById: [Int: PanicPerson], selfTitle: String) -> [PanicChat] {
        var chats: [PanicChat] = []
        var own: PanicChat?
        for c in conversations {
            if c.isMyCloud {
                if own == nil { own = PanicChat(chat: c, title: selfTitle) }
                continue
            }
            guard c.kind == .group || c.kind == .direct, !c.hidden, let title = Self.title(c, usersById) else { continue }
            chats.append(PanicChat(chat: c, title: title))
        }
        chats.sort { $0.title.lowercased() < $1.title.lowercased() }
        return (own.map { [$0] } ?? []) + chats
    }

    /// lib/features/chat/domain/usecases/resolve_chat_title.dart: a one-to-one chat is named after the peer; nil while
    /// the peer is not loaded yet, or for a group without a name.
    static func title(_ chat: PanicChatRef, _ usersById: [Int: PanicPerson]) -> String? {
        if chat.kind == .direct {
            guard let peer = chat.peerUserId.flatMap({ usersById[$0] }) else { return nil }
            return peer.displayName
        }
        let name = chat.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

/// Ported from: lib/features/panic_switch/domain/usecases/load_panic_group_members.dart
/// The members of a group who could send the sticker: everyone but the user, by name.
public struct LoadPanicGroupMembers: Sendable {
    private let chats: PanicChatGateway

    public init(_ chats: PanicChatGateway) { self.chats = chats }

    public func callAsFunction(accountId: String, chatGid: String) async -> Outcome<[PanicPerson]> {
        var users = chats.users(accountId: accountId).makeAsyncIterator()
        let byId = Dictionary((await users.next() ?? []).map { ($0.userId, $0) }, uniquingKeysWith: { a, _ in a })
        let me = await chats.selfUserId(accountId: accountId)
        return await chats.memberIds(accountId: accountId, chatGid: chatGid).map { ids in
            ids.filter { $0 != me }.compactMap { byId[$0] }.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        }
    }
}

/// Ported from: lib/features/panic_switch/domain/usecases/send_panic_sticker.dart
/// Sends `trigger`'s sticker into `chatGid`, under the reserved file name receivers recognise it by — the same file names,
/// type and image the Flutter app sends, so either app reacts to the other's stickers.
public struct SendPanicSticker: Sendable {
    private let chats: PanicChatGateway
    private let sticker: PanicStickerSource

    public init(_ chats: PanicChatGateway, _ sticker: PanicStickerSource) { self.chats = chats; self.sticker = sticker }

    public func callAsFunction(trigger: PanicTrigger, accountId: String, chatGid: String) async -> Outcome<Void> {
        switch sticker.bytes() {
        case .failure(let f): return .failure(f)
        case .success(let bytes):
            return await chats.sendFile(accountId: accountId, chatGid: chatGid, name: trigger.stickerFileName,
                                        bytes: bytes, mimeType: PanicSwitchConstants.stickerMimeType)
        }
    }
}
