import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/core/widgets/quick_settings_{side_panel,panel}.dart — the title bar gear's popover. Two tabs: General
/// (Appearance with app name and icon, Layout, Language & region, Storage) and Chat (the chat's own look, notifications and
/// downloads). "All settings" opens the Settings place.
struct QuickSettingsView: View {
    private enum Tab { case general, chat }
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let root: CompositionRoot
    @State private var tab: Tab = .general

    var body: some View {
        let shell = root.shell
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: theme.spacing.s12) {
                Text(appString("quickSettings", "Quick settings")).font(theme.typography.titleSm).foregroundStyle(theme.colors.tx)
                AppSegmentedTabs([
                    AppSegmentedTab(label: appString("quickSettingsGeneral", "General"), active: tab == .general) { tab = .general },
                    AppSegmentedTab(label: appString("chat", "Chat"), active: tab == .chat) { tab = .chat },
                ])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.spacing.s16).padding(.vertical, theme.spacing.s12)
            Divider().overlay(theme.colors.line)
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.s20) {
                    switch tab {
                    case .general: general(shell)
                    case .chat: QuickSettingsChatTab(shell: shell)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.spacing.s16)
            }
            .id(tab)
            Divider().overlay(theme.colors.line)
            HStack {
                AppButton(appString("storageTitle", "Storage & cache"), systemImage: "internaldrive", kind: .ghost) {
                    shell.nav.select(.settings); shell.nav.setSettingsSection("cache"); dismiss()
                }
                Spacer()
                AppButton(appString("allSettings", "All settings"), systemImage: "gearshape", kind: .secondary) {
                    shell.nav.select(.settings); dismiss()
                }
            }
            .padding(theme.spacing.s12)
        }
        .frame(width: theme.sizes.dialogMd, height: theme.sizes.dialogLg - theme.spacing.s16)
        .background(theme.colors.card)
    }

    @ViewBuilder private func general(_ shell: ShellModel) -> some View {
        QuickSettingsGroup(title: appString("appearance", "Appearance")) {
            AppearanceControls(shell: shell)
            AppIdentityControls(root: root)
        }
        QuickSettingsGroup(title: appString("quickSettingsLayout", "Layout")) { LayoutRegionControls(shell: shell) }
    }
}

/// A titled group of the quick settings.
struct QuickSettingsGroup<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s12) {
            Text(title.uppercased()).font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
            content
        }
    }
}

/// The Chat tab: how the chat looks, what it notifies about, what it downloads.
struct QuickSettingsChatTab: View {
    @Environment(\.dismiss) private var dismiss
    let shell: ShellModel

    var body: some View {
        let s = shell.settings
        QuickSettingsGroup(title: appString("chatAppearanceCard", "Chat appearance")) {
            SettingsRow(label: appString("chatStyle", "Style")) {
                AppDropdown(value: s.chatAppearance, values: ChatAppearance.allCases, labelOf: { $0.rawValue.capitalized }) { v in
                    shell.updateSettings { $0.chatAppearance = v }
                }
            }
            SettingsToggleRow(label: appString("chatPrimaryBubbles", "Use the accent colour for my bubbles"), isOn: s.chatPrimaryBubbles) { on in
                shell.updateSettings { $0.chatPrimaryBubbles = on }
            }
            SettingsRow(label: appString("chatTextSize", "Text size")) {
                SettingsSlider(value: s.chatTextScale, range: 0.8...1.4, format: { "\(Int($0 * 100))%" }) { v in shell.updateSettings { $0.chatTextScale = v } }
            }
        }
        QuickSettingsGroup(title: appString("notifications", "Notifications")) {
            SettingsToggleRow(label: appString("chatNotify", "Notify about new messages"), isOn: s.chatNotifications) { on in shell.updateSettings { $0.chatNotifications = on } }
            SettingsToggleRow(label: appString("chatNotifyViewing", "Also while I'm looking at the chat"), isOn: s.chatNotifyWhileViewing) { on in shell.updateSettings { $0.chatNotifyWhileViewing = on } }
        }
        QuickSettingsGroup(title: appString("chatStorage", "Downloaded chat files")) {
            SettingsToggleRow(label: appString("chatAutoDownloadVideos", "Download videos automatically"), isOn: s.chatAutoDownloadVideos) { on in shell.updateSettings { $0.chatAutoDownloadVideos = on } }
            SettingsToggleRow(label: appString("chatSendTyping", "Let others see when I'm typing"), isOn: s.chatSendTypingStatus) { on in shell.updateSettings { $0.chatSendTypingStatus = on } }
        }
        QuickSettingsGroup(title: appString("chatLocalApiSection", "AI tools")) {
            // The setup guide is a dialog of its own: it opens from Settings › Chat.
            AppButton(appString("mcpSetupOpen", "Connect an AI tool (MCP)"), systemImage: "powerplug", kind: .ghost) {
                shell.nav.select(.settings); shell.nav.setSettingsSection("chat"); dismiss()
            }
            ChatLocalApiToggle(shell: shell)
        }
    }
}
