import CoreDomain
import CoreUI
import FeatureChat
import FeaturePanicSwitch
import Foundation

/// The panic switch ("Thầy vô") at the composition root (lib/app/di/service_locator.dart, the panic switch part, and
/// lib/app/shell/app_shell.dart's `PanicSwitchListener`): its settings file, the bundled sticker, and chat reached through
/// the panic switch's own gateway. Started with the app (not in demo mode), so it listens while the window is hidden too.
@MainActor
final class PanicSwitchWiring {
    let model: PanicSwitchModel

    init(chat: ChatRepository, workspaces: WorkspaceRepository) {
        let stickers = Bundle.main.url(forResource: "Stickers", withExtension: nil)
        model = PanicSwitchFeature.makeModel(
            settingsFile: PlatformPaths.applicationSupport().appendingPathComponent("panic_switch.json"),
            // The same image the Flutter app sends (assets/stickers/WorkNexus/thay_vo.png, copied by Scripts/sync-assets.sh).
            sticker: stickers?.appendingPathComponent("WorkNexus/thay_vo.png"),
            chats: ChatPanicGateway(repository: chat),
            accounts: { workspaces.watchAccounts() })
    }

    func start() { model.start() }
}

/// Adapts the chat repository to what the panic switch reads and sends (features never import each other). Each stream
/// is mapped to the panic switch's small values and repeats are dropped: a presence change or a new last message does not
/// reach it as a change of chats or people.
struct ChatPanicGateway: PanicChatGateway {
    let repository: ChatRepository

    func incoming() -> AsyncStream<PanicIncomingMessage> {
        Self.map(repository.watchIncoming(), dropRepeats: false) { m in
            var imageName: String?
            if case .image(let image) = m.content { imageName = image.name }
            return PanicIncomingMessage(accountId: m.accountId, chatGid: m.chatGid, senderId: m.senderId, sentAt: m.sentAt,
                                        isMine: m.isMine, deleted: m.deleted, imageName: imageName)
        }
    }

    func conversations(accountId: String) -> AsyncStream<[PanicChatRef]> {
        Self.map(repository.watchConversations(accountId: accountId), dropRepeats: true) { list in
            list.map { c in
                let kind: PanicChatRef.Kind = switch c.type { case .group: .group; case .one2one: .direct; default: .other }
                return PanicChatRef(gid: c.gid, kind: kind, name: c.name, peerUserId: c.peerUserId, isMyCloud: c.isMyCloud,
                                    hidden: c.hidden)
            }
        }
    }

    func users(accountId: String) -> AsyncStream<[PanicPerson]> {
        Self.map(repository.watchUsers(accountId: accountId), dropRepeats: true) { list in
            list.map { PanicPerson(userId: $0.userId, account: $0.account, realname: $0.realname, avatarUrl: $0.avatarUrl) }
        }
    }

    func selfUserId(accountId: String) async -> Int? {
        var it = repository.watchSelfUserId(accountId: accountId).makeAsyncIterator()
        return await it.next() ?? nil
    }

    func memberIds(accountId: String, chatGid: String) async -> Outcome<[Int]> {
        await repository.members(accountId: accountId, chatGid: chatGid)
    }

    /// The same call the chat's "send a file" makes: a PNG goes as an `image` message whose content carries `name`.
    func sendFile(accountId: String, chatGid: String, name: String, bytes: Data, mimeType: String) async -> Outcome<Void> {
        await repository.sendFile(accountId: accountId, chatGid: chatGid, name: name, bytes: bytes, mimeType: mimeType, replyToId: nil)
    }

    private static func map<A: Sendable, B: Sendable & Equatable>(_ source: AsyncStream<A>, dropRepeats: Bool,
                                                                  _ transform: @escaping @Sendable (A) -> B) -> AsyncStream<B> {
        AsyncStream { continuation in
            let task = Task {
                var last: B?
                for await value in source {
                    let mapped = transform(value)
                    if dropRepeats, mapped == last { continue }
                    last = mapped
                    continuation.yield(mapped)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
