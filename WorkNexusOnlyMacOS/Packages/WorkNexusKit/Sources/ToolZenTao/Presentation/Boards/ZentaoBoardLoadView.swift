import CoreUI
import SharedKit
import SwiftUI

/// Only the handover from placeholders to tickets animates. Later page, filter and sync updates keep their positions.
struct ZentaoBoardLoadView<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let loading: Bool
    let list: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            if loading {
                if list { TableSkeleton() } else { BoardSkeleton() }
            } else {
                content()
            }
        }
        .contentArrival(on: loading, backdrop: theme.colors.bg, enabled: !loading)
    }
}
