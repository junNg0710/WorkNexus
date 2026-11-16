import AppKit
import SwiftUI

/// Ported from: lib/core/widgets/workspace_badge.dart
/// Small square workspace badge with its chosen icon, falling back to the short code (initials).
public struct WorkspaceBadge: View {
    @Environment(\.appTheme) private var theme
    let color: Color; let short: String; let big: Bool; let iconKey: String?

    public init(_ color: Color, _ short: String, big: Bool = false, iconKey: String? = nil) {
        self.color = color; self.short = short; self.big = big; self.iconKey = iconKey
    }

    public var body: some View {
        let side = big ? theme.sizes.icon18 : theme.sizes.icon16
        ZStack {
            color
            if let data = WorkspaceIcons.imageData(iconKey), let img = NSImage(data: data) {
                Image(nsImage: img).resizable().scaledToFill()
            } else if let symbol = WorkspaceIcons.symbol(iconKey) {
                Image(systemName: symbol).font(.system(size: big ? theme.sizes.icon12 : 10, weight: .semibold))
                    .foregroundStyle(theme.colors.onColorInk)
            } else {
                Text(short).font(theme.typography.badge).foregroundStyle(theme.colors.onColorInk).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.xs))
    }
}

/// Ported from: lib/core/widgets/workspace_badge.dart (`workspaceIcon*` helpers).
public enum WorkspaceIcons {
    public static let keys = ["briefcase", "home", "building", "rocket", "code", "storage"]
    /// The workspace colour choices (0xAARRGGBB), in picker order.
    public static let colorChoices: [UInt32] = [0xFF16A99C, 0xFFCF8A3A, 0xFF8F63D6, 0xFF3B82F6, 0xFFE05561, 0xFF2F8A52, 0xFFDC2626, 0xFF0891B2]

    /// SF Symbol standing in for the Lucide glyph of an icon key; nil for an unknown / custom-image key.
    public static func symbol(_ key: String?) -> String? {
        switch key {
        case "briefcase": "briefcase"
        case "home": "house"
        case "building": "building.2"
        case "rocket": "paperplane"
        case "code": "chevron.left.forwardslash.chevron.right"
        case "storage": "cylinder"
        default: nil
        }
    }

    /// A custom icon is stored as a `data:image/…;base64,…` key.
    public static func imageData(_ key: String?) -> Data? {
        guard let key, key.hasPrefix("data:image/"), let marker = key.range(of: "base64,") else { return nil }
        return Data(base64Encoded: String(key[marker.upperBound...])).flatMap { $0.isEmpty ? nil : $0 }
    }
}
