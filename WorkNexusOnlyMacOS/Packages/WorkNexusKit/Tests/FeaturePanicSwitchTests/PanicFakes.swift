import CoreDomain
import Foundation
@testable import FeaturePanicSwitch

/// Records what the switch asked of the OS; nothing really moves.
@MainActor
final class FakeAppSwitcher: AppSwitcher {
    enum Call: Equatable { case activate(String), hideOthers([String]), hideSelf }
    var calls: [Call] = []
    var activateResult: Outcome<Void> = .success(())

    func listApps() async -> Outcome<[AppRef]> { .success([]) }
    func activate(_ app: AppRef) async -> Outcome<Void> { calls.append(.activate(app.id)); return activateResult }
    func hideOthers(keep: [AppRef]) async -> Outcome<Void> { calls.append(.hideOthers(keep.map(\.id))); return .success(()) }
    func hideSelf() async -> Outcome<Void> { calls.append(.hideSelf); return .success(()) }

    /// What a switch with no app to open does: everything else hidden, then WorkNexus.
    static let bareSwitch: [Call] = [.hideOthers([]), .hideSelf]
}

/// Chat with canned answers; records what is sent.
final class FakeChatGateway: PanicChatGateway, @unchecked Sendable {
    struct Sent: Equatable { let accountId: String; let chatGid: String; let name: String; let bytes: Data; let mimeType: String }
    private let lock = NSLock()
    private var _sent: [Sent] = []
    var sent: [Sent] { lock.lock(); defer { lock.unlock() }; return _sent }
    var sendResult: Outcome<Void> = .success(())
    var people: [PanicPerson] = []
    var me: Int?
    var members: Outcome<[Int]> = .success([])
    var arriving: [PanicIncomingMessage] = []
    /// The user's chats: the team's group by default (who the switch is for).
    var chatList: [PanicChatRef] = [PanicChatRef(gid: "team", kind: .group, name: "VN Mobile+Tester")]

    func incoming() -> AsyncStream<PanicIncomingMessage> {
        // A moment late, as live messages are: the account and settings are in by then.
        let list = arriving
        return AsyncStream { c in
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                list.forEach { c.yield($0) }; c.finish()
            }
        }
    }
    func conversations(accountId: String) -> AsyncStream<[PanicChatRef]> {
        let list = chatList
        return AsyncStream { $0.yield(list); $0.finish() }
    }
    func users(accountId: String) -> AsyncStream<[PanicPerson]> {
        let list = people
        return AsyncStream { $0.yield(list); $0.finish() }
    }
    func selfUserId(accountId: String) async -> Int? { me }
    func memberIds(accountId: String, chatGid: String) async -> Outcome<[Int]> { members }
    func sendFile(accountId: String, chatGid: String, name: String, bytes: Data, mimeType: String) async -> Outcome<Void> {
        lock.lock(); _sent.append(Sent(accountId: accountId, chatGid: chatGid, name: name, bytes: bytes, mimeType: mimeType)); lock.unlock()
        return sendResult
    }
}

struct FakeSticker: PanicStickerSource {
    var result: Outcome<Data> = .success(Data([1, 2]))
    func bytes() -> Outcome<Data> { result }
}

func panicAccount(_ id: String = "a1", _ type: ProviderType = .zentao, _ url: String? = "https://zentao.oasoft.xyz:4433/zentao") -> Account {
    Account(id: id, workspaceId: "w", providerType: type, handle: "h", baseUrl: url)
}

/// Settings kept in memory.
final class MemoryConfigRepository: PanicSwitchConfigRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: PanicSwitchConfig
    init(_ config: PanicSwitchConfig = PanicSwitchConfig()) { stored = config }
    var current: PanicSwitchConfig { lock.lock(); defer { lock.unlock() }; return stored }
    func load() async -> Outcome<PanicSwitchConfig> { .success(current) }
    func save(_ config: PanicSwitchConfig) async -> Outcome<Void> { lock.lock(); stored = config; lock.unlock(); return .success(()) }
}

/// The floating button, without a panel.
@MainActor
final class FakeOverlay: PanicOverlay {
    var shown: Data?
    var onClick: (@MainActor () -> Void)?
    func show(image: Data) -> Outcome<Void> { shown = image; return .success(()) }
    func hide() { shown = nil }
}

/// Waits (up to a second) for `condition` to hold.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
