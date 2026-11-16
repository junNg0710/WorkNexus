/// Ported from: lib/features/chat/presentation/widgets/chat_profile_tap.dart, forward_message_dialog.dart, save_sticker_action.dart (hooks)
import CoreDomain
import CoreUI
import SwiftUI

/// What the thread asks the rest of the chat UI to do, because the thing lives in another slice (profile dialog, forward
/// dialog, sticker store). The Shell passes these to `MessageListView(state:actions:)`; every hook is optional.
public struct ChatThreadActions {
    /// Opens a user's profile (tapping an avatar, a name or a mention).
    public var openProfile: (_ userId: Int) -> Void
    /// Opens the "forward to…" picker for a message.
    public var forward: ((ChatMessage) -> Void)?
    /// Saves an image message as a sticker.
    public var saveAsSticker: ((ChatMessage) -> Void)?
    /// Starts a ZenTao bug, task or todo from the messages (nil: the host cannot make them).
    public var createTicket: ((ChatTicketKind, [ChatMessage]) -> Void)?

    public init(openProfile: @escaping (Int) -> Void = { _ in }, forward: ((ChatMessage) -> Void)? = nil,
                saveAsSticker: ((ChatMessage) -> Void)? = nil, createTicket: ((ChatTicketKind, [ChatMessage]) -> Void)? = nil) {
        self.openProfile = openProfile; self.forward = forward; self.saveAsSticker = saveAsSticker; self.createTicket = createTicket
    }
}

private struct ChatThreadActionsKey: EnvironmentKey { static let defaultValue = ChatThreadActions() }
public extension EnvironmentValues {
    /// The hooks `MessageListView` uses when it is not given its own `actions` (set once near the chat root).
    var chatThreadActions: ChatThreadActions {
        get { self[ChatThreadActionsKey.self] }
        set { self[ChatThreadActionsKey.self] = newValue }
    }
}

public extension View {
    func chatThreadActions(_ actions: ChatThreadActions) -> some View { environment(\.chatThreadActions, actions) }
}

/// Everything a row of the message list needs: the timeline model (messages, reactions, summaries), the shared thread
/// state, the services and the hooks to other slices.
@MainActor struct ThreadContext {
    let model: MessageTimelineModel
    let actions: ChatThreadActions
    var state: ChatThreadState { model.state }
    var services: ChatServices { model.services }
    var accountId: String { model.accountId }
    var users: [Int: ChatUser] { model.state.users }

    /// The sender's name; your own messages read "You" while your profile is unknown.
    func name(of message: ChatMessage) -> String {
        message.isMine && users[message.senderId] == nil ? L.you : ChatTextLabels.userName(users, message.senderId)
    }

    func name(of userId: Int) -> String { ChatTextLabels.userName(users, userId) }

    /// Starts a reply to `message` (shown above the composer).
    func reply(to message: ChatMessage) { state.replyDraft = message }

    func openThread(_ rootServerId: Int) { state.sidePanel = .thread(rootServerId: rootServerId) }

    /// Opens a link tapped in chat: a ticket opens inside the app, anything else in the browser.
    func openLink(_ url: String) { ChatLinkOpener.open(url, services: services) }
}

enum ChatLinkOpener {
    /// A ZenTao / GitLab / GitHub item the app knows opens in the detail panel beside the chat; anything else (or one that
    /// cannot be loaded) opens in the browser.
    static func open(_ url: String, services: ChatServices) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            if let lookup = services.ticketLookup, let ticket = await lookup(trimmed), let open = services.openTicket {
                open(ticket)
                return
            }
            if let u = URL(string: trimmed) { services.openURL(u) }
        }
    }
}
