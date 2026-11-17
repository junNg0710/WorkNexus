import CoreDomain
import CoreUI
import FeatureChat
import FeatureConnections
import SwiftUI

/// Local data: what the connections feature can clear (tickets, dashboard, chat, translations) and the attachment cache.
/// Clearing re-syncs the accounts so the screens refill (lib/app/shell/storage_dialog.dart, reload_after_cache_clear.dart).
struct CacheSettingsPage: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let root: CompositionRoot

    var body: some View {
        SettingsPage(title: appString("localCache", "Local data")) {
            root.connections.localCachePanel { sections in
                // Clearing re-fetches what was cleared so the screens refill (reload_after_cache_clear.dart): the tickets are
                // synced again, the chat signs out and in again to load its conversations, contacts and messages.
                Task {
                    for a in await currentAccounts(root.services.workspaces) where a.credentialsRef != nil { _ = await root.coordinator.syncAccount(a) }
                }
                if sections.contains(.chat) { Task { await root.chat.reconnectAll() } }
            }
            SettingsCard(title: appString("chatStorage", "Downloaded chat files")) {
                ChatStoragePanel(limitMb: root.shell.settings.chatCacheLimitMb) { mb in root.shell.updateSettings { $0.chatCacheLimitMb = mb } }
            }
            SettingsCard(title: appString("attachmentCache", "Downloaded attachments"),
                         subtitle: appString("attachmentCacheHint", "Kept for this session only.")) {
                AttachmentStoragePanel(usage: { root.coordinator.attachmentStorageBytes() }, clear: {
                    AppVideoStills.clearCache()
                    return root.coordinator.clearAttachmentStorage()
                })
            }
            DiagnosticsCard(log: root.diagnostics.log)
        }
    }
}
