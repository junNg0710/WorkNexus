import CoreDomain
import Foundation

/// Public entry point of FeaturePanicSwitch (lib/features/panic_switch, wired in lib/app/di/service_locator.dart): the
/// composition root builds the model once, hands it a chat gateway (adapted from the chat repository) and starts it.
public enum PanicSwitchFeature {
    public static let name = "FeaturePanicSwitch"

    /// - Parameters:
    ///   - settingsFile: where the settings JSON is kept (`<Application Support>/panic_switch.json`).
    ///   - sticker: the bundled `Stickers/WorkNexus/thay_vo.png`.
    ///   - chats: chat, through the panic switch's own interface.
    ///   - accounts: the accounts, again each time they change.
    @MainActor
    public static func makeModel(settingsFile: URL, sticker: URL?, chats: PanicChatGateway,
                                 accounts: @escaping @Sendable () -> AsyncStream<[Account]>) -> PanicSwitchModel {
        PanicSwitchModel(PanicSwitchDependencies(
            repository: FilePanicSwitchConfigRepository(url: settingsFile), chats: chats, apps: WorkspaceAppSwitcher(),
            overlay: PanelPanicOverlay(), sticker: FilePanicStickerSource(url: sticker), accounts: accounts))
    }
}
