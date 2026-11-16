import CoreDomain
import Foundation

/// Ported from: lib/features/chat/domain/repositories/link_preview_repository.dart
public protocol LinkPreviewRepository: Sendable {
    func preview(url: String) async -> Outcome<LinkPreview?>
}

/// Ported from: lib/features/chat/domain/repositories/message_translation_repository.dart
public protocol MessageTranslationRepository: Sendable {
    func find(accountId: String, gid: String, targetLang: String) async -> Outcome<ChatMessageTranslation?>
    func watch(accountId: String, gid: String, targetLang: String) -> AsyncStream<ChatMessageTranslation?>
    func setVisible(accountId: String, gid: String, targetLang: String, visible: Bool) async -> Outcome<Void>
    func save(_ translation: ChatMessageTranslation) async -> Outcome<Void>
}

/// Ported from: lib/features/chat/domain/repositories/sticker_pack_source.dart
public protocol StickerPackSource: Sendable {
    func stickerSet(name: String, token: String) async -> Outcome<RemoteStickerSet>
    func file(fileId: String, token: String) async -> Outcome<Data>
}

public protocol StickerConverter: Sendable {
    func animatedToWebp(tgs: Data) async -> Outcome<Data>
    func imageToWebp(image: Data) async -> Outcome<Data>
}

public protocol TelegramTokenStore: Sendable {
    func read() async -> String?
    func write(_ token: String) async
}

/// Ported from: lib/features/chat/domain/repositories/sticker_repository.dart
public typealias StickerFile = (name: String, bytes: Data)

public protocol StickerRepository: Sendable {
    func stickers() async -> Outcome<[ChatSticker]>
    func bytes(_ sticker: ChatSticker) async -> Outcome<Data>
    func add(bytes: Data, name: String) async -> Outcome<ChatSticker>
    func remove(_ sticker: ChatSticker) async -> Outcome<Void>
    func addPack(_ pack: String, title: String, stickers: [StickerFile]) async -> Outcome<Void>
    func removePack(_ pack: String) async -> Outcome<Void>
    func lastPack() async -> Outcome<String?>
    func rememberPack(_ pack: String) async -> Outcome<Void>
}

/// Ported from: lib/features/chat/domain/repositories/wallpaper_repository.dart
public protocol WallpaperRepository: Sendable {
    func wallpapers() async -> Outcome<[String]>
    func add(bytes: Data, name: String) async -> Outcome<String>
    func remove(path: String) async -> Outcome<Void>
}

/// Loads the GitLab merge request / GitHub pull request — or an issue of either — a chat link points to, on demand: through the
/// connected account for the link's host, stores it with the other tickets and returns it, so its live state can be shown and it
/// can open in the detail panel. The host app implements it over its provider adapters (features never import tools).
/// Ported from: lib/core/domain/adapters/merge_request_link_service.dart
public protocol MergeRequestLinkService: Sendable {
    /// The item `link` names, as the provider reports it now. `.notFound` when no connected account matches the host.
    func fetchMergeRequest(_ link: MergeRequestLink) async -> Outcome<Ticket>
}
