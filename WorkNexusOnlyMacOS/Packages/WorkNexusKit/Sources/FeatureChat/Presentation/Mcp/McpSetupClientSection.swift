import CoreUI
import SwiftUI

/// How to register the MCP server with one AI tool: a heading, where it goes, and the command or config entry to copy.
/// Ported from: lib/features/chat/presentation/widgets/mcp_setup_client_section.dart
struct McpSetupClientSection: View {
    @Environment(\.appTheme) private var theme
    let config: McpClientConfig

    var body: some View {
        let texts = Self.texts(config)
        VStack(alignment: .leading, spacing: 0) {
            Text(texts.title).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
            Text(texts.hint).font(theme.typography.meta).foregroundStyle(theme.colors.tx2).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled).padding(.top, theme.spacing.s4)
            CodeBlock(config.snippet, fontSize: Self.codeSize).padding(.top, theme.spacing.s10)
        }
    }

    /// The size of `AppTypography.mono`, which `CodeBlock` takes as a number.
    private static let codeSize: CGFloat = 12

    /// The heading and the hint of `config`'s tool.
    static func texts(_ config: McpClientConfig) -> (title: String, hint: String) {
        switch config.client {
        case .claudeCode:
            return (appString("mcpSetupClaudeCode", "Claude Code"),
                    appString("mcpSetupClaudeCodeHint", "Run in a terminal, then start a new Claude Code session."))
        case .claudeDesktop:
            return (appString("mcpSetupClaudeDesktop", "Claude Desktop"),
                    appFormat("mcpSetupClaudeDesktopHint", "Add to %1$@ (merge into its \"mcpServers\" if it has one), then restart Claude Desktop.",
                              config.configFile ?? ""))
        case .other:
            return (appString("mcpSetupOtherClient", "Other MCP clients"),
                    appString("mcpSetupOtherClientHint", "Cursor, Windsurf and others take the same entry in their MCP settings."))
        }
    }
}
