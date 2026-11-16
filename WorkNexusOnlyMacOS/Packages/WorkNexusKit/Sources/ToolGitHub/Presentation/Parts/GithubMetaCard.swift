import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/provider_detail_sections.dart (`DetailMetaCard`)
/// The metadata card of a detail sidebar: a titled hairline key/value table with the empty rows filtered out (nothing
/// at all when every row is empty).
struct GithubMetaCard: View {
    let title: String
    let rows: [(String, String)]
    var valueViews: [String: AnyView] = [:]

    var body: some View {
        let filled = rows.filter { !$0.1.trimmingCharacters(in: .whitespaces).isEmpty }
        if !filled.isEmpty { DetailFieldsCard(title: title, rows: filled, valueViews: valueViews) }
    }
}
