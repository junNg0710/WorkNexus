import Observation
import SwiftUI

/// Whether the chat list and the info panel are collapsed. Both are user choices that survive relaunch: collapsing them is
/// how you keep names, avatars and member lists off the screen (screen sharing, someone looking over your shoulder).
@MainActor @Observable
final class ChatPanelVisibility {
    var listHidden: Bool { didSet { UserDefaults.standard.set(listHidden, forKey: Self.listKey) } }
    var infoHidden: Bool { didSet { UserDefaults.standard.set(infoHidden, forKey: Self.infoKey) } }

    private static let listKey = "chat.listHidden"
    private static let infoKey = "chat.infoHidden"

    init() {
        listHidden = UserDefaults.standard.bool(forKey: Self.listKey)
        infoHidden = UserDefaults.standard.bool(forKey: Self.infoKey)
    }
}

private struct ChatPanelVisibilityKey: EnvironmentKey {
    @MainActor static let defaultValue = ChatPanelVisibility()
}
extension EnvironmentValues {
    var chatPanelVisibility: ChatPanelVisibility {
        get { self[ChatPanelVisibilityKey.self] }
        set { self[ChatPanelVisibilityKey.self] = newValue }
    }
}
