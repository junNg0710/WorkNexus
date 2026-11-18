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

/// The menu itself; it reads the draft (rewrites need something typed), so only it redraws as the user types.
private struct ChatAiMenu: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatSettings) private var settings
    @State private var hovering = false
    let controller: ChatComposerController
    let state: ChatThreadState

    private var inThread: Bool { controller.threadRootId != nil }

    var body: some View {
        Menu {
            Button { controller.suggestReplies() } label: {
                Label(appString("chatAiSuggestReplies", "Suggest replies"), systemImage: "text.bubble")
            }
            // Rewriting needs something typed.
            if !controller.model.isBlank {
                Divider()
                ForEach(ChatDraftTone.allCases, id: \.self) { tone in
                    Button { controller.rewrite(tone) } label: { Label(Self.label(tone), systemImage: "wand.and.stars") }
                }
            }
            Divider()
            // The summary is of the chat itself, not of a reply thread.
            if !inThread {
                Button { state.sidePanel = .assistant } label: {
                    Label(appString("chatAiOpenAssistant", "Summarize with AI"), systemImage: "text.alignleft")
                }
            }
            Toggle(isOn: Binding(get: { settings.stickerSuggestions }, set: { controller.setStickerSuggestions($0) })) {
                Label(appString("chatStickerSuggestionsSetting", "Sticker suggestions"), systemImage: "face.smiling")
            }
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: theme.sizes.icon18))
                .foregroundStyle(theme.colors.tx2)
                .frame(width: theme.sizes.control36, height: theme.sizes.control36)
                .background(hovering ? theme.colors.panel2 : .clear, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .onHover { hovering = $0 }
        .help(appString("chatAiTools", "AI tools"))
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
