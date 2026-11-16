import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/editor_columns.dart
/// The editor's layout: the text (`main`) beside the fields (`side`) when there is room, as ZenTao's web form lays
/// them out; one column below that.
struct EditorColumns<Main: View, Side: View>: View {
    @Environment(\.appTheme) private var theme
    /// Below this width the fields go under the text.
    static var twoColumns: CGFloat { 900 }
    @ViewBuilder let main: Main
    @ViewBuilder let side: Side

    var body: some View {
        GeometryReader { box in
            let wide = box.size.width >= Self.twoColumns
            ScrollView {
                if wide {
                    HStack(alignment: .top, spacing: theme.spacing.s24) {
                        VStack(spacing: theme.spacing.s20) { main }
                        VStack(spacing: theme.spacing.s20) { side }
                            .frame(width: min(max(box.size.width * 0.3, 300), 380))
                    }
                    .padding(theme.spacing.s24)
                } else {
                    VStack(spacing: theme.spacing.s24) { main; side }.padding(theme.spacing.s24)
                }
            }
        }
    }
}
