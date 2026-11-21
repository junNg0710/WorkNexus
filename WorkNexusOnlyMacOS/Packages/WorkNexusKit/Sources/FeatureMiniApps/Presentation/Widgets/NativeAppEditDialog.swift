import AppKit
import CoreUI
import SwiftUI
import UniformTypeIdentifiers

/// Not in the Flutter app. Edits how a Mac app shows on WorkNexus's rail: its name (empty keeps the app's own) and its icon
/// (an image of the user's, or the app's own). The app itself is not touched. Enter saves; present it with `.appDialog`.
public struct NativeAppEditDialog: View {
    @Environment(\.appTheme) private var theme
    let model: NativeAppsModel
    let app: NativeApp
    let onClose: () -> Void
    @State private var name: String
    @State private var iconPath: String?
    @State private var busy = false
    @State private var error: String?

    public init(model: NativeAppsModel, app: NativeApp, onClose: @escaping () -> Void) {
        self.model = model; self.app = app; self.onClose = onClose
        _name = State(initialValue: app.customName ?? ""); _iconPath = State(initialValue: app.iconPath)
    }

    public var body: some View {
        AppDialogFrame(title: appString("nativeAppEdit", "Edit Mac app"), leadingIcon: "app.badge", maxWidth: theme.sizes.dialogSm, onClose: onClose) {
            VStack(alignment: .leading, spacing: theme.spacing.s14) {
                Text(app.path).font(theme.typography.meta).foregroundStyle(theme.colors.tx3).lineLimit(1).truncationMode(.middle)
                MiniAppFormField(label: appString("miniAppNameLabel", "Name (optional)"), hint: app.name, text: $name,
                                 error: error, autofocus: true, onSubmit: save)
                NativeAppIconField(icon: model.icon(forPath: app.path, custom: iconPath), busy: busy, custom: iconPath != nil,
                                   onChoose: chooseIcon, onReset: { iconPath = nil })
            }
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s16)
        } actions: {
            Spacer(minLength: 0)
            AppButton(appString("cancel", "Cancel"), kind: .ghost, action: onClose)
            AppButton(appString("save", "Save"), kind: .primary, action: save).disabled(busy).opacity(busy ? 0.5 : 1)
        }
    }

    private func save() {
        Task {
            switch await model.edit(app, name: name, iconPath: iconPath) {
            case .success: onClose()
            case .failure(let f): error = appFormat("actionFailed", "Failed: %1$@", f.message)
            }
        }
    }

    /// Picks an image and keeps a copy of it as the icon (applied with Save).
    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP, .gif, .ico, .icns, .tiff, .heic]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        busy = true; error = nil
        Task {
            switch await model.importIcon(id: app.id, from: path) {
            case .success(let kept): iconPath = kept
            case .failure: error = appString("miniAppIconFailed", "Couldn't get an icon this way")
            }
            busy = false
        }
    }
}

/// The icon field: a preview and the ways to change it - pick an image, or go back to the app's own icon.
private struct NativeAppIconField: View {
    @Environment(\.appTheme) private var theme
    let icon: NSImage
    let busy: Bool
    /// The icon is one the user picked (so "Use the app's icon" has something to undo).
    let custom: Bool
    let onChoose: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s6) {
            Text(appString("miniAppIcon", "Icon")).font(theme.typography.metaStrong).foregroundStyle(theme.colors.tx2)
            HStack(spacing: theme.spacing.s14) {
                Group {
                    if busy { ProgressView().controlSize(.small) }
                    else { Image(nsImage: icon).resizable().interpolation(.high).scaledToFit().frame(width: 36, height: 36) }
                }
                .frame(width: 48, height: 48)
                .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.lg))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
                VStack(alignment: .leading, spacing: theme.spacing.s8) {
                    AppButton(appString("miniAppIconChoose", "Choose image…"), systemImage: "photo", action: onChoose).disabled(busy)
                    AppButton(appString("nativeAppIconOwn", "Use the app's icon"), systemImage: "app", action: onReset).disabled(busy || !custom)
                }
            }
        }
    }
}
