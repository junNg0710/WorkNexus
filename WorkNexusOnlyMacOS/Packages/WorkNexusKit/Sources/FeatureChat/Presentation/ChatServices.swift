import CoreDomain
import CoreUI
import SwiftUI

/// What the chat UI may depend on — interfaces only (rules 1.3/8.2). Built by `ChatFeature` (or the host's composition root)
/// and injected with `.chatServices(_:)`. Optional members disable the matching UI when nil.
public struct ChatServices: Sendable {
    public var chat: ChatRepository
    public var stickers: StickerRepository?
    public var wallpapers: WallpaperRepository?
    public var linkPreviews: LinkPreviewRepository?
    public var translations: MessageTranslationRepository?
    public var translator: ChatTextTranslator?
    /// Asked before a message is translated: false means translating cannot run (no OpenCode login / API key) and the host has
    /// already told the user how to fix it (`ensureOpenCodeLinked`). nil: always ready.
    public var ensureTranslatorReady: (@Sendable () async -> Bool)?
    public var telegramTokens: TelegramTokenStore?
    public var stickerImport: ImportStickerPack?
    /// Looks up a ticket by (ZenTao / GitLab / GitHub) URL for link cards; the app wires it to its ticket repository.
    public var ticketLookup: (@Sendable (String) async -> Ticket?)?
    /// Fetches the MR/PR/issue a link points to from its provider (and stores it); nil: link cards only read what is stored.
    public var mergeRequests: MergeRequestLinkService?
    /// Brings the chat place forward on `chatGid` of the account (a person chip opened a direct chat); nil: chips are not tappable.
    public var showChat: (@Sendable (_ accountId: String, _ chatGid: String) -> Void)?
    /// Opens a ticket inside the app.
    public var openTicket: (@Sendable (Ticket) -> Void)?
    public var openURL: @Sendable (URL) -> Void

    public init(chat: ChatRepository, stickers: StickerRepository? = nil, wallpapers: WallpaperRepository? = nil,
                linkPreviews: LinkPreviewRepository? = nil, translations: MessageTranslationRepository? = nil,
                translator: ChatTextTranslator? = nil, ensureTranslatorReady: (@Sendable () async -> Bool)? = nil, telegramTokens: TelegramTokenStore? = nil, stickerImport: ImportStickerPack? = nil,
                ticketLookup: (@Sendable (String) async -> Ticket?)? = nil, mergeRequests: MergeRequestLinkService? = nil,
                showChat: (@Sendable (String, String) -> Void)? = nil, openTicket: (@Sendable (Ticket) -> Void)? = nil, openURL: @escaping @Sendable (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.chat = chat; self.stickers = stickers; self.wallpapers = wallpapers; self.linkPreviews = linkPreviews
        self.translations = translations; self.translator = translator; self.ensureTranslatorReady = ensureTranslatorReady; self.telegramTokens = telegramTokens
        self.stickerImport = stickerImport; self.ticketLookup = ticketLookup; self.mergeRequests = mergeRequests; self.showChat = showChat; self.openTicket = openTicket; self.openURL = openURL
    }
}

private struct ChatServicesKey: EnvironmentKey { static let defaultValue: ChatServices? = nil }
public extension EnvironmentValues {
    var chatServices: ChatServices? {
        get { self[ChatServicesKey.self] }
        set { self[ChatServicesKey.self] = newValue }
    }
}

public extension View {
    func chatServices(_ services: ChatServices) -> some View { environment(\.chatServices, services) }
}
