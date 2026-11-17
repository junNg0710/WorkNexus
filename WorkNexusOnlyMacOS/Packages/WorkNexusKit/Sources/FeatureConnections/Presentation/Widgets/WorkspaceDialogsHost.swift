import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/connections/presentation/widgets/create_workspace_dialog.dart (+ the editor the workspace
/// switcher opens). Presents the "Create workspace" dialog while `creating` and the workspace editor while `editing` is set,
/// over `content`. A created workspace is stored, then reported to `onCreated` (the shell joins it, as the Dart dialog does);
/// an edited one is saved through the model.
struct WorkspaceDialogsHost<Content: View>: View {
    @Environment(\.toasts) private var toasts
    let model: ConnectionsModel
    @Binding var creating: Bool
    @Binding var editing: Workspace?
    let onCreated: (Workspace) -> Void
    /// Built once here, not stored as a closure: it wraps the whole app, and a stored closure re-ran on every redraw.
    let content: Content
    /// The draft the create dialog starts from; a fresh id each time it opens.
    @State private var draft = Self.newDraft()

    init(model: ConnectionsModel, creating: Binding<Bool>, editing: Binding<Workspace?>, onCreated: @escaping (Workspace) -> Void,
         @ViewBuilder content: () -> Content) {
        self.model = model; _creating = creating; _editing = editing; self.onCreated = onCreated; self.content = content()
    }

    var body: some View {
        content
            .task { model.start() }
            .onChange(of: creating) { _, on in if on { draft = Self.newDraft() } }
            .appDialog(isPresented: $creating) {
                WorkspaceEditorDialog(workspace: draft, title: L.createTitle, saveTitle: L.createAndJoin, onSave: create) { creating = false }
            }
            .appDialog(item: $editing) { w in
                WorkspaceEditorDialog(workspace: w, onSave: { updated in
                    editing = nil
                    Task {
                        if case .failure = await model.save(updated) { toasts?.show(L.workspaceSaveFailed, kind: .error) }
                    }
                }, onClose: { editing = nil })
            }
    }

    private func create(_ workspace: Workspace) {
        Task {
            switch await model.create(workspace) {
            case .success: creating = false; onCreated(workspace)
            case .failure(let f): toasts?.show(L.createFailed(f.message), kind: .error)
            }
        }
    }

    /// A fresh id (`ws_<millis>`, as the Flutter dialog makes it), the first colour choice and the default icon.
    static func newDraft(now: Date = Date()) -> Workspace {
        Workspace(id: "ws_\(Int(now.timeIntervalSince1970 * 1000))", name: "", shortCode: "",
                  colorValue: Int(WorkspaceIcons.colorChoices[0]), iconKey: "briefcase")
    }
}
