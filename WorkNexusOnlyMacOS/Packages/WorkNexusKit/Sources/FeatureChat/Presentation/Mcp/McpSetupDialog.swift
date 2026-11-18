import CoreDomain
import CoreUI
import SwiftUI

/// The MCP setup guide: whether Node.js is ready, then the command / config entry for each AI tool, with absolute paths
/// filled in. Present it with `.appDialog`; it prepares the server each time it appears.
/// Ported from: lib/features/chat/presentation/widgets/mcp_setup_dialog.dart
public struct McpSetupDialog: View {
    @Environment(\.appTheme) private var theme
    let model: McpSetupModel
    let onClose: () -> Void

    static let nodeDownloadUrl = "https://nodejs.org/en/download"

    public init(model: McpSetupModel, onClose: @escaping () -> Void) { self.model = model; self.onClose = onClose }

    public var body: some View {
        AppDialogFrame(title: appString("mcpSetupTitle", "Connect an AI tool"), leadingIcon: "powerplug", maxWidth: theme.sizes.dialogLg,
                       onClose: onClose) {
            // The guide scrolls inside the dialog rather than growing past a laptop screen.
            McpSetupContent(state: model.state).frame(maxHeight: theme.sizes.dialogLg * 7 / 8)
        } actions: {
            Spacer()
            if model.nodeMissing {
                AppButton(appString("mcpSetupGetNode", "Get Node.js"), systemImage: "arrow.down.circle", kind: .ghost) {
                    _ = openExternally(Self.nodeDownloadUrl)
                }
            }
            AppButton(appString("gotIt", "Got it"), kind: .primary, action: onClose)
        }
        .task { await model.load() }
    }
}

/// The guide's body for each state: a spinner, the error, or the guide itself.
private struct McpSetupContent: View {
    @Environment(\.appTheme) private var theme
    let state: McpSetupModel.State

    var body: some View {
        switch state {
        case .loading: AppInlineSpinner().padding(theme.spacing.s24)
        case .failed(let message):
            VStack(alignment: .leading, spacing: theme.spacing.s6) {
                Text(appString("mcpSetupFailed", "Could not prepare the MCP server")).font(theme.typography.bodyStrong)
                    .foregroundStyle(theme.colors.tx)
                AppInlineNote(message, isError: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s24)
        case .ready(let setup, let configs): McpSetupGuide(setup: setup, configs: configs)
        }
    }
}

private struct McpSetupGuide: View {
    @Environment(\.appTheme) private var theme
    let setup: McpSetup
    let configs: [McpClientConfig]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                McpSetupNote(text: appString("mcpSetupIntro", "WorkNexus comes with an MCP server: add it to Claude or another MCP-capable assistant, and it can list, read and search your ZenTao chats (and TBChat, when installed), send messages, load older history and open files and images."))
                McpSetupNodeStatus(setup: setup).padding(.top, theme.spacing.s16)
                ForEach(configs, id: \.client) { config in
                    McpSetupClientSection(config: config).padding(.top, theme.spacing.s20)
                }
                McpSetupNote(text: appString("mcpSetupSendNote", "Reading what WorkNexus already stored works right away. To let the assistant send messages, load older history and open files and images, also turn on \"Let local AI tools use chat\" below. WorkNexus must be running for that."))
                    .padding(.top, theme.spacing.s20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s24)
        }
    }
}

/// A paragraph of the guide's explanatory text.
private struct McpSetupNote: View {
    @Environment(\.appTheme) private var theme
    let text: String
    var body: some View {
        Text(text).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2).fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}
