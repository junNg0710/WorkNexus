import CoreDomain
import CorePersistence
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/features/connections/** (entry point; no Dart counterpart - the Flutter app wires these through get_it).
///
/// The single public entry point of FeatureConnections; the composition root builds one and keeps it alive.
///
/// ### What it gives the composition root
/// - `model` - `ConnectionsModel`: workspaces + accounts (database streams) and their commands (sync, remove,
///   edit / delete workspace, connect, clear cache).
/// - `integrationsContent(workspaceId:)` - the Integrations page body (accounts of that workspace, "Connect a
///   tool" dialog for ZenTao / GitHub / GitLab, info box). FeatureWorkspaceOverview hosts it through a slot the
///   composition root fills; Overview never imports this target.
/// - `connectDialog(isPresented:)` - the connect dialog alone, for a "Connect" button elsewhere (e.g. the rail).
/// - `localCachePanel(onCleared:)` - the "Clear local data" panel of the storage dialog; `onCleared` receives the
///   sections the app should resync.
///
/// ### Wiring
/// - Needs the database (`AppDatabase`) for its two repositories and the `AppServices` for everything else
///   (provider tests go through `services.adapters`, secrets through `services.credentials` as `secret:{accountId}`,
///   the first sync through `services.sync`).
/// - `afterAccountAdded` runs after an account is saved and before its first sync (the Flutter app refreshes the
///   ZenTao profile there; ZenTaoProfileRepository is not hoisted into CoreDomain so the root supplies it).
/// - Migrations: none - this feature owns no tables (`migrationRegistrars` is empty).
@MainActor
public final class ConnectionsFeature {
    public static let migrationRegistrars: [MigrationRegistrar] = []
    public let model: ConnectionsModel

    public init(services: AppServices, db: AppDatabase, afterAccountAdded: (@Sendable (Account) async -> Void)? = nil) {
        model = ConnectionsModel(
            workspaces: services.workspaces, tickets: services.tickets, credentials: services.credentials,
            sync: services.sync, adapters: services.adapters, connections: GRDBConnectionRepository(db: db),
            cache: GRDBLocalCacheRepository(db: db), afterAccountAdded: afterAccountAdded)
    }

    /// The Integrations page body for `workspaceId` (nil: the first workspace).
    public func integrationsContent(workspaceId: String?) -> IntegrationsContentView {
        IntegrationsContentView(model: model, workspaceId: workspaceId)
    }

    /// The "Connect a tool" dialog, shown over the modified view while `isPresented`.
    public func connectDialog<Content: View>(isPresented: Binding<Bool>, over content: Content) -> some View {
        ConnectDialogHost(model: model, isPresented: isPresented) { content }
    }

    /// The "Create workspace" dialog (while `creating`) and the workspace editor (while `editing` is set), over `content`.
    /// `onCreated` runs once the new workspace is stored: the shell joins it.
    public func workspaceDialogs<Content: View>(creating: Binding<Bool>, editing: Binding<Workspace?>,
                                                onCreated: @escaping (Workspace) -> Void, over content: Content) -> some View {
        WorkspaceDialogsHost(model: model, creating: creating, editing: editing, onCreated: onCreated) { content }
    }

    /// The local-data section of the storage dialog.
    public func localCachePanel(onCleared: @escaping (Set<CacheSection>) -> Void) -> LocalCachePanelView {
        model.start()
        return LocalCachePanelView(model: model, onCleared: onCleared)
    }
}

/// Presents the connect dialog over `content`.
struct ConnectDialogHost<Content: View>: View {
    @Environment(\.toasts) private var toasts
    let model: ConnectionsModel
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .task { model.start() }
            .appDialog(isPresented: $isPresented) {
                ConnectAccountDialog(model: model, onClose: { isPresented = false },
                                     onSyncWarning: { toasts?.show($0, kind: .warning) })
            }
    }
}
