import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/connections/presentation/{connect_account_dialog,add_connection_dialog,
/// github_connection_dialog,gitlab_connection_dialog}.dart
/// "Connect account": one dialog with the provider picker on top and the picked provider's form under it.
/// Switching provider starts that form afresh (the `.id` below). The secret goes to the keychain, never the DB.
struct ConnectAccountDialog: View {
    @State private var provider: ProviderType = .zentao
    let model: ConnectionsModel
    let onClose: () -> Void
    let onSyncWarning: (String) -> Void

    var body: some View {
        ConnectionForm(provider: provider, model: model, onProviderChanged: { provider = $0 },
                       onClose: onClose, onSyncWarning: onSyncWarning)
            .id(provider)
    }
}

/// One provider's form: ZenTao asks for URL + username + password, GitHub / GitLab for URL + token (the handle
/// comes from the token). The workspace starts on the only one there is; with several the user must pick.
private struct ConnectionForm: View {
    @State private var baseUrl: String
    @State private var username = ""
    @State private var secret = ""
    @State private var workspaceId: String?
    @State private var newWorkspace = ""
    @State private var add: AddConnectionModel
    let provider: ProviderType
    let model: ConnectionsModel
    let onProviderChanged: (ProviderType) -> Void
    let onClose: () -> Void
    let onSyncWarning: (String) -> Void

    init(provider: ProviderType, model: ConnectionsModel, onProviderChanged: @escaping (ProviderType) -> Void,
         onClose: @escaping () -> Void, onSyncWarning: @escaping (String) -> Void) {
        self.provider = provider; self.model = model; self.onProviderChanged = onProviderChanged
        self.onClose = onClose; self.onSyncWarning = onSyncWarning
        _baseUrl = State(initialValue: Self.defaultServer(provider))
        _workspaceId = State(initialValue: ConnectionIdentity.initialWorkspaceId(model.workspaces))
        _add = State(initialValue: AddConnectionModel { await model.connect($0) })
    }

    private static func defaultServer(_ p: ProviderType) -> String {
        switch p { case .github: "https://github.com"; case .gitlab: "https://gitlab.com"; default: "" }
    }

    private var noWorkspace: Bool { model.workspaces.isEmpty }
    private var isZenTao: Bool { provider == .zentao }

    private var canConnect: Bool {
        if add.busy { return false }
        if !isZenTao, secret.trimmed.isEmpty { return false }
        if noWorkspace { return true }
        guard let workspaceId else { return false }
        return workspaceId != WorkspacePicker.newValue || !newWorkspace.trimmed.isEmpty
    }

    var body: some View {
        ConnectionDialogFrame(provider: provider, workspaces: model.workspaces, workspaceId: $workspaceId,
                              newWorkspace: $newWorkspace, busy: add.busy, error: add.error, canConnect: canConnect,
                              onProviderChanged: onProviderChanged, onConnect: connect, onClose: onClose) {
            ConnectionTextField(label: L.serverUrl, text: $baseUrl, hint: L.serverHint(provider),
                                autofocus: isZenTao, onSubmit: connect)
            if isZenTao {
                ConnectionTextField(label: L.username, text: $username, hint: L.usernameHint, onSubmit: connect)
                ConnectionTextField(label: L.password, text: $secret, secure: true, onSubmit: connect)
            } else {
                ConnectionTextField(label: L.personalAccessToken, text: $secret, hint: L.tokenHint(provider),
                                    secure: true, autofocus: true, onSubmit: connect) {
                    GenerateTokenLink { openExternally(tokenPage) }
                }
            }
        }
        .onChange(of: add.done) { _, done in
            guard done else { return }
            if let warning = add.syncWarning { onSyncWarning(warning) }
            onClose()
        }
    }

    private var tokenPage: String {
        provider == .github ? TokenSettingsURL.github(baseUrl) : TokenSettingsURL.gitlab(baseUrl)
    }

    private func connect() {
        guard canConnect else { return }
        let picked = noWorkspace || workspaceId == WorkspacePicker.newValue ? nil : workspaceId
        let newName: String? = noWorkspace ? L.defaultWorkspaceName : (workspaceId == WorkspacePicker.newValue ? newWorkspace : nil)
        let request = ConnectRequest(provider: provider, baseUrl: baseUrl, username: username, secret: secret,
                                     workspaceId: picked, newWorkspaceName: newName)
        Task { await add.submit(request) }
    }
}
