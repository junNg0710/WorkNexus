/// Ported from: lib/tools/zentao/presentation/widgets/zentao_bug_column_card.dart (drop rules + handlers)
import CoreDomain
import CoreUI
import Foundation

/// What dropping a bug card onto a column does: confirm, reopen or resolve (Flutter `_canDrop` / `_handleDrop`).
enum ZentaoBugDrops {
    /// Whether `ticket` can be dropped on `target`.
    static func canDrop(_ ticket: Ticket, onto target: ZenTaoBugColumn) -> Bool {
        let current = zentaoBugColumnFor(ticket)
        if current == target { return false }
        switch target {
        // ZenTao has no "un-confirm": nothing can move back into New/Unconfirmed.
        case .newUnconfirmed: return false
        // Reachable two ways: confirming a New/Unconfirmed bug, or reopening a resolved/closed one (activate). Either
        // way it lands active in Confirmed/To Fix.
        case .confirmedToFix: return true
        // Resolving is allowed from any non-resolved state.
        case .resolvedVerify, .postponed, .nonFix: return true
        case .closed: return false
        }
    }

    enum Kind: Equatable { case confirm, activate, resolve(String), askNonFix }

    static func kind(_ ticket: Ticket, onto target: ZenTaoBugColumn) -> Kind? {
        switch target {
        case .confirmedToFix: zentaoBugColumnFor(ticket) == .newUnconfirmed ? .confirm : .activate
        case .resolvedVerify: .resolve("fixed")
        case .postponed: .resolve("postponed")
        case .nonFix: .askNonFix
        case .newUnconfirmed, .closed: nil
        }
    }

    /// Runs the drop and returns the toast message and whether it worked.
    @MainActor
    static func run(_ kind: Kind, ticket: Ticket, workflow: ZenTaoWorkflowService) async -> (message: String, ok: Bool) {
        switch kind {
        case .confirm:
            switch await workflow.confirmBug(ticket, assignee: nil, comment: nil) {
            case .success: return (appString("boardBugConfirmed", "Bug confirmed"), true)
            case .failure(let f): return (appFormat("boardBugConfirmFailed", "Couldn't confirm the bug: %1$@", f.message), false)
            }
        case .activate:
            switch await workflow.activateBug(ticket, build: "trunk", assignee: nil, comment: nil) {
            case .success: return (appString("boardBugActivated", "Bug reactivated"), true)
            case .failure(let f): return (appFormat("boardBugActivateFailed", "Couldn't reactivate the bug: %1$@", f.message), false)
            }
        case .resolve(let resolution):
            let label = zentaoBugResolutionLabels.first { $0.code == resolution }?.label ?? resolution
            switch await workflow.resolveBug(ticket, resolution: resolution, build: "trunk", assignee: nil, comment: nil) {
            case .success: return (appFormat("boardBugResolvedAs", "Resolved as %1$@", label), true)
            case .failure(let f): return (appFormat("boardBugResolveFailed", "Couldn't resolve the bug: %1$@", f.message), false)
            }
        case .askNonFix: return ("", false)
        }
    }
}
