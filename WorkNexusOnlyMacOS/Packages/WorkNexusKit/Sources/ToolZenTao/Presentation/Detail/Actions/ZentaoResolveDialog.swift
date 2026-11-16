/// Ported from: lib/tools/zentao/presentation/detail/{resolve_dialog,non_fix_resolution_dialog}.dart
import CoreDomain
import CoreUI
import SwiftUI

/// ZenTao's own bug resolution codes, in the order the picker lists them, with their labels.
enum ZentaoResolutions {
    static let codes = ["fixed", "bydesign", "duplicate", "external", "notrepro", "willnotfix", "postponed", "tostory"]

    static func label(_ code: String) -> String {
        switch code {
        case "fixed": appString("taskDetailResolutionFixed", "Fixed")
        case "bydesign": appString("taskDetailResolutionByDesign", "By design")
        case "duplicate": appString("taskDetailResolutionDuplicate", "Duplicate")
        case "external": appString("taskDetailResolutionExternal", "External")
        case "notrepro": appString("taskDetailResolutionNotRepro", "Irreproducible")
        case "willnotfix": appString("taskDetailResolutionWontFix", "Won't fix")
        case "postponed": appString("taskDetailResolutionPostponed", "Postponed")
        case "tostory": appString("taskDetailResolutionToStory", "To story")
        default: code
        }
    }
}

/// Resolves a ZenTao bug: resolution code, build, optional assignee and note.
struct ZentaoResolveDialog: View {
    @Environment(\.toasts) private var toasts
    @Environment(\.zentaoCelebrate) private var celebrate
    let deps: ZentaoDependencies; let state: ZentaoUIState; let ticket: Ticket; let onClose: () -> Void
    @State private var note: ZentaoNoteModel
    @State private var build = "trunk"
    @State private var resolution: String?
    @State private var assignee: String?
    @State private var busy = false

    init(deps: ZentaoDependencies, state: ZentaoUIState, ticket: Ticket, onClose: @escaping () -> Void) {
        self.deps = deps; self.state = state; self.ticket = ticket; self.onClose = onClose
        _note = State(initialValue: ZentaoNoteModel(ticket: ticket))
    }

    private func submit() {
        guard let resolution, !busy else { return }
        busy = true
        let t = ticket, wf = deps.workflow, comment = note.value, build = build, assignee = assignee, celebrate = celebrate
        Task {
            let ok = await ZentaoActionRunner.run(
                state: state, ticket: t, toasts: toasts, label: appString("resolve", "Resolve"),
                successMessage: appFormat("taskDetailResolvedAs", "Resolved (%1$@)", ZentaoResolutions.label(resolution))) {
                await wf.resolveBug(t, resolution: resolution, build: build, assignee: assignee, comment: comment)
            }
            // Fireworks for a fix only, not for duplicate / by design / won't fix.
            if ok, resolution == "fixed" { celebrate() }
            onClose()
        }
    }

    var body: some View {
        let title = appString("resolve", "Resolve")
        ZentaoActionFrame(title: ZentaoActionLooks.title(title, ticket.externalKey), icon: "checkmark.circle", submitLabel: title,
                          busy: busy, canSubmit: resolution != nil, onSubmit: submit, onClose: onClose) {
            ZentaoFieldLabel(appString("taskDetailResolutionRequired", "Resolution *"))
            SearchableDropdownField(
                items: ZentaoResolutions.codes, value: resolution, labelOf: ZentaoResolutions.label,
                hintText: appString("taskDetailSelectResolution", "Select a resolution"),
                searchHint: appString("taskDetailSearchResolutions", "Search resolutions…"),
                emptyLabel: appString("taskDetailNoMatchingResolutions", "No matching resolutions")) { resolution = $0 }
            ZentaoFieldGap()
            ZentaoFieldLabel(appString("zentaoBuild", "Build"))
            ZentaoTextInput(text: $build, onSubmit: submit)
            ZentaoFieldGap()
            ZentaoFieldLabel(appString("zentaoAssignToOptional", "Assign to (optional)"))
            ZentaoAssigneeDropdown(deps: deps, ticket: ticket, value: assignee) { assignee = $0 }
            ZentaoFieldGap()
            ZentaoFieldLabel(appString("zentaoNote", "Note"))
            ZentaoNoteField(deps: deps, ticket: ticket, note: note)
        }
    }
}

/// Asks which non-fix resolution a bug dropped on the Non-Fix column gets. Calls `onPick` with the resolution code,
/// or `onClose` when dismissed. Nothing is picked up front: a preselected reason would be one careless click away
/// from the wrong resolution.
public struct ZentaoNonFixResolutionDialog: View {
    @Environment(\.appTheme) private var theme
    let onPick: (String) -> Void; let onClose: () -> Void
    @State private var resolution: String?

    public init(onPick: @escaping (String) -> Void, onClose: @escaping () -> Void) { self.onPick = onPick; self.onClose = onClose }

    public var body: some View {
        AppDialogFrame(title: appString("boardNonFixTitle", "Resolve as Non-Fix"), maxWidth: theme.sizes.dialogSm, onClose: onClose) {
            AppDropdown(value: resolution, values: [String?.none] + zentaoNonFixResolutionLabels.map { Optional($0.code) },
                        labelOf: { code in code.map { c in zentaoNonFixResolutionLabels.first { $0.code == c }?.label ?? c }
                            ?? appString("boardNonFixReasonHint", "Select a reason") }) { resolution = $0 }
                .padding(EdgeInsets(top: 0, leading: theme.spacing.s24, bottom: theme.spacing.s24, trailing: theme.spacing.s24))
        } actions: {
            Spacer(minLength: 0)
            AppButton(appString("cancel", "Cancel"), kind: .ghost, action: onClose)
            AppButton(appString("resolve", "Resolve"), kind: .primary) { if let resolution { onPick(resolution) } }.disabled(resolution == nil)
        }
    }
}
