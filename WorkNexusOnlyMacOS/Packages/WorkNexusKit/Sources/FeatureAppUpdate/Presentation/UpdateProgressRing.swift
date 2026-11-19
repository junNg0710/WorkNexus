import CoreUI
import SwiftUI

/// Ported from: lib/features/app_update/presentation/widgets/update_rail_button.dart (`_ProgressIcon`)
/// The update arrow inside a ring that fills with `progress` (0…1) while the update downloads, or spins when `progress` is
/// nil (installing).
public struct UpdateProgressRing: View {
    @Environment(\.appTheme) private var theme
    @State private var spinning = false
    let progress: Double?

    public init(progress: Double?) { self.progress = progress }

    public var body: some View {
        let side = theme.sizes.icon24, stroke = theme.borders.thick
        ZStack {
            Circle().stroke(theme.colors.line, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: progress.map { max(0.02, min(1, $0)) } ?? 0.3)
                .stroke(theme.colors.accent, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90 + (spinning ? 360 : 0)))
                // Eases between the model's 1 % steps.
                .animation(.easeOut(duration: theme.motion.base), value: progress)
            Image(systemName: "arrow.up").font(.system(size: theme.sizes.icon12, weight: .semibold))
                .foregroundStyle(theme.colors.accent)
        }
        .frame(width: side - stroke, height: side - stroke)
        .frame(width: side, height: side)
        .onAppear { startSpinning(progress == nil) }
        .onChange(of: progress == nil) { _, indeterminate in startSpinning(indeterminate) }
    }

    private func startSpinning(_ on: Bool) {
        if on {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spinning = true }
        } else {
            spinning = false
        }
    }
}
