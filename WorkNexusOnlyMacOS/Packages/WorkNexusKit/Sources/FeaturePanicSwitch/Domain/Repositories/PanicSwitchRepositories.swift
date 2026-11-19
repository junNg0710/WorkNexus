import CoreDomain
import Foundation

/// Ported from: lib/features/panic_switch/domain/repositories/app_switcher.dart
/// Brings other apps to the front and hides them, through the OS.
public protocol AppSwitcher: Sendable {
    /// Apps the user can pick from: installed and running ones, by name.
    func listApps() async -> Outcome<[AppRef]>
    /// Brings `app` to the front, starting it when it is not running.
    func activate(_ app: AppRef) async -> Outcome<Void>
    /// Hides `app`; nothing when it is not running.
    func hide(_ app: AppRef) async -> Outcome<Void>
    /// Hides WorkNexus.
    func hideSelf() async -> Outcome<Void>
}

/// Ported from: lib/features/panic_switch/domain/repositories/panic_overlay.dart
/// The floating button, drawn by the OS above every app. Clicks are reported one by one (`onClick`); the panic switch
/// counts them (`TripleClickCounter`).
@MainActor
public protocol PanicOverlay: AnyObject {
    /// Shows the button with `image` (PNG bytes) on it.
    func show(image: Data) -> Outcome<Void>
    func hide()
    /// Called on every click of the button that was not a drag.
    var onClick: (@MainActor () -> Void)? { get set }
}

/// Ported from: lib/features/panic_switch/domain/repositories/panic_sticker_source.dart
/// The "Thầy vô" sticker image.
public protocol PanicStickerSource: Sendable {
    func bytes() -> Outcome<Data>
}

/// Ported from: lib/features/panic_switch/domain/repositories/panic_switch_config_repository.dart
/// Where this computer's panic switch settings are kept.
public protocol PanicSwitchConfigRepository: Sendable {
    /// The saved settings, or the defaults when none were saved yet.
    func load() async -> Outcome<PanicSwitchConfig>
    func save(_ config: PanicSwitchConfig) async -> Outcome<Void>
}

/// Chat, as the panic switch uses it: groups and members to pick from, messages arriving, a file to send. The composition
/// root adapts the chat repository to it (the Flutter feature read `ChatRepository` directly).
/// Ported from: lib/features/chat/domain/repositories/chat_repository.dart (the calls the panic switch makes)
public protocol PanicChatGateway: Sendable {
    /// Messages from other people as they arrive live (not history).
    func incoming() -> AsyncStream<PanicIncomingMessage>
    /// The account's chats, again each time they change.
    func conversations(accountId: String) -> AsyncStream<[PanicChatRef]>
    /// The people chat knows, again each time they change.
    func users(accountId: String) -> AsyncStream<[PanicPerson]>
    /// The signed-in user's chat id, once known.
    func selfUserId(accountId: String) async -> Int?
    /// The user ids of a group's members.
    func memberIds(accountId: String, chatGid: String) async -> Outcome<[Int]>
    /// Uploads `bytes` as a file named `name` and sends it into the chat (an image message for an image type).
    func sendFile(accountId: String, chatGid: String, name: String, bytes: Data, mimeType: String) async -> Outcome<Void>
}
