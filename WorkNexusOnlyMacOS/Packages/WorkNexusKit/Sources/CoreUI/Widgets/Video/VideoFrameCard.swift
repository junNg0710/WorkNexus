import AppKit
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/attachment_video_frame.dart
/// A video attached to a timeline entry, drawn as chat draws one: a 16:9 frame with a still (when one can be made),
/// its name and size along the top and a play disc in the middle. `loadStill` returns the still's image bytes (made
/// with `VideoThumbnailer` from the downloaded file); the card shows black until it arrives. A click calls `onTap`.
public struct VideoFrameCard: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let size: Int?
    let loadStill: (() async -> Data?)?
    let onTap: () -> Void
    @State private var still: NSImage?

    public init(title: String, size: Int?, loadStill: (() async -> Data?)? = nil, onTap: @escaping () -> Void) {
        self.title = title; self.size = size; self.loadStill = loadStill; self.onTap = onTap
    }

    public var body: some View {
        let c = theme.colors
        ZStack {
            // Black until a still is ready, as a player would be.
            Rectangle().fill(c.scrim)
            if let still { Image(nsImage: still).resizable().scaledToFill() }
            LinearGradient(colors: [c.scrim.opacity(0.6), c.scrim.opacity(0)], startPoint: .top, endPoint: .center)
            VStack {
                HStack(spacing: theme.spacing.s8) {
                    Text(title).font(theme.typography.label).foregroundStyle(c.onScrim).lineLimit(1)
                    Spacer(minLength: 0)
                    if let text = formatFileSize(size) { Text(text).font(theme.typography.caption).foregroundStyle(c.onScrim.opacity(0.85)) }
                }
                .padding(theme.spacing.s8)
                Spacer()
            }
            VideoPlayDisc()
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: theme.sizes.detailPanel - theme.spacing.s40 * 2)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg))
        .contentShape(RoundedRectangle(cornerRadius: theme.radii.lg))
        .onTapGesture(perform: onTap)
        .pointerStyle(.link)
        .task { if still == nil, let data = await loadStill?() { still = NSImage(data: data) } }
    }
}
