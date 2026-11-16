import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/core/tools/tool_module.dart. A tool module renders its own nav pane / sections / detail extras;
/// the shell and `SharedKit` dispatch to it through `ToolRegistry` and never import a concrete tool (rules 1.5, 10.1).
public enum ScopeKind: Sendable { case project, product, repository, library, conversation, none }

public struct ToolViewMode: Identifiable, Sendable {
    public let id: ViewModeID
    public let label: String          // localization key resolved with `String(localized:)`
    public let systemImage: String
    public init(id: ViewModeID, label: String, systemImage: String) { self.id = id; self.label = label; self.systemImage = systemImage }
}

public struct ToolSection: Identifiable, Sendable {
    public let id: SectionID
    public let label: String
    public let systemImage: String
    public let scopeKind: ScopeKind
    public let viewModes: [ToolViewMode]
    public let available: Bool
    public init(id: SectionID, label: String, systemImage: String, scopeKind: ScopeKind,
                viewModes: [ToolViewMode] = [], available: Bool = true) {
        self.id = id; self.label = label; self.systemImage = systemImage; self.scopeKind = scopeKind
        self.viewModes = viewModes; self.available = available
    }
}

public struct ToolMetrics: Sendable {
    public let primaryCount: Int
    public let primaryLabel: String
    public let secondaryCount: Int?
    public let secondaryLabel: String?
    public init(primaryCount: Int, primaryLabel: String, secondaryCount: Int? = nil, secondaryLabel: String? = nil) {
        self.primaryCount = primaryCount; self.primaryLabel = primaryLabel
        self.secondaryCount = secondaryCount; self.secondaryLabel = secondaryLabel
    }
}

@MainActor
public protocol ToolModule {
    var providerType: ProviderType { get }
    var defaultSection: SectionID { get }
    var sections: [ToolSection] { get }
    var sectionsOnRail: Bool { get }
    var roleLabel: String { get }

    func buildNavPane(account: Account, location: ToolLocation) -> AnyView
    func buildSection(account: Account, location: ToolLocation) -> AnyView
    func metrics(account: Account) -> AsyncStream<ToolMetrics?>
    func scopeTickets(location: ToolLocation, tickets: [Ticket]) -> [Ticket]
    func paneCollapsible(location: ToolLocation) -> Bool
    func webURL(account: Account, location: ToolLocation) -> URL?
    func scopeTitle(account: Account, location: ToolLocation) -> AsyncStream<String?>?

    // Detail-panel hooks (shared/detail dispatches here). nil = nothing to show.
    func buildDetail(ticket: Ticket, onClose: @escaping () -> Void) -> AnyView?
    func buildActions(ticket: Ticket) -> AnyView?
    func buildDetailHeaderExtras(ticket: Ticket) -> AnyView?
    func buildStatusStrip(ticket: Ticket) -> AnyView?
    func buildDetailEffort(ticket: Ticket) -> AnyView?
    func buildDetailSubtasks(ticket: Ticket) -> AnyView?
    func buildDetailAttachments(ticket: Ticket) -> AnyView?
    func buildDetailSidebar(ticket: Ticket) -> AnyView?
}

public extension ToolModule {
    var defaultSection: SectionID { "default" }
    var sections: [ToolSection] { [] }
    var sectionsOnRail: Bool { false }
    var roleLabel: String { "" }
    func metrics(account: Account) -> AsyncStream<ToolMetrics?> { AsyncStream { $0.yield(nil); $0.finish() } }
    func scopeTickets(location: ToolLocation, tickets: [Ticket]) -> [Ticket] { tickets }
    func paneCollapsible(location: ToolLocation) -> Bool { false }
    func webURL(account: Account, location: ToolLocation) -> URL? { nil }
    func scopeTitle(account: Account, location: ToolLocation) -> AsyncStream<String?>? { nil }
    func buildDetail(ticket: Ticket, onClose: @escaping () -> Void) -> AnyView? { nil }
    func buildActions(ticket: Ticket) -> AnyView? { nil }
    func buildDetailHeaderExtras(ticket: Ticket) -> AnyView? { nil }
    func buildStatusStrip(ticket: Ticket) -> AnyView? { nil }
    func buildDetailEffort(ticket: Ticket) -> AnyView? { nil }
    func buildDetailSubtasks(ticket: Ticket) -> AnyView? { nil }
    func buildDetailAttachments(ticket: Ticket) -> AnyView? { nil }
    func buildDetailSidebar(ticket: Ticket) -> AnyView? { nil }
}

/// Maps `ProviderType` → module (lib/app/tool_registry.dart builds this at the composition root).
@MainActor
public final class ToolRegistry {
    private var modules: [ProviderType: any ToolModule] = [:]
    public init(_ modules: [any ToolModule] = []) { modules.forEach { self.modules[$0.providerType] = $0 } }
    public func register(_ m: any ToolModule) { modules[m.providerType] = m }
    public func module(for p: ProviderType) -> (any ToolModule)? { modules[p] }
    public var all: [any ToolModule] { Array(modules.values) }
}
