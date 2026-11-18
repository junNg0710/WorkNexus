import CoreDomain
import CoreUI
import FeatureChat
import SharedKit
import SwiftUI

/// Ported from: lib/features/chat/presentation/widgets/chat_local_api_settings.dart — connecting AI tools through the
/// bundled MCP server (the setup guide), and whether they may use chat through this app (the local chat API).
struct ChatAiToolsCard: View {
    @Environment(\.appTheme) private var theme
    let shell: ShellModel
    let mcp: McpSetupModel
    @State private var showingGuide = false

    var body: some View {
        SettingsCard(title: appString("chatLocalApiSection", "AI tools")) {
            AppButton(appString("mcpSetupOpen", "Connect an AI tool (MCP)"), systemImage: "powerplug") { showingGuide = true }
            ChatLocalApiToggle(shell: shell)
        }
        .appDialog(isPresented: $showingGuide) { McpSetupDialog(model: mcp) { showingGuide = false } }
    }
}

/// "Let local AI tools use chat" with its warning hint (here and in Quick Settings).
struct ChatLocalApiToggle: View {
    let shell: ShellModel

    var body: some View {
        SettingsToggleRow(label: appString("chatLocalApi", "Let local AI tools use chat"),
                          hint: appString("chatLocalApiHint", "Programs on this computer, such as an AI assistant's MCP server, can send chat messages as you, load older history and download files and images through this app, without your password. Only turn this on for tools you trust."),
                          isOn: shell.settings.chatLocalApi) { on in shell.updateSettings { $0.chatLocalApi = on } }
    }
}
