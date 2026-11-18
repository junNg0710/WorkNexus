import CoreDomain
import CoreUI
import FeatureTranslation
import Foundation
import Observation
import SwiftUI

/// Ported from: lib/core/widgets/opencode_not_linked_dialog.dart (`ensureOpenCodeLinked`, `OpenCodeNotLinkedDialog`); per purpose
/// and with saved API providers: not in the Flutter app.
/// The check every AI run passes first: the provider chosen for its purpose is usable (a key, or one it does not need), or it
/// runs on an OpenCode with an authenticated provider. When it is not, a dialog explains how to fix it and the run does not
/// start, rather than failing with a raw CLI error. Used by the ticket translation footer, chat message translation and the
/// chat's AI help.
@MainActor @Observable
final class OpenCodeLinkGate {
    static let shared = OpenCodeLinkGate()
    /// What the dialog explains; nil while it is closed.
    var problem: AiSetupProblem?
    @ObservationIgnored private var check: CheckTranslationReady?
    /// "Open settings" in the dialog: the translation settings page.
    @ObservationIgnored var openSettings: () -> Void = {}

    private init() {}

    func install(feature: TranslationFeature, openSettings: @escaping () -> Void) {
        check = CheckTranslationReady(setup: feature.aiSetup, cli: feature.openCodeCli)
        self.openSettings = openSettings
    }

    /// True when a run for `purpose` can start; otherwise shows the dialog and returns false.
    func ensureLinked(_ purpose: AiPurpose = .translation) async -> Bool {
        guard let check else { return true }
        let readiness = await check.readiness(purpose)
        if readiness == .ready { return true }
        problem = AiSetupProblem(purpose: purpose, readiness: readiness)
        return false
    }
}

/// Why an AI run of `purpose` could not start.
struct AiSetupProblem: Equatable {
    let purpose: AiPurpose
    let readiness: AiReadiness
}

/// Explains what to set up: link OpenCode (the CLI login) when the run would go to OpenCode, or finish the chosen provider;
/// either way another provider can be picked in Settings.
struct OpenCodeNotLinkedDialog: View {
    @Environment(\.appTheme) private var theme
    let problem: AiSetupProblem
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    private var title: String {
        if case .providerNotUsable(let name) = problem.readiness { return appFormat("aiProviderNotReadyTitle", "%1$@ is not set up", name) }
        return appString("openCodeNotLinkedTitle", "OpenCode not linked")
    }

    private var message: String {
        switch (problem.readiness, problem.purpose) {
        case (.providerNotUsable(let name), .chat):
            appFormat("aiProviderNotReadyChatBody", "AI in chat runs on %1$@, which has no API key or model yet. Add them under Settings → Translation, or pick another provider for AI in chat.", name)
        case (.providerNotUsable(let name), _):
            appFormat("aiProviderNotReadyTranslationBody", "Translation runs on %1$@, which has no API key or model yet. Add them under Settings → Translation, or pick another translation provider.", name)
        case (_, .chat):
            appString("openCodeNotLinkedChatBody", "AI in chat runs on OpenCode, and no authenticated OpenCode provider was found. Run the command below in a terminal, or pick an API provider for AI in chat under Settings → Translation.")
        default:
            appString("openCodeNotLinkedBody", "No authenticated OpenCode provider was found. Add an API key under Settings → Translation, run the command below in a terminal, or pick another translation provider (Gemini, Groq, …).")
        }
    }

    var body: some View {
        AppDialogFrame(title: title, maxWidth: theme.sizes.dialogSm, onClose: onClose) {
            VStack(alignment: .leading, spacing: theme.spacing.s12) {
                Text(message).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2).fixedSize(horizontal: false, vertical: true)
                if problem.readiness == .openCodeNotLinked {
                    Text("opencode auth login").font(theme.typography.mono).foregroundStyle(theme.colors.tx).textSelection(.enabled)
                        .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
                        .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
                }
            }
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s24)
        } actions: {
            Spacer(minLength: 0)
            AppButton(appString("gotIt", "Got it"), kind: .ghost, action: onClose)
            AppButton(appString("openCodeOpenSettings", "Open settings"), systemImage: "gearshape", kind: .primary, action: onOpenSettings)
        }
    }
}

/// Presents the dialog (window-level) whenever the gate asks for it.
struct OpenCodeLinkGateHost: ViewModifier {
    @Bindable var gate: OpenCodeLinkGate

    func body(content: Content) -> some View {
        content.appDialog(item: $gate.problem) { problem in
            OpenCodeNotLinkedDialog(problem: problem, onClose: { gate.problem = nil },
                                    onOpenSettings: { gate.problem = nil; gate.openSettings() })
        }
    }
}

extension View {
    func openCodeLinkGate(_ gate: OpenCodeLinkGate) -> some View { modifier(OpenCodeLinkGateHost(gate: gate)) }
}
