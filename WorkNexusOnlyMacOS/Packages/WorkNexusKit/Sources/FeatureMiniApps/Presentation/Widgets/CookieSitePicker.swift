import CoreUI
import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/cookie_site_picker.dart
/// The sites a browser profile has cookies for, each with a checkbox: a search narrows them, and the picks can be set all at once.
struct CookieSitePicker: View {
    @Environment(\.appTheme) private var theme
    let model: CookieImportDialogModel
    let sites: [CookieSite]
    @State private var query = ""

    private var shown: [CookieSite] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? sites : sites.filter { $0.site.contains(q) }
    }

    var body: some View {
        if sites.isEmpty {
            AppInlineNote(appString("miniAppCookiesNoSites", "This browser has no cookies."))
        } else {
            VStack(alignment: .leading, spacing: theme.spacing.s8) {
                HStack(spacing: theme.spacing.s8) {
                    AppSearchField(text: $query, hint: appString("miniAppCookiesSearch", "Search sites"), autofocus: true)
                    AppButton(appString("miniAppCookiesSelectAll", "Select all"), kind: .ghost) { model.pick(shown) }
                    AppButton(appString("miniAppCookiesSelectNone", "Select none"), kind: .ghost) { model.pickNone() }
                        .disabled(model.picked.isEmpty)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shown, id: \.site) { site in
                            CookieSiteRow(site: site, picked: model.picked.contains(site.site)) { model.toggle(site.site) }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
    }
}

private struct CookieSiteRow: View {
    @Environment(\.appTheme) private var theme
    let site: CookieSite
    let picked: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s10) {
            Image(systemName: picked ? "checkmark.square.fill" : "square").font(.system(size: theme.sizes.icon16))
                .foregroundStyle(picked ? theme.colors.accent : theme.colors.tx3)
            Text(site.site).font(theme.typography.body).foregroundStyle(theme.colors.tx).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if site.usedByMiniApp { TintedPill(appString("miniAppCookiesUsedByApp", "Mini app"), tint: theme.colors.accent) }
            Text(count).font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
        }
        .padding(.horizontal, theme.spacing.s4).padding(.vertical, theme.spacing.s6)
        .contentShape(Rectangle()).onTapGesture(perform: onToggle)
        .accessibilityElement(children: .combine).accessibilityAddTraits(picked ? .isSelected : [])
    }

    private var count: String {
        let n = site.cookies.count
        return appFormat("miniAppCookiesSiteCount", n == 1 ? "1 cookie" : "%1$@ cookies", "\(n)")
    }
}
