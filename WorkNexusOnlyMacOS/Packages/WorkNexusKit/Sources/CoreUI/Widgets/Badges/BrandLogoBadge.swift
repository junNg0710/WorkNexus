import AppKit
import CoreDomain
import SwiftUI

/// Ported from: lib/core/widgets/badges.dart (provider logo) — the SVGs in `App/Resources/Brands` are bundled
/// into the app; they are read from the main bundle (NSImage renders SVG), with a letter tile as a fallback when
/// they are not there (tests, previews).
public enum BrandLogos {
    private static var cache: [String: NSImage] = [:]

    /// Bundle resource name for a provider (`zentao`, `gitlab`, `github`, `jira`).
    public static func resourceName(_ type: ProviderType) -> String { type.rawValue }

    @MainActor public static func image(for type: ProviderType, bundle: Bundle = .main) -> NSImage? {
        let name = resourceName(type)
        if let hit = cache[name] { return hit }
        let candidates = [
            bundle.url(forResource: name, withExtension: "svg", subdirectory: "Brands"),
            bundle.url(forResource: name, withExtension: "svg"),
            bundle.url(forResource: name, withExtension: "svg", subdirectory: "Resources/Brands"),
        ]
        for case let url? in candidates {
            if let img = NSImage(contentsOf: url) { cache[name] = img; return img }
        }
        return nil
    }
}

/// A provider's logo as a small rounded square.
public struct BrandLogoBadge: View {
    @Environment(\.appTheme) private var theme
    let providerType: ProviderType; let size: CGFloat
    public init(_ providerType: ProviderType, size: CGFloat = 20) { self.providerType = providerType; self.size = size }

    public var body: some View {
        Group {
            if let img = BrandLogos.image(for: providerType) {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                Text(providerType.code).font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(theme.colors.accentTx).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.colors.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.sm))
        .accessibilityLabel(providerType.displayName)
    }
}
