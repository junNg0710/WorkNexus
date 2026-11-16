import CoreUI
import SwiftUI
import UniformTypeIdentifiers

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_dialog.dart
/// Adds a mini app (a web address and an optional name; its icon comes from the site), or — given `existing` — edits one,
/// with its icon, certificate trust and the permissions it was given too. Enter saves. `onSaved` gets the app as kept (a new
/// one opens at once, as picking it on the rail would); `onClose` runs for Cancel, Esc and after a save. Present it with
/// `.appDialog`.
public struct MiniAppDialog: View {
    @Environment(\.appTheme) private var theme
    @State private var form: MiniAppFormModel
    @State private var permissions: MiniAppPermissionsModel?
    private let feature: MiniAppsFeature
    private let onSaved: (MiniApp) -> Void
    private let onClose: () -> Void

    public init(feature: MiniAppsFeature, existing: MiniApp? = nil, onSaved: @escaping (MiniApp) -> Void = { _ in },
                onClose: @escaping () -> Void) {
        self.feature = feature; self.onSaved = onSaved; self.onClose = onClose
        _form = State(initialValue: MiniAppFormModel(model: feature.model, existing: existing))
        _permissions = State(initialValue: existing.map { MiniAppPermissionsModel(miniAppId: $0.id, repository: feature.permissions) })
    }

    public var body: some View {
        AppDialogFrame(title: form.existing == nil ? appString("miniAppAdd", "Add mini app") : appString("miniAppEdit", "Edit mini app"),
                       leadingIcon: "macwindow", maxWidth: theme.sizes.dialogSm, onClose: onClose) {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.s14) {
                    MiniAppFormField(label: appString("miniAppUrlLabel", "Web address"), hint: appString("miniAppUrlHint", "example.com"),
                                     text: $form.url, error: form.error, autofocus: true, onSubmit: save)
                    MiniAppFormField(label: appString("miniAppNameLabel", "Name (optional)"), hint: "", text: $form.name, onSubmit: save)
                    if form.existing != nil {
                        MiniAppIconPicker(name: form.name, iconPath: form.iconPath, busy: form.iconBusy, onChoose: chooseIcon,
                                          onUseSite: { Task { await form.useSiteIcon() } })
                    }
                    MiniAppCertificateSection(url: form.url, model: feature.trustedModel)
                    if let permissions { MiniAppPermissionsSection(model: permissions) }
                }
                .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s16)
            }
            .frame(maxHeight: 520)
        } actions: {
            Spacer(minLength: 0)
            AppButton(appString("cancel", "Cancel"), kind: .ghost, action: onClose)
            AppButton(appString("save", "Save"), kind: .primary, action: save).disabled(!form.canSave).opacity(form.canSave ? 1 : 0.5)
        }
        .onChange(of: form.url) { _, _ in form.clearError() }
    }

    private func save() {
        Task {
            guard let app = await form.save() else { return }
            onSaved(app)
            onClose()
        }
    }

    /// Picks an image file and takes it as the icon.
    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP, .gif, .ico]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        Task { await form.importIcon(from: path) }
    }
}
