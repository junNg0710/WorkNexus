/// Ported from: lib/core/widgets/app_page.dart
import CoreUI
import SwiftUI

/// A full page of the workspace (Overview, Integrations): the same margins, content width and title on each, so
/// moving between them nothing jumps. The `title` and `subtitle` head the content, with an optional action on the
/// right (`trailing`).
struct PageFrame<Trailing: View, Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let subtitle: String?
    let trailing: Trailing
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.trailing = trailing(); self.content = content()
    }

    var body: some View {
        let s = theme.spacing
        ScrollView {
            VStack(alignment: .leading, spacing: s.s20) {
                HStack(alignment: .top, spacing: s.s10) {
                    VStack(alignment: .leading, spacing: s.s4) {
                        Text(title).font(theme.typography.display).foregroundStyle(theme.colors.tx)
                        if let subtitle { Text(subtitle).font(theme.typography.meta).foregroundStyle(theme.colors.tx2) }
                    }
                    Spacer(minLength: 0)
                    trailing
                }
                content
            }
            .frame(maxWidth: OverviewLayout.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, s.s24).padding(.top, s.s20).padding(.bottom, s.s24)
        }
        .background(theme.colors.bg)
    }
}
