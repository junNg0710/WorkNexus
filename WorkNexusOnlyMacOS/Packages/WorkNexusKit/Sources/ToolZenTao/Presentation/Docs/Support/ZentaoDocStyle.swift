/// Ported from: the inline-style handling of `flutter_widget_from_html_core` as `zentao_doc_body.dart` uses it (font /
/// span colours, `background-color`, `text-align` / `align`, `bgcolor`, `font-weight` ...).
import CoreUI
import Foundation
import SwiftUI

/// A colour a document's HTML sets (text or background), kept as plain RGB so blocks stay `Equatable` and `Sendable`.
public struct ZentaoColor: Equatable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    public var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

    private static let named: [String: UInt32] = [
        "black": 0x000000, "white": 0xFFFFFF, "red": 0xFF0000, "green": 0x008000, "blue": 0x0000FF, "yellow": 0xFFFF00,
        "orange": 0xFFA500, "purple": 0x800080, "gray": 0x808080, "grey": 0x808080, "silver": 0xC0C0C0, "maroon": 0x800000,
        "navy": 0x000080, "teal": 0x008080, "lime": 0x00FF00, "aqua": 0x00FFFF, "cyan": 0x00FFFF, "fuchsia": 0xFF00FF,
        "magenta": 0xFF00FF, "olive": 0x808000, "brown": 0xA52A2A, "pink": 0xFFC0CB, "gold": 0xFFD700, "darkred": 0x8B0000,
        "darkblue": 0x00008B, "darkgreen": 0x006400, "lightgray": 0xD3D3D3, "lightgrey": 0xD3D3D3, "darkgray": 0xA9A9A9,
        "darkgrey": 0xA9A9A9, "crimson": 0xDC143C, "coral": 0xFF7F50, "indigo": 0x4B0082, "violet": 0xEE82EE,
        "whitesmoke": 0xF5F5F5, "lightyellow": 0xFFFFE0, "lightblue": 0xADD8E6, "lightgreen": 0x90EE90,
    ]

    /// `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb(r, g, b)` / `rgba(...)` or a common colour name; nil for anything else
    /// (`transparent`, `inherit`, a fully transparent colour ...).
    public init?(css: String) {
        let v = css.trimmingCharacters(in: .whitespaces).lowercased()
        func byte(_ n: UInt32) -> Double { Double(n & 0xFF) / 255 }
        if v.hasPrefix("#") {
            var hex = String(v.dropFirst())
            if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6 || hex.count == 8, let n = UInt32(hex, radix: 16) else { return nil }
            if hex.count == 8 {
                if n & 0xFF == 0 { return nil }
                self.init(r: byte(n >> 24), g: byte(n >> 16), b: byte(n >> 8))
            } else { self.init(r: byte(n >> 16), g: byte(n >> 8), b: byte(n)) }
        } else if v.hasPrefix("rgb") {
            let parts = v.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map(String.init)
            guard parts.count >= 3 else { return nil }
            func channel(_ s: String) -> Double? {
                if s.hasSuffix("%") { return Double(s.dropLast()).map { min(max($0 / 100, 0), 1) } }
                return Double(s).map { min(max($0 / 255, 0), 1) }
            }
            guard let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]) else { return nil }
            if parts.count > 3, let a = Double(parts[3].hasSuffix("%") ? String(parts[3].dropLast()) : parts[3]), a == 0 { return nil }
            self.init(r: r, g: g, b: b)
        } else if let n = Self.named[v] {
            self.init(r: byte(n >> 16), g: byte(n >> 8), b: byte(n))
        } else { return nil }
    }
}

/// Horizontal alignment of a block (`text-align`, the `align` attribute, `<center>`). `left` is the default.
public enum ZentaoDocAlign: Equatable, Sendable {
    case left, center, right

    init?(css: String) {
        switch css.trimmingCharacters(in: .whitespaces).lowercased() {
        case "center", "middle": self = .center
        case "right", "end": self = .right
        case "left", "start", "justify": self = .left
        default: return nil
        }
    }

    var text: TextAlignment { switch self { case .left: .leading; case .center: .center; case .right: .trailing } }
    var alignment: Alignment { switch self { case .left: .leading; case .center: .center; case .right: .trailing } }
}

/// Sub- and superscript runs.
public enum ZentaoScript: Equatable, Sendable { case sub, sup }

/// What an element's inline `style` (and its legacy attributes) asks for, as far as the reader draws it.
struct ZentaoCssStyle {
    var color: ZentaoColor?
    var background: ZentaoColor?
    var bold: Bool?
    var italic: Bool?
    var underline: Bool?
    var strike: Bool?
    var align: ZentaoDocAlign?

    init(_ node: HtmlNode) {
        let style = node.attr("style")
        func value(_ key: String) -> String? { Self.value(style, key) }
        if let c = value("color") { color = ZentaoColor(css: c) }
        if node.name == "font", let c = node.attr("color") { color = ZentaoColor(css: c) ?? color }
        if let b = value("background-color") ?? value("background") { background = ZentaoColor(css: b) }
        if let b = node.attr("bgcolor") { background = ZentaoColor(css: b) ?? background }
        if let w = value("font-weight")?.lowercased() { bold = w == "bold" || w == "bolder" || (Int(w).map { $0 >= 600 } ?? false) }
        if let f = value("font-style")?.lowercased() { italic = f == "italic" || f == "oblique" }
        if let d = value("text-decoration") ?? value("text-decoration-line") {
            let lower = d.lowercased()
            if lower.contains("underline") { underline = true }
            if lower.contains("line-through") { strike = true }
        }
        if let a = value("text-align") ?? node.attr("align") { align = ZentaoDocAlign(css: a) }
        if node.name == "center" { align = .center }
    }

    /// The value of declaration `key` in a `style` attribute.
    static func value(_ style: String?, _ key: String) -> String? {
        guard let style else { return nil }
        for decl in style.split(separator: ";") {
            let parts = decl.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].lowercased() == key { return parts[1].replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }
}
