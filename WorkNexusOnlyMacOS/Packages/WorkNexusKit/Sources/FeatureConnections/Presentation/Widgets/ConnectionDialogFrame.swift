import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/connections/presentation/widgets/connection_dialog_frame.dart
/// The chrome the ZenTao / GitLab / GitHub connect dialogs share: the provider picker, the provider badge and
/// blurb, the provider's own `fields`, the workspace picker (with a name field for a new one), the last error,
/// and Cancel / Connect & sync.
struct ConnectionDialogFrame<Fields: View>: View {
    @Environment(\.appTheme) private var theme
    let provider: ProviderType
    let workspaces: [Workspace]
    @Binding var workspaceId: String?
    @Binding var newWorkspace: String
    let busy: Bool
    let error: String?
    let canConnect: Bool
    let onProviderChanged: (ProviderType) -> Void
    let onConnect: () -> Void
    let onClose: () -> Void
    @ViewBuilder var fields: Fields

    var body: some View {
        let s = theme.spacing
        AppDialogFrame(title: L.connectTitle(provider), maxWidth: theme.sizes.dialogMd, onClose: onClose) {
            ScrollView {
                VStack(alignment: .leading, spacing: s.s16) {
                    ConnectionProviderPicker(value: provider, onChanged: onProviderChanged)
                    HStack(alignment: .top, spacing: s.s12) {
                        BrandLogoBadge(provider, size: theme.sizes.icon24)
                        Text(L.subtitle(provider)).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, s.s8)
                    fields
                    // No workspace yet: skip the picker; connecting creates a default one.
                    if !workspaces.isEmpty {
                        WorkspacePicker(workspaces: workspaces, value: workspaceId) { workspaceId = $0 }
                    }
                    if !workspaces.isEmpty, workspaceId == WorkspacePicker.newValue {
                        ConnectionTextField(label: L.newWorkspaceName, text: $newWorkspace, hint: L.newWorkspaceHint,
                                            onSubmit: { if canConnect { onConnect() } })
                    }
                    if let error { ConnectionErrorNote(message: error) }
                }
                .padding(.horizontal, s.s24).padding(.bottom, s.s24)
            }
            .scrollBounceBehavior(.basedOnSize)
        } actions: {
            Spacer(minLength: 0)
            AppButton(L.cancel, kind: .ghost, action: onClose).disabled(busy)
            ConnectButton(busy: busy, enabled: canConnect, action: onConnect)
        }
    }
}

/// Why the last connect attempt failed, under the form.
struct ConnectionErrorNote: View {
    @Environment(\.appTheme) private var theme
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.s8) {
            Image(systemName: "exclamationmark.circle").font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.red)
            Text(message).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(theme.spacing.s12)
        .background(theme.colors.red.opacity(0.10), in: RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.red.opacity(0.35), lineWidth: theme.borders.hairline))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The filled "Connect & sync" button: a spinner while busy, dimmed until the form can be submitted.
private struct ConnectButton: View {
    @Environment(\.appTheme) private var theme
    let busy: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.s6) {
                if busy { ProgressView().controlSize(.small).tint(theme.colors.accentTx) }
                Text(L.connectAndSync).font(theme.typography.label)
            }
            .padding(.horizontal, theme.spacing.s12).frame(height: theme.sizes.control32)
            .foregroundStyle(theme.colors.accentTx)
            .background(theme.colors.accent, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .opacity(enabled && !busy ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled || busy)
    }
}
