/// Ported from: lib/core/widgets/hsv_color_fields.dart + swatch_button.dart (+ hexOf / parseHexColor of custom_color_dialog.dart)
import SwiftUI

/// A colour as hue (0-360), saturation and value (0-1) — what the picker's area and bar edit — with the `#RRGGBB` text form.
public struct HsvColor: Equatable, Sendable {
    public var h: Double
    public var s: Double
    public var v: Double
    public init(h: Double, s: Double, v: Double) { self.h = h; self.s = s; self.v = v }

    /// `#RRGGBB` (the `#` is optional, case does not matter); nil for anything else.
    public init?(hex: String) {
        guard let (r, g, b) = Self.parseHex(hex) else { return nil }
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var hue = 0.0
        if d > 0 {
            if mx == r { hue = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { hue = (b - r) / d + 2 }
            else { hue = (r - g) / d + 4 }
            hue *= 60
            if hue < 0 { hue += 360 }
        }
        self.init(h: hue, s: mx == 0 ? 0 : d / mx, v: mx)
    }

    public static func parseHex(_ text: String) -> (Double, Double, Double)? {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6, let n = UInt32(t, radix: 16) else { return nil }
        return (Double((n >> 16) & 0xFF) / 255, Double((n >> 8) & 0xFF) / 255, Double(n & 0xFF) / 255)
    }

    public var rgb: (r: Double, g: Double, b: Double) {
        let c = v * s, hp = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double)
        switch hp {
        case ..<1: (r, g, b) = (c, x, 0)
        case ..<2: (r, g, b) = (x, c, 0)
        case ..<3: (r, g, b) = (0, c, x)
        case ..<4: (r, g, b) = (0, x, c)
        case ..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }

    /// `#RRGGBB`, upper case.
    public var hex: String {
        let (r, g, b) = rgb
        func byte(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    public var color: Color { let (r, g, b) = rgb; return Color(.sRGB, red: r, green: g, blue: b) }
}

/// The saturation/value square of a colour picker: the hue's colour fading to white to the left and to black downwards.
public struct HsvSaturationValueArea: View {
    @Environment(\.appTheme) private var theme
    let color: HsvColor
    let onChange: (HsvColor) -> Void
    public init(color: HsvColor, onChange: @escaping (HsvColor) -> Void) { self.color = color; self.onChange = onChange }

    public var body: some View {
        GeometryReader { geo in
            let pure = HsvColor(h: color.h, s: 1, v: 1).color
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [.white, pure], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                HsvThumb(fill: color.color)
                    .position(x: geo.size.width * color.s, y: geo.size.height * (1 - color.v))
            }
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.md))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                var c = color
                c.s = min(max(g.location.x / max(geo.size.width, 1), 0), 1)
                c.v = 1 - min(max(g.location.y / max(geo.size.height, 1), 0), 1)
                onChange(c)
            })
        }
        .frame(height: theme.sizes.dialogSm / 2.5)
    }
}

/// The hue strip under the area.
public struct HsvHueBar: View {
    @Environment(\.appTheme) private var theme
    let color: HsvColor
    let onChange: (HsvColor) -> Void
    public init(color: HsvColor, onChange: @escaping (HsvColor) -> Void) { self.color = color; self.onChange = onChange }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                LinearGradient(colors: stride(from: 0.0, through: 360, by: 60).map { HsvColor(h: $0, s: 1, v: 1).color },
                               startPoint: .leading, endPoint: .trailing)
                    .clipShape(Capsule())
                HsvThumb(fill: HsvColor(h: color.h, s: 1, v: 1).color).position(x: geo.size.width * color.h / 360, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                var c = color
                c.h = min(max(g.location.x / max(geo.size.width, 1), 0), 1) * 360
                onChange(c)
            })
        }
        .frame(height: theme.sizes.icon20)
    }
}

private struct HsvThumb: View {
    @Environment(\.appTheme) private var theme
    let fill: Color
    var body: some View {
        Circle().fill(fill).frame(width: theme.sizes.icon16, height: theme.sizes.icon16)
            .overlay(Circle().stroke(theme.colors.onScrim, lineWidth: theme.borders.thick))
            .shadow(color: theme.colors.scrim.opacity(0.4), radius: theme.borders.thick)
    }
}

/// One round colour swatch with a ring when `selected`; with no `color` it is the "pick your own" button (a plus).
public struct AppSwatchButton: View {
    @Environment(\.appTheme) private var theme
    let size: CGFloat
    let color: Color?
    let selected: Bool
    let help: String?
    let action: () -> Void

    public init(size: CGFloat, color: Color?, selected: Bool, help: String? = nil, action: @escaping () -> Void) {
        self.size = size; self.color = color; self.selected = selected; self.help = help; self.action = action
    }

    public var body: some View {
        HoverRegion { hovered in
            Button(action: action) {
                ZStack {
                    Circle().fill(color ?? theme.colors.panel2)
                    Circle().stroke(color == nil ? theme.colors.line2 : theme.colors.scrim.opacity(0.12), lineWidth: theme.borders.hairline)
                    if color == nil { Image(systemName: "plus").font(.system(size: size * 0.45)).foregroundStyle(theme.colors.tx2) }
                }
                .padding(theme.borders.medium + theme.borders.hairline)
                .overlay(Circle().stroke(selected ? theme.colors.tx : (hovered ? theme.colors.line2 : .clear), lineWidth: theme.borders.thick))
                .frame(width: size, height: size)
            }
            .buttonStyle(.plain)
        }
        .help(help ?? "")
    }
}
