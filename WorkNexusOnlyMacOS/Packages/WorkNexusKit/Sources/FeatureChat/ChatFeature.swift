import CoreDomain
import CorePersistence
import CoreUI
import Foundation
import GRDB

/// The chat feature's single entry point for the composition root (nothing registers itself):
///
/// 1. **Database** — pass `ChatFeature.migrationRegistrar` (`"chat_v1"`) to `AppDatabase.open(registrars:)`.
/// 2. **Repository** — `ChatFeature.makeRepository(db:account:credentials:)`: the xxd-backed `ChatRepository` (also a
///    `ChatRuntimeSettings`: push `AppSettings.chatCacheLimitMb`, `chatAutoDownloadVideoMb`, `chatReactions` through it).
///    One repository serves every ZenTao account; `connect(accountId:)` signs one in.
/// 3. **Services** — `ChatFeature.makeServices(...)` wires sticker/wallpaper/link-preview/translation stores into `ChatServices`;
///    inject it with `.chatServices(_:)` together with `.chatSettings(ChatSettings(appSettings))` and the app theme.
/// 4. **View** — `ChatRootView(account:)` (an `Account` of provider ZenTao) for the chat tool pane.
/// 5. **Unread badge** — `ChatFeature.unreadCounter(repository:)`.`counts(accountId:)` (hidden/archived/muted chats excluded).
/// 6. **Notifications** — implement `ChatNotificationSink`, then `ChatFeature.notificationBridge(...)`.`start(accountIds:)`;
///    route a click back with `ChatShellEvents.open(chatGid:)`. The view reports the chat it has open (`ChatShellEvents.openChat`):
///    return it from `visibleChat` while the Chat place is on screen, so only that chat's notification is dropped.
/// 7. **Settings views** — `ChatStylePicker`, `ChatWallpaperPicker(onSelect:onDim:)` and `ChatStoragePanel(limitMb:onLimitChange:)`
///    (read `\.chatServices` / `\.chatSettings`; the host saves what they report). `ChatPersonChip`, `ChatPersonChatButton` and
///    `ChatPersonAvatar` are the person hooks (tapping opens the 1:1 chat through `ChatServices.showChat`).
/// 8. **Host hooks on `ChatServices`** — `ticketLookup` / `mergeRequests` (link cards), `showChat`, `openTicket`,
///    `ensureTranslatorReady` (the "OpenCode not linked" gate before a message is translated).
///
/// Settings read from `AppSettings` (via `ChatSettings`): chatAppearance, chatPrimaryBubbles, chatWallpaper, chatWallpaperDim,
/// chatSendMarkdown, chatNotifications, chatNotifyWhileViewing, chatSendTypingStatus, chatReactions, chatCacheLimitMb,
/// chatAutoDownloadVideos, chatAutoDownloadVideoMb, chatTextScale, translationLang, translationModel.
public enum ChatFeature {
    public static var migrationRegistrar: MigrationRegistrar { ChatMigrations.registrar }

    /// - Parameter account: a ZenTao account to prepare (its chat row is created so `connect` has an address); other accounts of
    ///   the same database are still served on demand.
    public static func makeRepository(db: AppDatabase, account: Account? = nil, credentials: CredentialStore,
                                      applying settings: AppSettings? = nil) -> ChatRepository {
        let repo = XxdChatRepository(db: db, credentials: credentials)
        if let s = settings {
            repo.setCacheLimit(bytes: s.chatCacheLimitMb * 1024 * 1024)
            repo.setVideoAutoDownloadLimit(bytes: s.chatAutoDownloadVideoMb * 1024 * 1024)
            repo.setReactions(s.chatReactions)
        }
        if let account, account.providerType == .zentao, let server = ChatCredentialsResolver.xxdServer(for: account.baseUrl) {
            let local = repo.local
            Task { if (try? await local.chatAccount(account.id)) == nil { try? await local.saveChatAccount(account.id, serverUrl: .some(server.absoluteString)) } }
        }
        return repo
    }

    /// The optional stores around the repository, on disk under Application Support (`<bundle>/chat/…`).
    /// - Parameter bundledStickers: a folder of `<pack>/<image>` sticker sets shipped in the app (nil: none).
    public static func makeServices(repository: ChatRepository, db: AppDatabase, credentials: CredentialStore, bundledStickers: URL? = nil,
                                    translator: ChatTextTranslator? = nil, ensureTranslatorReady: (@Sendable () async -> Bool)? = nil,
                                    translations: MessageTranslationRepository? = nil,
                                    ticketLookup: (@Sendable (String) async -> Ticket?)? = nil, mergeRequests: MergeRequestLinkService? = nil,
                                    showChat: (@Sendable (String, String) -> Void)? = nil, openTicket: (@Sendable (Ticket) -> Void)? = nil) -> ChatServices {
        let base = PlatformPaths.applicationSupport().appendingPathComponent("chat", isDirectory: true)
        let converter = ImageStickerConverter()
        let stickers = LocalStickerRepository(bundleRoot: bundledStickers, directory: base.appendingPathComponent("stickers", isDirectory: true), converter: converter)
        let source = TelegramStickerSource()
        return ChatServices(
            chat: repository, stickers: stickers, wallpapers: LocalWallpaperRepository(directory: base.appendingPathComponent("wallpapers", isDirectory: true)),
            linkPreviews: CachedLinkPreviewRepository(db: db), translations: translations ?? (repository as? XxdChatRepository).map { LocalMessageTranslationRepository(local: $0.local) },
            translator: translator, ensureTranslatorReady: ensureTranslatorReady, telegramTokens: CredentialTelegramTokenStore(store: credentials),
            stickerImport: ImportStickerPack(source, converter, stickers), ticketLookup: ticketLookup, mergeRequests: mergeRequests,
            showChat: showChat, openTicket: openTicket)
    }

    public static func unreadCounter(repository: ChatRepository) -> ChatUnreadCounter { ChatUnreadCounter(repository: repository) }

    public static func notificationBridge(repository: ChatRepository, sink: ChatNotificationSink, texts: ChatNotificationTexts = ChatNotificationTexts(),
                                          preferences: @escaping @Sendable () -> ChatNotificationPreferences,
                                          visibleChat: @escaping @Sendable () -> (accountId: String, chatGid: String)?) -> ChatNotificationBridge {
        ChatNotificationBridge(repository: repository, sink: sink, texts: texts, preferences: preferences, visibleChat: visibleChat)
    }
}
