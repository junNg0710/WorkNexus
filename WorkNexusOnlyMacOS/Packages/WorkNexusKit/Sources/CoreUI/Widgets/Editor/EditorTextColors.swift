import SwiftUI

/// Ported from: lib/core/util/editor_text_colors.dart (+ the helpers of editor_color_button.dart)
/// The colours offered for text and its highlight in the rich-text editor, as the `#rrggbb` values written into
/// the document (content data, not theme colours). Rows run light, strong, deep, then the greys; six columns so the
/// picker lays them out as a grid.
public enum EditorTextColors {
    public static let swatches = [
        "#bfedd2", "#fbeeb8", "#f8cac6", "#eccafa", "#c2e0f4", "#ffffff",
        "#2dc26b", "#f1c40f", "#e03e2d", "#b96ad9", "#3598db", "#ced4d9",
        "#169179", "#e67e23", "#ba372a", "#843fa1", "#236fa1", "#95a5a6",
        "#0e5e4c", "#a04f0c", "#7a1f17", "#4f1f66", "#163e5e", "#000000",
    ]

    /// Columns of the `swatches` grid.
    public static let columns = 6

    /// `css` as lower-case `#rrggbb` when it is a `#rgb` or `#rrggbb` colour (what the editor writes), else nil.
    public static func normalized(_ css: String?) -> String? {
        guard var t = css?.trimmingCharacters(in: .whitespaces).lowercased(), t.hasPrefix("#") else { return nil }
        t.removeFirst()
        if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
        guard t.count == 6, t.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + t
    }

    /// Whether a check drawn on `hex` should be black (a light swatch) rather than white.
    public static func prefersDarkInk(on hex: String) -> Bool {
        guard let (r, g, b) = HsvColor.parseHex(hex) else { return true }
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) > 0.5
    }
}
