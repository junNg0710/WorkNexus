import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/ticket_status_pill.dart
/// The ticket's status as a tinted pill; a tool's `buildStatusStrip` replaces it with its own (ZenTao's real status).
public struct TicketStatusPill: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket; let registry: ToolRegistry
    public init(ticket: Ticket, registry: ToolRegistry) { self.ticket = ticket; self.registry = registry }
    public var body: some View {
        if let strip = registry.module(for: ticket.providerType)?.buildStatusStrip(ticket: ticket) {
            strip
        } else {
            TintedPill(statusLabel(ticket.status), tint: theme.colors.statusColor(ticket.status))
        }
    }
}
