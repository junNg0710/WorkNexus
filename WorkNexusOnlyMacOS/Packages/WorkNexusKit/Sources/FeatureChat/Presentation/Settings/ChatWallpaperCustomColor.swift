/// Ported from: lib/features/chat/presentation/widgets/chat_wallpaper_custom_color.dart
import CoreDomain
import CoreUI
import SwiftUI

/// A free wallpaper colour, picked right in the chat settings: the colour area, the hue bar and the hex field. The chat
/// background follows the colour while it is dragged (a preview), and it is saved once the picking pauses — or when the picker
/// closes.
struct ChatWallpaperCustomColor: View {
    /// How long a picked colour rests before it is saved.
    static let saveAfter: Duration = .milliseconds(400)

    @Environment(\.appTheme) private var theme
    let doodles: Bool
    let onSave: (String) -> Void
    @State private var color: HsvColor
    @State private var hex: String
    @State private var hexInvalid = false
    @State private var pending: String?
    @State private var saver: Task<Void, Never>?

    init(initial: ChatColor, doodles: Bool, onSave: @escaping (String) -> Void) {
        let hsv = HsvColor(hex: Self.hex(of: initial)) ?? HsvColor(h: 120, s: 0.3, v: 0.7)
        _color = State(initialValue: hsv); _hex = State(initialValue: hsv.hex)
        self.doodles = doodles; self.onSave = onSave
    }

    static func hex(of c: ChatColor) -> String {
        func b(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", b(c.r), b(c.g), b(c.b))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s12) {
            HsvSaturationValueArea(color: color, onChange: pick)
            HsvHueBar(color: color, onChange: pick)
            VStack(alignment: .leading, spacing: theme.spacing.s4) {
                Text(shellString("colorHex", "Hex")).font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
                TextField("#RRGGBB", text: Binding(get: { hex }, set: typed))
                    .textFieldStyle(.plain).font(theme.typography.body).padding(.horizontal, theme.spacing.s10)
                    .frame(height: theme.sizes.control36)
                    .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
                    .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(hexInvalid ? theme.colors.red : theme.colors.line, lineWidth: theme.borders.hairline))
                if hexInvalid { Text(shellString("colorHexInvalid", "Enter a colour like #1A2B3C")).font(theme.typography.caption).foregroundStyle(theme.colors.red) }
            }
        }
        .onDisappear { commitPending() }
    }

    /// From the area or the hue bar: the hex field follows.
    private func pick(_ next: HsvColor) { color = next; hex = next.hex; hexInvalid = false; show(next) }

    /// From the hex field: the area and bar follow once it parses.
    private func typed(_ text: String) {
        hex = text
        guard let parsed = HsvColor(hex: text) else { hexInvalid = true; return }
        hexInvalid = false
        // A grey has no hue of its own; keep the one in use.
        var next = parsed
        if next.s == 0 { next.h = color.h }
        color = next; show(next)
    }

    private func show(_ next: HsvColor) {
        let wallpaper = ChatWallpaperColor(next.hex, doodles: doodles).value
        pending = wallpaper
        ChatWallpaperPreview.shared.show(wallpaper)
        saver?.cancel()
        saver = Task {
            try? await Task.sleep(for: Self.saveAfter)
            if !Task.isCancelled { commit(wallpaper) }
        }
    }

    private func commit(_ wallpaper: String) {
        onSave(wallpaper); ChatWallpaperPreview.shared.clear(); pending = nil
    }

    /// Saved unless another choice cleared the preview meanwhile.
    private func commitPending() {
        saver?.cancel()
        if let pending, ChatWallpaperPreview.shared.shows(pending) { commit(pending) }
    }
}
