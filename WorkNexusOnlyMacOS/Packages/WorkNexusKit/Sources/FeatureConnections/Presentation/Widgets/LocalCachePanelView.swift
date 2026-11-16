import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/connections/presentation/widgets/{local_cache_panel,local_cache_section_row}.dart
/// The synced data kept in the local database, by section, every one picked to start with; "Clear" drops the
/// picked ones and hands them to `onCleared` - the app resyncs them, which reaches into features this one must
/// not know. The local-data part of the app's storage dialog.
public struct LocalCachePanelView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    @State private var picked = Set(CacheSection.allCases)
    @State private var clearing = false
    let model: ConnectionsModel
    let onCleared: (Set<CacheSection>) -> Void

    init(model: ConnectionsModel, onCleared: @escaping (Set<CacheSection>) -> Void) {
        self.model = model; self.onCleared = onCleared
    }

    public var body: some View {
        let c = theme.colors, s = theme.spacing
        VStack(alignment: .leading, spacing: s.s12) {
            Text(L.cacheDbHint).font(theme.typography.caption).foregroundStyle(c.tx2)
            VStack(spacing: 0) {
                ForEach(Array(CacheSection.allCases.enumerated()), id: \.element) { i, section in
                    if i > 0 { Rectangle().fill(c.line).frame(height: theme.borders.hairline) }
                    CacheSectionRow(section: section, picked: picked.contains(section)) { toggle(section) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(c.line, lineWidth: theme.borders.hairline))
            Text(L.cacheKept).font(theme.typography.caption).foregroundStyle(c.tx3)
            AppButton(clearing ? "…" : L.clearConfirm, kind: .danger, action: clear)
                .disabled(picked.isEmpty || clearing).opacity(picked.isEmpty ? 0.5 : 1)
        }
    }

    private func toggle(_ section: CacheSection) {
        if picked.remove(section) == nil { picked.insert(section) }
    }

    private func clear() {
        let sections = picked
        clearing = true
        Task {
            let result = await model.clear(sections)
            clearing = false
            switch result {
            case .success: onCleared(sections); toasts?.show(L.cacheCleared)
            case .failure(let f): toasts?.show(L.cacheClearFailed(f.message), kind: .error)
            }
        }
    }
}

/// One part of the local database: its icon, name and what it holds, and a checkbox; the whole row toggles it.
private struct CacheSectionRow: View {
    @Environment(\.appTheme) private var theme
    let section: CacheSection
    let picked: Bool
    let onToggle: () -> Void

    var body: some View {
        let c = theme.colors
        HoverSurface(onTap: onToggle, cornerRadius: 0) {
            HStack(spacing: theme.spacing.s12) {
                Image(systemName: Self.symbol(section)).font(.system(size: theme.sizes.icon16)).foregroundStyle(c.tx2)
                    .frame(width: theme.sizes.control36, height: theme.sizes.control36)
                    .background(c.panel2, in: Circle())
                VStack(alignment: .leading, spacing: theme.spacing.s2) {
                    Text(L.cacheTitle(section)).font(theme.typography.bodyStrong).foregroundStyle(c.tx)
                    Text(L.cacheHint(section)).font(theme.typography.caption).foregroundStyle(c.tx2)
                }
                Spacer(minLength: 0)
                Image(systemName: picked ? "checkmark.square.fill" : "square").font(.system(size: theme.sizes.icon18))
                    .foregroundStyle(picked ? c.accent : c.tx3)
            }
            .padding(theme.spacing.s12)
        }
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private static func symbol(_ s: CacheSection) -> String {
        switch s {
        case .tickets: "rectangle.split.3x1"
        case .dashboard: "square.grid.2x2"
        case .chat: "bubble.left.and.bubble.right"
        case .translations: "character.bubble"
        }
    }
}
