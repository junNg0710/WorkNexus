import CoreDomain
import CoreUI
import FeatureChat
import SharedKit
import SwiftUI

/// Ported from: lib/features/chat/presentation/widgets/chat_appearance_settings.dart + the chat cards of Quick Settings:
/// the chat's look (style, accent bubbles, the wallpaper picker, text size), messaging, notifications and the downloaded
/// files' limit and auto-download, and AI tools (the MCP setup guide and the local chat API).
struct ChatSettingsPage: View {
    let shell: ShellModel
    let mcp: McpSetupModel

    var body: some View {
        let s = shell.settings
        SettingsPage(title: appString("chat", "Chat")) {
            SettingsCard(title: appString("chatAppearanceCard", "Chat appearance")) {
                ChatStylePicker { v in shell.updateSettings { $0.chatAppearance = v } }
                // The default style already follows the app's colours.
                SettingsToggleRow(label: appString("chatPrimaryBubbles", "Use the accent colour for my bubbles"),
                                  hint: appString("chatPrimaryBubblesHint", "Telegram, Zalo, ZenTao and WeChat use the app's accent colour for your messages. The default style always follows the app's colours."),
                                  isOn: s.chatPrimaryBubbles) { on in shell.updateSettings { $0.chatPrimaryBubbles = on } }
                    .disabled(s.chatAppearance == .worknexus)
                ChatWallpaperPicker(onSelect: { v in shell.updateSettings { $0.chatWallpaper = v } },
                                    onDim: { v in shell.updateSettings { $0.chatWallpaperDim = v } })
                SettingsRow(label: appString("chatTextSize", "Text size")) {
                    SettingsSlider(value: s.chatTextScale, range: 0.8...1.4, format: { "\(Int($0 * 100))%" }) { v in shell.updateSettings { $0.chatTextScale = v } }
                }
            }
            SettingsCard(title: appString("chatMessaging", "Messaging")) {
                SettingsToggleRow(label: appString("chatSendMarkdown", "Send messages as Markdown"), isOn: s.chatSendMarkdown) { on in shell.updateSettings { $0.chatSendMarkdown = on } }
                SettingsToggleRow(label: appString("chatSendTyping", "Let others see when I'm typing"), isOn: s.chatSendTypingStatus) { on in shell.updateSettings { $0.chatSendTypingStatus = on } }
                SettingsToggleRow(label: appString("chatReactions", "Reactions"),
                                  hint: appString("chatReactionsHint", "Show a reply that is just an emoji as a reaction under the message it answers, and react to messages."),
                                  isOn: s.chatReactions) { on in shell.updateSettings { $0.chatReactions = on } }
            }
            SettingsCard(title: appString("notifications", "Notifications")) {
                SettingsToggleRow(label: appString("chatNotify", "Notify about new messages"), isOn: s.chatNotifications) { on in shell.updateSettings { $0.chatNotifications = on } }
                SettingsToggleRow(label: appString("chatNotifyViewing", "Also while I'm looking at the chat"), isOn: s.chatNotifyWhileViewing) { on in shell.updateSettings { $0.chatNotifyWhileViewing = on } }
            }
            SettingsCard(title: appString("chatStorage", "Downloaded chat files")) {
                SettingsRow(label: appString("chatCacheLimit", "Cache size limit")) {
                    AppDropdown(value: s.chatCacheLimitMb, values: [512, 1024, 2048, 5120, 10240], labelOf: { $0 >= 1024 ? "\($0 / 1024) GB" : "\($0) MB" }) { v in
                        shell.updateSettings { $0.chatCacheLimitMb = v }
                    }
                }
                SettingsToggleRow(label: appString("chatAutoDownloadVideos", "Download videos automatically"), isOn: s.chatAutoDownloadVideos) { on in shell.updateSettings { $0.chatAutoDownloadVideos = on } }
                SettingsRow(label: appString("chatAutoDownloadUpTo", "Up to")) {
                    AppDropdown(value: s.chatAutoDownloadVideoMb, values: [5, 10, 20, 50, 100], labelOf: { "\($0) MB" }) { v in shell.updateSettings { $0.chatAutoDownloadVideoMb = v } }
                }
                // What is stored per chat, and "clear all", is under Local data.
            }
            ChatAiToolsCard(shell: shell, mcp: mcp)
        }
    }
}
