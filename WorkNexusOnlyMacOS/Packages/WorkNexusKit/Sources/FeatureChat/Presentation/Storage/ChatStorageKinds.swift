/// Ported from: lib/features/chat/presentation/widgets/chat_storage_bar.dart (chatStorageKinds, the bar's segment maths)
import CoreDomain
import CoreUI
import SwiftUI

/// One kind of downloaded attachment in a storage breakdown.
struct ChatStorageKind: Equatable {
    var label: String
    var bytes: Int
    var color: Color
}

enum ChatStorageLogic {
    /// Bar resolution: segments are whole thousandths of the total.
    static let steps = 1000

    /// Photos, videos and files — the kinds every storage view splits into, each in its own colour so the bar, legend and
    /// rows read alike.
    static func kinds(imageBytes: Int, videoBytes: Int, fileBytes: Int, theme: AppTheme) -> [ChatStorageKind] {
        [ChatStorageKind(label: shellString("chatStoragePhotos", "Photos"), bytes: imageBytes, color: theme.colors.accent),
         ChatStorageKind(label: shellString("chatStorageVideos", "Videos"), bytes: videoBytes, color: theme.colors.violet),
         ChatStorageKind(label: shellString("chatStorageFiles", "Files"), bytes: fileBytes, color: theme.colors.amber)]
    }

    /// The share of each part, in thousandths of `total`; a used part always shows, however small next to the total.
    static func flexes(_ parts: [Int], total: Int) -> [Int] {
        parts.map { $0 <= 0 || total <= 0 ? 0 : min(max(Int((Double($0) * Double(steps) / Double(total)).rounded()), 1), steps) }
    }

    /// "42%" for a ratio of 0.42.
    static func percent(_ ratio: Double) -> String { "\(Int((ratio * 100).rounded()))%" }

    /// "Videos 80 MB · Photos 19 MB": largest first, empty kinds left out.
    static func split(_ kinds: [ChatStorageKind]) -> [ChatStorageKind] { kinds.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes } }

    /// A limit as a round figure: "512 MB", "2 GB" — never "512.0 MB".
    static func limitLabel(_ mb: Int) -> String { mb >= 1024 ? "\(mb / 1024) GB" : "\(mb) MB" }

    static let limitsMb = [512, 1024, 2048, 5120, 10240]
}

/// A bar for `total` bytes with one coloured segment per part, the rest of it the track.
struct ChatStorageBar: View {
    @Environment(\.appTheme) private var theme
    let total: Int
    let parts: [(bytes: Int, color: Color)]
    var height: CGFloat?

    var body: some View {
        let flexes = ChatStorageLogic.flexes(parts.map(\.bytes), total: total)
        let rest = max(0, ChatStorageLogic.steps - flexes.reduce(0, +))
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(parts.indices, id: \.self) { i in
                    if flexes[i] > 0 { parts[i].color.frame(width: geo.size.width * CGFloat(flexes[i]) / CGFloat(ChatStorageLogic.steps)) }
                }
                if rest > 0 { theme.colors.line.frame(width: geo.size.width * CGFloat(rest) / CGFloat(ChatStorageLogic.steps)) }
            }
        }
        .frame(height: height ?? theme.spacing.s8).clipShape(Capsule())
    }
}

/// The kinds' colours with their names and sizes, wrapping on narrow widths. Kinds with nothing stored are left out.
struct ChatStorageLegend: View {
    @Environment(\.appTheme) private var theme
    let kinds: [ChatStorageKind]

    var body: some View {
        FlowLayout(spacing: theme.spacing.s16) {
            ForEach(kinds.filter { $0.bytes > 0 }, id: \.label) { k in
                HStack(spacing: theme.spacing.s6) {
                    Circle().fill(k.color).frame(width: theme.spacing.s8, height: theme.spacing.s8)
                    Text(k.label).font(theme.typography.meta).foregroundStyle(theme.colors.tx)
                    Text(ChatShellLabels.fileSize(k.bytes)).font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
                }
            }
        }
    }
}
