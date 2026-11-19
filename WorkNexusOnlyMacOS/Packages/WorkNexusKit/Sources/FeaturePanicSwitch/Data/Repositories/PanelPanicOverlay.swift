import AppKit
import CoreDomain
import CoreUI
import Foundation

/// Ported from: lib/features/panic_switch/data/repositories/channel_panic_overlay.dart
/// `PanicOverlay` as its own always-on-top panel (`FloatingStickerPanel`): the app's window cannot float over other apps
/// while it may itself be hidden.
@MainActor
public final class PanelPanicOverlay: PanicOverlay {
    private let panel = FloatingStickerPanel(autosaveKey: "panic.floating")
    private var shownImage: Data?

    public var onClick: (@MainActor () -> Void)? {
        didSet { panel.onClick = { [weak self] in self?.onClick?() } }
    }

    public init() {}

    public func show(image: Data) -> Outcome<Void> {
        if panel.isShown, shownImage == image { return .success(()) }
        guard let picture = NSImage(data: image) else { return .failure(.parse("Floating button: the sticker is not an image")) }
        shownImage = image
        panel.show(image: picture)
        return .success(())
    }

    public func hide() { panel.hide() }
}
