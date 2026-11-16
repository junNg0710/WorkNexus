/// Ported from: lib/features/chat/presentation/providers (chatWallpaperPreviewProvider, shownChatWallpaperProvider)
import Foundation
import Observation

/// A wallpaper colour still being tried out in the settings picker: the chat background follows every step of a drag at once
/// (`ChatWallpaperView` shows `value` over the saved setting) while only where the drag stops is saved.
@MainActor @Observable
public final class ChatWallpaperPreview {
    public static let shared = ChatWallpaperPreview()
    public private(set) var value: String?
    private init() {}

    public func show(_ wallpaper: String) { value = wallpaper }
    public func clear() { value = nil }
    public func shows(_ wallpaper: String) -> Bool { value == wallpaper }

    /// What is on screen: the preview while one is shown, else the saved wallpaper.
    public func shown(saved: String) -> String { value ?? saved }
}
