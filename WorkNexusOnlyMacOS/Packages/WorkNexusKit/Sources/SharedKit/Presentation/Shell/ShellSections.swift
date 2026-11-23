import CoreUI

/// The sections of the places that have a fixed list (workspace pages, settings pages): their pane rows and breadcrumb labels.
enum ShellSections {
    struct Row { let id: String; let key: String; let fallback: String; let icon: String }

    static let workspace: [Row] = [
        Row(id: "overview", key: "overview", fallback: "Overview", icon: "square.grid.2x2"),
        Row(id: "integrations", key: "integrations", fallback: "Integrations", icon: "puzzlepiece.extension"),
        Row(id: "members", key: "members", fallback: "Members", icon: "person.2"),
        Row(id: "settings", key: "settings", fallback: "Settings", icon: "slider.horizontal.3"),
    ]
    static let settings: [Row] = [
        Row(id: "general", key: "general", fallback: "General", icon: "slider.horizontal.3"),
        Row(id: "appearance", key: "appearance", fallback: "Appearance", icon: "paintpalette"),
        Row(id: "shortcuts", key: "shortcutsSettings", fallback: "Shortcuts", icon: "keyboard"),
        Row(id: "pet", key: "petSettings", fallback: "Pet", icon: "pawprint"),
        Row(id: "chat", key: "chat", fallback: "Chat", icon: "bubble.left.and.bubble.right"),
        Row(id: "translation", key: "translation", fallback: "Translation", icon: "character.bubble"),
        // Listed only for users of the ZenTao the panic switch is offered for (`ShellHost.settingsSectionVisible`).
        Row(id: "panicSwitch", key: "panicSwitchTitle", fallback: "Thầy vô (boss alert)", icon: "light.beacon.max"),
        Row(id: "cache", key: "localCache", fallback: "Local data", icon: "internaldrive"),
    ]

    static func label(_ rows: [Row], _ id: String) -> String {
        guard let r = rows.first(where: { $0.id == id }) ?? rows.first else { return id }
        return appString(r.key, r.fallback)
    }
}
