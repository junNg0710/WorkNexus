/// Ported from: lib/features/panic_switch/domain/value_objects/panic_trigger.dart
/// The two triggers of the panic switch, running side by side, each with its own sticker, chat and debounce.
public enum PanicTrigger: String, Sendable, CaseIterable, Hashable {
    /// The team's group, with the "Thầy vô" sticker: the pet's gesture.
    case release
    /// The demo chat, with the demo sticker, only in demo mode: "Demo" in the pet's right-click menu.
    case demo

    /// The reserved name the sticker travels under, which receivers tell the two triggers apart by.
    public var stickerFileName: String {
        switch self {
        case .release: PanicSwitchConstants.stickerFileName
        case .demo: PanicSwitchConstants.demoStickerFileName
        }
    }

    /// The trigger whose sticker is called `name` (in any case), if any.
    public static func ofSticker(_ name: String) -> PanicTrigger? {
        let lower = name.lowercased()
        return allCases.first { $0.stickerFileName == lower }
    }
}
