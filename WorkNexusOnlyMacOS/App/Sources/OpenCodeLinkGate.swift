import CoreDomain
import CoreUI
import FeatureTranslation
import Foundation
import Observation
import SwiftUI

/// Ported from: lib/core/widgets/opencode_not_linked_dialog.dart (`ensureOpenCodeLinked`, `OpenCodeNotLinkedDialog`)
/// The check every translation passes first: a usable API key, or an OpenCode with an authenticated provider. When neither is
/// there the "OpenCode not linked" dialog explains how to link it and the translation does not start, rather than failing with
/// a raw CLI error. Used by the ticket translation footer and the chat message translation.
@MainActor @Observable
final class OpenCodeLinkGate {
    static let shared = OpenCodeLinkGate()
    var isShowingDialog = false
    @ObservationIgnored private var check: CheckTranslationReady?
    /// "Open settings" in the dialog: the translation settings page.
    @ObservationIgnored var openSettings: () -> Void = {}

    private init() {}

    func install(feature: TranslationFeature, openSettings: @escaping () -> Void) {
        check = CheckTranslationReady(apiConfig: feature.apiConfig, cli: feature.openCodeCli)
        self.openSettings = openSettings
    }

    /// True when a translation can run; otherwise shows the dialog and returns false.
    func ensureLinked() async -> Bool {
        guard let check else { return true }
        if await check() { return true }
        isShowingDialog = true
        return false
    }
}

/// Explains how to link OpenCode when no provider is authenticated: run the CLI login, or switch translation to an API-key
/// provider in Settings.
struct OpenCodeNotLinkedDialog: View {
    @Environment(\.appTheme) private var theme
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        AppDialogFrame(title: appString("openCodeNotLinkedTitle", "OpenCode not linked"), maxWidth: theme.sizes.dialogSm, onClose: onClose) {
            VStack(alignment: .leading, spacing: theme.spacing.s12) {
                Text(appString("openCodeNotLinkedBody", "No authenticated OpenCode provider was found. Add an API key under Settings → Translation, run the command below in a terminal, or pick another translation provider (Gemini, Groq, …)."))
                    .font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2)
                Text("opencode auth login").font(theme.typography.mono).foregroundStyle(theme.colors.tx).textSelection(.enabled)
                    .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
                    .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
            }
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s24)
        } actions: {
            Spacer(minLength: 0)
            AppButton(appString("gotIt", "Got it"), kind: .ghost, action: onClose)
            AppButton(appString("openCodeOpenSettings", "Open settings"), systemImage: "gearshape", kind: .primary, action: onOpenSettings)
        }
    }
}

/// Presents the "OpenCode not linked" dialog (window-level) whenever the gate asks for it.
struct OpenCodeLinkGateHost: ViewModifier {
    @Bindable var gate: OpenCodeLinkGate

    func body(content: Content) -> some View {
        content.appDialog(isPresented: $gate.isShowingDialog) {
            OpenCodeNotLinkedDialog(onClose: { gate.isShowingDialog = false },
                                    onOpenSettings: { gate.isShowingDialog = false; gate.openSettings() })
        }
    }
}

extension View {
    func openCodeLinkGate(_ gate: OpenCodeLinkGate) -> some View { modifier(OpenCodeLinkGateHost(gate: gate)) }
}
