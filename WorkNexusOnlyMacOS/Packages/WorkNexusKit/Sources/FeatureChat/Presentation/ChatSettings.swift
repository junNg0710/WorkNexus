import CoreDomain
import SwiftUI

/// The `AppSettings` fields chat reads (the host injects them with `.chatSettings(_:)` whenever settings change).
/// Ported from: lib/core/settings/{app_settings,chat_appearance}.dart (chat* fields)
public struct ChatSettings: Equatable, Sendable {
    public var appearance: ChatAppearance = .worknexus
    public var primaryBubbles = false
    public var wallpaper = "pattern"
    public var wallpaperDim: Double = 0.2
    public var sendMarkdown = false
    public var notifications = true
    public var notifyWhileViewing = true
    public var sendTypingStatus = true
    public var reactions = false
    public var cacheLimitMb = 2048
    public var autoDownloadVideos = true
    public var autoDownloadVideoMb = 20
    public var textScale: Double = 1
    public var translationLang = "vi"
    public var translationModel = ""

    public init() {}
    public init(_ s: AppSettings) {
        appearance = s.chatAppearance; primaryBubbles = s.chatPrimaryBubbles; wallpaper = s.chatWallpaper
        wallpaperDim = s.chatWallpaperDim; sendMarkdown = s.chatSendMarkdown; notifications = s.chatNotifications
        notifyWhileViewing = s.chatNotifyWhileViewing; sendTypingStatus = s.chatSendTypingStatus; reactions = s.chatReactions
        cacheLimitMb = s.chatCacheLimitMb; autoDownloadVideos = s.chatAutoDownloadVideos
        autoDownloadVideoMb = s.chatAutoDownloadVideoMb; textScale = s.chatTextScale
        translationLang = s.translationLang; translationModel = s.translationModel
    }
}

private struct ChatSettingsKey: EnvironmentKey { static let defaultValue = ChatSettings() }
public extension EnvironmentValues {
    var chatSettings: ChatSettings {
        get { self[ChatSettingsKey.self] }
        set { self[ChatSettingsKey.self] = newValue }
    }
}

public extension View {
    func chatSettings(_ settings: ChatSettings) -> some View { environment(\.chatSettings, settings) }
}
