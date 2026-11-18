import CoreDomain
import CoreUI
import SwiftUI

/// One line on the Node.js the MCP server needs: found and recent enough, too old, or missing — plus a warning when it comes
/// from a version manager, whose path breaks once that version is switched away from or removed.
/// Ported from: lib/features/chat/presentation/widgets/mcp_setup_node_status.dart
struct McpSetupNodeStatus: View {
    @Environment(\.appTheme) private var theme
    let setup: McpSetup

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            let line = Self.line(setup)
            McpSetupStatusLine(icon: line.icon, color: line.tone.color(theme), text: line.text)
            if setup.nodeFromVersionManager {
                McpSetupStatusLine(icon: "info.circle", color: theme.colors.amber, text: appString("mcpSetupNodeVersionManager", "This Node.js belongs to one version of a version manager (nvm, fnm, asdf, …). If you switch away from or remove that version, the AI tool can no longer start the server: open this guide again and register it with the new path."))
            }
        }
    }

    enum Tone {
        case ok, warning, error
        func color(_ theme: AppTheme) -> Color {
            switch self { case .ok: theme.colors.green; case .warning: theme.colors.amber; case .error: theme.colors.red }
        }
    }

    /// The status line's icon, tone and text for `setup`.
    static func line(_ setup: McpSetup) -> (icon: String, tone: Tone, text: String) {
        let min = "\(McpSetup.minNode.major).\(McpSetup.minNode.minor)"
        switch (setup.nodeVersion, setup.nodePath) {
        case (let v?, let p?) where setup.nodeSupported:
            return ("checkmark.circle", .ok, appFormat("mcpSetupNodeFound", "Node.js %1$@ at %2$@", v, p))
        case (let v?, _):
            return ("exclamationmark.triangle", .warning, appFormat("mcpSetupNodeOld", "Node.js %1$@ is too old: the MCP server needs %2$@ or newer.", v, min))
        default:
            return ("xmark.circle", .error, appFormat("mcpSetupNodeMissing", "Node.js was not found. Install Node.js %1$@ or newer, then open this guide again.", min))
        }
    }
}

private struct McpSetupStatusLine: View {
    @Environment(\.appTheme) private var theme
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.s10) {
            Image(systemName: icon).font(.system(size: theme.sizes.icon16)).foregroundStyle(color)
            Text(text).font(theme.typography.body).foregroundStyle(theme.colors.tx).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
