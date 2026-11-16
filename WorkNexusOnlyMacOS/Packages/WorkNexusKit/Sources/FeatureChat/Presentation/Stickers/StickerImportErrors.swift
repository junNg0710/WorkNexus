/// Ported from: lib/features/chat/presentation/widgets/import_sticker_pack_dialog.dart (the failure → message switch)
import CoreDomain
import CoreUI

/// What the import dialog tells the user for each way an import fails: a refused token is shown at the token field (and the
/// field opens for a new one); the rest are one line under the form.
enum StickerImportErrors {
    enum Shown: Equatable { case token(String), general(String) }

    static func shown(for failure: CoreDomain.Failure) -> Shown {
        switch failure {
        case .auth: .token(appString("stickerImportBadToken", "Telegram refused this bot token."))
        case .notFound: .general(appString("stickerImportNoSet", "No sticker set has this link."))
        case .network: .general(appString("stickerImportNetwork", "Telegram could not be reached."))
        case .validation: .general(appString("stickerImportBadLink", "Paste a link like https://t.me/addstickers/Name"))
        default: .general(appString("stickerImportFailed", "The sticker set could not be added."))
        }
    }
}
