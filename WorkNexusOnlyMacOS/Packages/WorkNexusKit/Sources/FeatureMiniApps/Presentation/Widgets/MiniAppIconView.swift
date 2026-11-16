import AppKit
import CoreUI
import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_icon.dart
/// A mini app's icon image, or its name's initial on the accent when it has none.
struct MiniAppIconView: View {
    @Environment(\.appTheme) private var theme
    let app: MiniApp
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let path = app.iconPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Text(String(app.name.first.map { String($0).uppercased() } ?? "?"))
                    .font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(theme.colors.accentTx)
                    .frame(width: size, height: size).background(theme.colors.accent)
            }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: theme.radii.sm))
    }
}
