import CoreDomain
import SwiftUI

/// How the chat view fits its width: whether the info panel stays open beside a chat (it only gives way when there is no
/// room), and whether the chat list narrows. A panel opened without room slides over the messages instead.
/// Ported from: lib/features/chat/presentation/widgets/chat_layout.dart
struct ChatShellLayout: Equatable {
    static let listWidth: CGFloat = 320
    static let listCompactWidth: CGFloat = 240
    static let messagesMinWidth: CGFloat = 520
    static let panelRoom: CGFloat = 380
    static let sidePanelWidth: CGFloat = 340
    /// The widest the column of messages grows; beyond it the window's extra width is margin.
    static let messageColumnWidth: CGFloat = 1040
    static let headerHeight: CGFloat = 68
    static let subHeaderHeight: CGFloat = 56

    var infoRoom: Bool
    var compactList: Bool
    /// Whether the info panel would fit beside the chat (true even while the user has it collapsed).
    var infoFits = false

    static func of(width: CGFloat, withList: Bool = true, infoHidden: Bool = false) -> ChatShellLayout {
        let list = withList ? listWidth : 0
        let fits = width - list - panelRoom >= messagesMinWidth
        let infoRoom = fits && !infoHidden
        let panel = infoRoom ? panelRoom : 0
        return ChatShellLayout(infoRoom: infoRoom, compactList: width - list - panel < messagesMinWidth, infoFits: fits)
    }
}

private struct ChatShellLayoutKey: EnvironmentKey { static let defaultValue = ChatShellLayout(infoRoom: false, compactList: false) }
extension EnvironmentValues {
    var chatShellLayout: ChatShellLayout {
        get { self[ChatShellLayoutKey.self] }
        set { self[ChatShellLayoutKey.self] = newValue }
    }
}

/// The side-panel rules of one open chat: one panel at a time; with room the info panel is always there.
/// Ported from: lib/features/chat/presentation/widgets/chat_panels.dart
extension ChatThreadState {
    /// The panel shown beside the chat: the one the user opened, else the info panel when there is room for it.
    func effectivePanel(infoRoom: Bool) -> ChatSidePanel? {
        if let sidePanel, sidePanel != .search { return sidePanel }
        return infoRoom ? .info : nil
    }

    /// Opens `panel` (closing a reply thread), or closes it when it is already open; with room, "closing" returns to info.
    func togglePanel(_ panel: ChatSidePanel, infoRoom: Bool) {
        let shown = effectivePanel(infoRoom: infoRoom)
        sidePanel = shown == panel || (infoRoom && panel == .info) ? nil : panel
    }

    /// From pinned messages or files back to the chat info.
    func backToInfo(infoRoom: Bool) { sidePanel = infoRoom ? nil : .info }

    func closePanel() { sidePanel = nil }
}
