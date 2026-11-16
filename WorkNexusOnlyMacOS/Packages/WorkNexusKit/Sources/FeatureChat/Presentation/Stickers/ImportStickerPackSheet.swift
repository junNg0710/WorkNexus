/// Ported from: lib/features/chat/presentation/widgets/import_sticker_pack_dialog.dart
import CoreUI
import SwiftUI

/// Asks for a Telegram sticker-set link and a bot token (kept on this device), then imports the set in the background.
struct ImportStickerPackSheet: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var token = ""
    @State private var savedToken: String?
    @State private var changingToken = false
    @State private var checking = false
    @State private var error: String?
    @State private var tokenError: String?

    private var usingSaved: Bool { savedToken != nil && !changingToken }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s12) {
            Text(appString("stickerImportTitle", "Add a Telegram sticker set")).font(theme.typography.titleSm).foregroundStyle(theme.colors.tx)
            Text(appString("stickerImportLink", "Sticker set link")).font(theme.typography.label).foregroundStyle(theme.colors.tx2)
            TextField(appString("stickerImportLinkHint", "https://t.me/addstickers/…"), text: $link).textFieldStyle(.roundedBorder)
            if usingSaved {
                HStack {
                    Text(appString("stickerImportTokenSaved", "Using the saved bot token")).font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
                    Spacer()
                    AppButton(appString("stickerImportChangeToken", "Change"), kind: .ghost) { changingToken = true }
                }
            } else {
                Text(appString("stickerImportToken", "Telegram bot token")).font(theme.typography.label).foregroundStyle(theme.colors.tx2)
                SecureField("", text: $token).textFieldStyle(.roundedBorder).onSubmit(submit)
                if let tokenError { Text(tokenError).font(theme.typography.meta).foregroundStyle(theme.colors.red) }
                Text(appString("stickerImportTokenHelp", "Create a bot with @BotFather to get one. It is kept only on this device."))
                    .font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
            }
            if checking { Text(appString("stickerImportChecking", "Checking the link…")).font(theme.typography.meta).foregroundStyle(theme.colors.tx2) }
            if let error { Text(error).font(theme.typography.meta).foregroundStyle(theme.colors.red) }
            HStack {
                Spacer()
                AppButton(appString("chatCancel", "Cancel")) { dismiss() }
                AppButton(appString("stickerImportAction", "Add set"), kind: .primary, action: submit)
            }
        }
        .padding(theme.spacing.s20)
        .frame(width: theme.sizes.dialogMd)
        .background(theme.colors.card)
        .task { savedToken = await services?.telegramTokens?.read(); if savedToken?.isEmpty == true { savedToken = nil } }
    }

    private func submit() {
        guard !checking, let importer = services?.stickerImport else { error = appString("stickerImportFailed", "The sticker set could not be added."); return }
        guard ParseStickerPackLink()(link) != nil else { error = appString("stickerImportBadLink", "Paste a link like https://t.me/addstickers/Name"); return }
        let chosen = usingSaved ? (savedToken ?? "") : token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chosen.isEmpty else { error = appString("stickerImportToken", "Telegram bot token"); return }
        error = nil; tokenError = nil; checking = true
        StickerImportJobs.shared.start(link: link, token: chosen, using: importer, tokens: services?.telegramTokens) { result in
            checking = false
            switch result {
            case .success: dismiss()
            case .failure(let f):
                switch StickerImportErrors.shown(for: f) {
                case .token(let message): changingToken = true; tokenError = message
                case .general(let message): error = message
                }
            }
        }
    }
}
