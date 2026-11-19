/// Ported from: lib/features/chat/presentation/widgets/chat_ai_compose_button.dart
import CoreUI
import SwiftUI

/// The composer's ✨ tool, the one place for the chat's AI help: asks the AI for replies to the latest messages (shown above
/// the input to pick from), rewrites what is typed — clearer, more formal, friendlier or shorter —, opens the chat summary
/// beside the chat, and turns the sticker suggestions over the input on or off. A spinner stands in while a rewrite runs.
struct ChatAiComposeButton: View {
    @Environment(\.appTheme) private var theme
    let controller: ChatComposerController
    let state: ChatThreadState

    var body: some View {
        if controller.ai.rewriting {
            ProgressView().controlSize(.small)
                .frame(width: theme.sizes.control36, height: theme.sizes.control36)
                .help(appString("chatAiRewriting", "Rewriting…"))
        } else {
            ChatAiMenu(controller: controller, state: state)
        }
    }
}

/// The menu itself. Its entries (rewrites need something typed) are read when it is pressed, so typing doesn't redraw it.
private struct ChatAiMenu: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatSettings) private var settings
    @State private var hovering = false
    let controller: ChatComposerController
    let state: ChatThreadState

    private var inThread: Bool { controller.threadRootId != nil }

    var body: some View {
        AppMenuButton(help: appString("chatAiTools", "AI tools"), items: menuItems) {
            Image(systemName: "sparkles")
                .font(.system(size: theme.sizes.icon18))
                .foregroundStyle(theme.colors.tx2)
                .frame(width: theme.sizes.control36, height: theme.sizes.control36)
                .background(hovering ? theme.colors.panel2 : .clear, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .contentShape(Rectangle())
        }
        .fixedSize()
        .onHover { hovering = $0 }
    }

    private func menuItems() -> [AppNativeMenu.Item] {
        var out = [AppNativeMenu.Item(appString("chatAiSuggestReplies", "Suggest replies"), icon: "text.bubble") { controller.suggestReplies() },
                   replyAsMenu()]
        // Rewriting needs something typed.
        if !controller.model.isBlank {
            for (i, tone) in ChatDraftTone.allCases.enumerated() {
                out.append(.init(Self.label(tone), icon: "wand.and.stars", dividerBefore: i == 0) { controller.rewrite(tone) })
            }
        }
        // The summary is of the chat itself, not of a reply thread.
        if !inThread {
            out.append(.init(appString("chatAiOpenAssistant", "Summarize with AI"), icon: "text.alignleft", dividerBefore: true) {
                state.sidePanel = .assistant
            })
        }
        let stickers = settings.stickerSuggestions
        out.append(.init(appString("chatStickerSuggestionsSetting", "Sticker suggestions"), icon: "face.smiling", dividerBefore: inThread,
                         checked: stickers) { controller.setStickerSuggestions(!stickers) })
        return out
    }

    /// "Reply as ▸": whose voice the reply ideas take — the ZenTao role (named) or one picked.
    private func replyAsMenu() -> AppNativeMenu.Item {
        let current = settings.replyRole
        let code = state.selfUserId.flatMap { state.users[$0]?.role }.flatMap { $0.isEmpty ? nil : $0 }
        let detected = code.map { ChatShellLabels.roleLabel($0, serverNames: state.roleNames) }
        let auto = detected.map { appFormat("chatAiReplyRoleAutoNamed", "From ZenTao (%1$@)", $0) }
            ?? appString("chatAiReplyRoleAuto", "From ZenTao")
        var items = [AppNativeMenu.Item(auto, checked: current == .auto) { controller.setReplyRole(.auto) }]
        for (i, role) in ChatReplyRole.picks.enumerated() {
            items.append(.init(Self.label(role), dividerBefore: i == 0, checked: current == role) { controller.setReplyRole(role) })
        }
        return AppNativeMenu.Item(appString("chatAiReplyAs", "Reply as"), icon: "person.text.rectangle", children: items)
    }

    static func label(_ role: ChatReplyRole) -> String {
        switch role {
        case .auto: appString("chatAiReplyRoleAuto", "From ZenTao")
        case .techLead: appString("chatAiRoleTechLead", "Tech lead")
        case .developer: appString("chatAiRoleDeveloper", "Developer")
        case .tester: appString("chatAiRoleTester", "Tester (QA)")
        case .projectManager: appString("chatAiRolePm", "Project manager")
        case .productOwner: appString("chatAiRolePo", "Product owner")
        case .designer: appString("chatAiRoleDesigner", "Designer (UI/UX)")
        case .businessAnalyst: appString("chatAiRoleBa", "Business analyst")
        }
    }

    static func label(_ tone: ChatDraftTone) -> String {
        switch tone {
        case .clearer: appString("chatAiRewriteClearer", "Make it clearer")
        case .formal: appString("chatAiRewriteFormal", "More formal")
        case .friendly: appString("chatAiRewriteFriendly", "Friendlier")
        case .shorter: appString("chatAiRewriteShorter", "Shorter")
        }
    }
}
