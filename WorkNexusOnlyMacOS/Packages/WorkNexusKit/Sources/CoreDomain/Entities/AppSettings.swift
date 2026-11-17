import Foundation

/// Ported from: lib/core/settings/app_settings.dart (+ chat_appearance.dart). Persisted as one JSON row.
public enum ThemeVariant: String, Codable, CaseIterable, Sendable { case light, dark, midnight }
public enum SurfaceStyle: String, Codable, CaseIterable, Sendable { case flat, outline }
public enum AppDensity: String, Codable, CaseIterable, Sendable { case comfortable, compact }
public enum DetailLayout: String, Codable, CaseIterable, Sendable { case twoPane, tabbed }
public enum BoardLayout: String, Codable, CaseIterable, Sendable { case board, table }
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
    public var miniAppLiveLimit = 5
    public var miniAppNotifyInBackground = true
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
        s.chatTextScale = v(.chatTextScale, s.chatTextScale); s.miniAppLiveLimit = v(.miniAppLiveLimit, s.miniAppLiveLimit)
        s.miniAppNotifyInBackground = v(.miniAppNotifyInBackground, s.miniAppNotifyInBackground)
        s.accentColorValue = try? c.decodeIfPresent(Int.self, forKey: .accentColorValue)
        s.pinnedProjects = v(.pinnedProjects, s.pinnedProjects); s.pinnedExecutions = v(.pinnedExecutions, s.pinnedExecutions)
        s.teamExecutionVisibility = v(.teamExecutionVisibility, s.teamExecutionVisibility)
        s.sidebarWidth = v(.sidebarWidth, s.sidebarWidth); s.tableColumnWidths = v(.tableColumnWidths, s.tableColumnWidths)
        s.docsReaderBrightness = try? c.decodeIfPresent(String.self, forKey: .docsReaderBrightness)
        s.viewModes = v(.viewModes, s.viewModes); s.showPet = v(.showPet, s.showPet)
        self = s
    }
}

public protocol SettingsRepository: Sendable {
    func load() async -> AppSettings
    func save(_ settings: AppSettings) async -> Outcome<Void>
    func watch() -> AsyncStream<AppSettings>
}
