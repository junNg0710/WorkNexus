import SwiftUI

/// Ported from: lib/core/widgets/zentao_kind_icon.dart
/// A ZenTao object's kind as a small tinted tile — a red bug, an accent task, an info story — so mixed lists
/// scan by colour. Unknown kinds (projects, docs…) get a neutral glyph.
public struct ZenTaoKindIcon: View {
    @Environment(\.appTheme) private var theme
    let objectType: String?; let large: Bool
    /// - Parameter objectType: the ZenTao `objectType` code (`bug`, `task`, `story`, `todo`…).
    public init(_ objectType: String?, large: Bool = false) { self.objectType = objectType; self.large = large }

    private var spec: (symbol: String, color: Color) {
        let c = theme.colors
        switch objectType?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "bug": return ("ladybug", c.red)
        case "task": return ("checklist", c.accent)
        case "story": return ("book", c.violet)
        case "todo": return ("list.bullet.clipboard", c.green)
        case "execution", "project": return ("rectangle.split.3x1", c.amber)
        default: return ("bell", c.tx3)
        }
    }

    public var body: some View {
        let side = large ? theme.sizes.control32 : theme.sizes.icon24
        Image(systemName: spec.symbol)
            .font(.system(size: large ? theme.sizes.icon16 : theme.sizes.icon14, weight: .medium)).foregroundStyle(spec.color)
            .frame(width: side, height: side)
            .background(spec.color.opacity(0.14), in: RoundedRectangle(cornerRadius: theme.radii.md))
    }
}
