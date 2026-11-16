import CoreUI
import SwiftUI

/// New feature, no Dart counterpart. "Add Mac app": the apps installed in /Applications, ~/Applications and /System/Applications
/// (searchable, the ones already on the rail marked), and "Choose other…" for an app anywhere else. Clicking an app adds it and
/// leaves the dialog open, so several can be added in a row. `onClose` runs for Done, Esc and the close button; present it with
/// `.appDialog`.
public struct NativeAppPickerDialog: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    @State private var query = ""
    private let model: NativeAppsModel
    private let onClose: () -> Void

    public init(model: NativeAppsModel, onClose: @escaping () -> Void) { self.model = model; self.onClose = onClose }

    public var body: some View {
        AppDialogFrame(title: appString("nativeAppAddTitle", "Add Mac app"), leadingIcon: "app.badge", maxWidth: theme.sizes.dialogSm, onClose: onClose) {
            VStack(alignment: .leading, spacing: theme.spacing.s10) {
                AppSearchField(text: $query, hint: appString("nativeAppSearchHint", "Search installed apps…"), autofocus: true)
                list
            }
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s16)
        } actions: {
            AppButton(appString("nativeAppChooseOther", "Choose other…"), systemImage: "folder", kind: .secondary, action: chooseOther)
            Spacer(minLength: 0)
            AppButton(appString("nativeAppDone", "Done"), kind: .primary, action: onClose)
        }
        .task { await model.loadInstalled() }
    }

    private var list: some View {
        let shown = Self.filter(model.installed, query)
        return ScrollView {
            LazyVStack(spacing: 0) {
                if shown.isEmpty {
                    AppInlineNote(model.loadingInstalled ? appString("nativeAppScanning", "Looking for apps…")
                                                         : appString("nativeAppNoMatches", "No apps match."))
                        .padding(theme.spacing.s8)
                }
                ForEach(shown, id: \.bundleId) { info in
                    NativeAppPickerRow(info: info, model: model, added: model.isAdded(info.bundleId)) { add(info.path) }
                }
            }
        }
        .frame(height: 340)
    }

    /// The apps whose name contains `query` (ignoring case and accents); all of them for a blank one.
    static func filter(_ apps: [AppBundleInfo], _ query: String) -> [AppBundleInfo] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return apps }
        return apps.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private func chooseOther() {
        guard let path = NativeAppPanel.chooseApp() else { return }
        add(path)
    }

    private func add(_ path: String) {
        Task {
            if case .failure(let failure) = await model.add(path: path) {
                if case .parse = failure { toasts?.show(appString("nativeAppNotAnApp", "That is not a Mac app."), kind: .error) }
                else { toasts?.show(appFormat("actionFailed", "Failed: %1$@", failure.message), kind: .error) }
            }
        }
    }
}
