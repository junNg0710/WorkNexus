import Foundation

/// Ported from: lib/core/settings/app_settings.dart (+ chat_appearance.dart). Persisted as one JSON row.
public enum ThemeVariant: String, Codable, CaseIterable, Sendable { case light, dark, midnight }
public enum SurfaceStyle: String, Codable, CaseIterable, Sendable { case flat, outline }
public enum AppDensity: String, Codable, CaseIterable, Sendable { case comfortable, compact }
public enum DetailLayout: String, Codable, CaseIterable, Sendable { case twoPane, tabbed }
public enum BoardLayout: String, Codable, CaseIterable, Sendable { case board, table }
/// Where the pet stands: in the main window over the content, or floating on the desktop above every app (macOS only).
public enum PetDisplay: String, Codable, CaseIterable, Sendable { case inWindow, floating }
public enum ChatAppearance: String, Codable, CaseIterable, Sendable { case worknexus, telegram, zalo, zentao, wechat, tbchat }

public struct AppSettings: Codable, Equatable, Sendable {
    public var variant: ThemeVariant = .light
    public var themeFollowsSystem = true
    public var surface: SurfaceStyle = .outline
    public var density: AppDensity = .comfortable
    public var detailLayout: DetailLayout = .twoPane
    public var boardLayout: BoardLayout = .board
    public var dateFormat = "iso"
    public var companyTint = false
    public var localeCode = "en"
    public var translationLang = "vi"
    public var translationModel = ""
    public var fontFamily = ""        // "" = the system font (SF Pro); the Flutter app defaulted to Space Grotesk
    public var componentRadius: Double = 8
    public var chatAppearance: ChatAppearance = .worknexus
    public var chatPrimaryBubbles = false
    public var chatWallpaper = "pattern"
    public var chatWallpaperDim: Double = 0.2
    public var chatSendMarkdown = false
    public var chatNotifications = true
    public var chatNotifyWhileViewing = true
    public var chatSendTypingStatus = true
    public var chatReactions = false
    public var chatCacheLimitMb = 2048
    public var chatAutoDownloadVideos = true
    public var chatAutoDownloadVideoMb = 20
    public var chatTextScale: Double = 1
    /// Hiding chats on screen; see `ChatPrivacy`.
    public var chatPrivacy = ChatPrivacy()
    /// Stickers offered over the composer while typing and to answer the newest message (turned on and off in its ✨ menu).
    public var chatStickerSuggestions = true
    /// Whose voice the ✨ reply ideas take (`ChatReplyRole` raw value; "auto" follows the ZenTao role).
    public var chatAiReplyRole = "auto"
    /// Whether local AI tools (the bundled MCP server) may use chat through the loopback chat API: send messages, load older
    /// history, download attachments. Off by default.
    public var chatLocalApi = false
    public var miniAppLiveLimit = 5
    public var miniAppNotifyInBackground = true
    /// Whether the bars over a mini app's page (the window's title bar and the browser bar) are folded away, leaving the
    /// page their room; the tab strip stays, with the button that brings them back (macOS only).
    public var miniAppBarsCollapsed = false
    public var accentColorValue: Int?
    public var pinnedProjects: [String] = []
    public var pinnedExecutions: [String] = []
    /// Not in the Flutter app. Per ZenTao execution ("accountId:executionId"): whether its tasks show in a team view. An
    /// execution without an entry follows the default (`IsShownInTeamView`).
    public var teamExecutionVisibility: [String: Bool] = [:]
    public var sidebarWidth: Double = 290
    public var tableColumnWidths: [String: Double] = [:]
    public var docsReaderBrightness: String?
    public var viewModes: [String: String] = [:]
    /// The TBChat character that stands in the window (macOS only).
    public var showPet = true
    /// The pet shown (an installed pet's id); nil is the TBChat character that ships with the app (macOS only).
    public var petId: String?
    public var petDisplay: PetDisplay = .floating
    /// Whether a pet that can look around turns toward the pointer while it idles (macOS only).
    public var petFollowsCursor = true
    /// Whether the pet says what a new chat message or ZenTao notification says, rather than only that one came (macOS only).
    public var petShowsDetails = true
    /// Whether the pet on the desktop stays there when WorkNexus is hidden (a click on the pet, ⌘H) (macOS only).
    public var petStaysWhenAppHides = true
    /// Whether a click on the pet while WorkNexus is in front puts the app the user was in before back over it, rather
    /// than hiding WorkNexus (macOS only).
    public var petClickGoesBack = true
    /// How big the pet is drawn, against its usual size (1), in the window and on the desktop (macOS only).
    public var petScale: Double = 1
    /// The sizes the pet can be set to (`petScale`).
    public static let petScaleRange: ClosedRange<Double> = 0.5...2
    /// What the pet does: how much it moves, what it reacts to, how it speaks (macOS only).
    public var petBehavior = PetBehavior()
    /// The keys that open the places of the rail (⌘1 … ⌘0, then ⌥⌘1 … ⌥⌘0 from the top unless chosen otherwise).
    public var railShortcuts = RailShortcuts()

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var s = AppSettings()
        func v<T: Decodable>(_ k: CodingKeys, _ cur: T) -> T { c.value(k, default: cur) }
        s.variant = v(.variant, s.variant); s.themeFollowsSystem = v(.themeFollowsSystem, s.themeFollowsSystem)
        s.surface = v(.surface, s.surface); s.density = v(.density, s.density)
        s.detailLayout = v(.detailLayout, s.detailLayout); s.boardLayout = v(.boardLayout, s.boardLayout)
        s.dateFormat = v(.dateFormat, s.dateFormat); s.companyTint = v(.companyTint, s.companyTint)
        s.localeCode = v(.localeCode, s.localeCode); s.translationLang = v(.translationLang, s.translationLang)
        s.translationModel = v(.translationModel, s.translationModel); s.fontFamily = v(.fontFamily, s.fontFamily)
        s.componentRadius = v(.componentRadius, s.componentRadius); s.chatAppearance = v(.chatAppearance, s.chatAppearance)
        s.chatPrimaryBubbles = v(.chatPrimaryBubbles, s.chatPrimaryBubbles); s.chatWallpaper = v(.chatWallpaper, s.chatWallpaper)
        s.chatWallpaperDim = v(.chatWallpaperDim, s.chatWallpaperDim); s.chatSendMarkdown = v(.chatSendMarkdown, s.chatSendMarkdown)
        s.chatNotifications = v(.chatNotifications, s.chatNotifications)
        s.chatNotifyWhileViewing = v(.chatNotifyWhileViewing, s.chatNotifyWhileViewing)
        s.chatSendTypingStatus = v(.chatSendTypingStatus, s.chatSendTypingStatus)
        s.chatReactions = v(.chatReactions, s.chatReactions); s.chatCacheLimitMb = v(.chatCacheLimitMb, s.chatCacheLimitMb)
        s.chatAutoDownloadVideos = v(.chatAutoDownloadVideos, s.chatAutoDownloadVideos)
        s.chatAutoDownloadVideoMb = v(.chatAutoDownloadVideoMb, s.chatAutoDownloadVideoMb)
        s.chatTextScale = v(.chatTextScale, s.chatTextScale); s.chatPrivacy = v(.chatPrivacy, s.chatPrivacy)
        s.chatLocalApi = v(.chatLocalApi, s.chatLocalApi)
        s.chatStickerSuggestions = v(.chatStickerSuggestions, s.chatStickerSuggestions); s.chatAiReplyRole = v(.chatAiReplyRole, s.chatAiReplyRole); s.miniAppLiveLimit = v(.miniAppLiveLimit, s.miniAppLiveLimit)
        s.miniAppNotifyInBackground = v(.miniAppNotifyInBackground, s.miniAppNotifyInBackground)
        s.miniAppBarsCollapsed = v(.miniAppBarsCollapsed, s.miniAppBarsCollapsed)
        s.accentColorValue = try? c.decodeIfPresent(Int.self, forKey: .accentColorValue)
        s.pinnedProjects = v(.pinnedProjects, s.pinnedProjects); s.pinnedExecutions = v(.pinnedExecutions, s.pinnedExecutions)
        s.teamExecutionVisibility = v(.teamExecutionVisibility, s.teamExecutionVisibility)
        s.sidebarWidth = v(.sidebarWidth, s.sidebarWidth); s.tableColumnWidths = v(.tableColumnWidths, s.tableColumnWidths)
        s.docsReaderBrightness = try? c.decodeIfPresent(String.self, forKey: .docsReaderBrightness)
        s.viewModes = v(.viewModes, s.viewModes); s.showPet = v(.showPet, s.showPet)
        s.petId = try? c.decodeIfPresent(String.self, forKey: .petId)
        s.petDisplay = v(.petDisplay, s.petDisplay); s.petFollowsCursor = v(.petFollowsCursor, s.petFollowsCursor)
        s.petShowsDetails = v(.petShowsDetails, s.petShowsDetails); s.petStaysWhenAppHides = v(.petStaysWhenAppHides, s.petStaysWhenAppHides)
        s.petClickGoesBack = v(.petClickGoesBack, s.petClickGoesBack); s.petScale = v(.petScale, s.petScale)
        s.petBehavior = v(.petBehavior, s.petBehavior); s.railShortcuts = v(.railShortcuts, s.railShortcuts)
        self = s
    }
}

public extension AppSettings {
    /// Puts every setting of the pet back as it comes. The pet chosen (`petId`) stays.
    mutating func resetPet() {
        let fresh = AppSettings()
        showPet = fresh.showPet; petDisplay = fresh.petDisplay; petFollowsCursor = fresh.petFollowsCursor
        petShowsDetails = fresh.petShowsDetails; petStaysWhenAppHides = fresh.petStaysWhenAppHides
        petClickGoesBack = fresh.petClickGoesBack; petScale = fresh.petScale; petBehavior = fresh.petBehavior
    }
}

public protocol SettingsRepository: Sendable {
    func load() async -> AppSettings
    func save(_ settings: AppSettings) async -> Outcome<Void>
    func watch() -> AsyncStream<AppSettings>
}
