/// Ported from: lib/l10n/app_en.arb (the overview / dashboard keys)
import CoreUI
import Foundation

/// The overview's UI strings, by their `lib/l10n/*.arb` key. `%1$@`-style placeholders are filled here and plural
/// forms are resolved here (`{count, plural, ...}`), so a raw ICU string in the catalog never reaches the screen.
enum OL {
    private static func fill(_ key: String, _ fallback: String, _ args: [String]) -> String {
        var text = appString(key, fallback)
        if text.contains("plural,") { text = fallback }
        for (i, arg) in args.enumerated() { text = text.replacingOccurrences(of: "%\(i + 1)$@", with: arg) }
        return text
    }
    private static func plural(_ key: String, zero: String? = nil, one: String, other: String, _ count: Int) -> String {
        let fallback = count == 0 ? (zero ?? other) : count == 1 ? one : other
        return fill(key, fallback, ["\(count)"])
    }

    static var overview: String { appString("overview", "Overview") }
    static var integrations: String { appString("integrations", "Integrations") }
    static var connectionsSettingsSubtitle: String {
        appString("connectionsSettingsSubtitle", "The same provider can be connected multiple times — one per company. Tasks assigned to you are pulled from every account below.")
    }
    static var connectATool: String { appString("connectATool", "Connect a tool") }
    static var whoCanConnectTools: String { appString("whoCanConnectTools", "Who can connect tools") }
    static func connectionsSharedByEveryone(_ ws: String) -> String {
        fill("connectionsSharedByEveryone", "Connections are shared by everyone in %1$@.", [ws])
    }
    static var members: String { appString("members", "Members") }
    static var membersComingSoonBody: String {
        appString("membersComingSoonBody", "Members are coming soon. Connections are currently shared by everyone using this app.")
    }
    static func overviewSubtitle(_ count: Int, _ ws: String) -> String {
        let text = count == 1 ? "1 tool connected to \(ws). Pick a tool to work in it." : "\(count) tools connected to \(ws). Pick a tool to work in it."
        return text
    }
    static var manageIntegrations: String { appString("manageIntegrations", "Manage integrations") }
    static var noConnectedAccounts: String { appString("noConnectedAccounts", "No tools connected yet") }
    static var noConnectedAccountsDesc: String {
        appString("noConnectedAccountsDesc", "Connect a tool to start tracking work across your projects.")
    }
    static var assignedToYou: String { appString("assignedToYou", "Assigned to you") }
    static var fromAllTools: String { appString("fromAllTools", "from all tools") }
    static var noAssignedWork: String { appString("noAssignedWork", "No open work assigned to you") }
    static func showAllWithCount(_ n: Int) -> String { fill("showAllWithCount", "Show all %1$@", ["\(n)"]) }
    static var viewList: String { appString("viewList", "List") }
    static func openToolAction(_ tool: String) -> String { fill("openToolAction", "Open %1$@ →", [tool]) }
    static func overdueRelative(_ date: String) -> String { fill("overdueRelative", "Overdue %1$@", [date]) }
    static func dueRelative(_ date: String) -> String { fill("dueRelative", "Due %1$@", [date]) }

    static var dashboardMyTasks: String { appString("dashboardMyTasks", "My tasks") }
    static var dashboardMyBugs: String { appString("dashboardMyBugs", "My bugs") }
    static var dashboardMyWork: String { appString("dashboardMyWork", "My work") }
    static var dashboardShowAll: String { appString("dashboardShowAll", "Show all") }
    static var dashboardInProgress: String { appString("dashboardInProgress", "In progress") }
    static var dashboardNotStarted: String { appString("dashboardNotStarted", "Not started") }
    static var dashboardFocusEmpty: String { appString("dashboardFocusEmpty", "Nothing open here") }
    static var dashboardSprints: String { appString("dashboardSprints", "Executions") }
    static var dashboardActivity: String { appString("dashboardActivity", "Recent activity") }
    static var dashboardTodos: String { appString("dashboardTodos", "Todos") }
    static var dashboardRefreshFailed: String { appString("dashboardRefreshFailed", "Couldn't refresh — showing the last saved data") }
    static var dashboardLoadFailed: String { appString("dashboardLoadFailed", "Couldn't load the dashboard") }
    static var dashboardOpenFailed: String { appString("dashboardOpenFailed", "Couldn't open this item") }
    static var dashboardWorkSyncFailed: String {
        appString("dashboardWorkSyncFailed", "Couldn't sync from ZenTao — showing the last saved list")
    }
    static var dashboardTasksTab: String { appString("dashboardTasksTab", "Tasks") }
    static var dashboardBugsTab: String { appString("dashboardBugsTab", "Bugs") }
    static var dashboardOpenOnly: String { appString("dashboardOpenOnly", "Open") }
    static var dashboardAllItems: String { appString("dashboardAllItems", "All") }
    static var dashboardWorkEmptyAll: String { appString("dashboardWorkEmptyAll", "Nothing assigned to you") }
    static var refresh: String { appString("refresh", "Refresh") }
    static var retry: String { appString("retry", "Retry") }
    static func dashboardUpdated(_ when: String) -> String { fill("dashboardUpdated", "Updated %1$@", [when]) }
    static func dashboardEnds(_ date: String) -> String { fill("dashboardEnds", "Ends %1$@", [date]) }
    static func dashboardDue(_ date: String) -> String { fill("dashboardDue", "Due %1$@", [date]) }
    static func dashboardDaysLeft(_ n: Int) -> String {
        plural("dashboardDaysLeft", zero: "ends today", one: "1 day left", other: "\(n) days left", n)
    }
    static func dashboardDaysOverdue(_ n: Int) -> String {
        plural("dashboardDaysOverdue", one: "1 day overdue", other: "\(n) days overdue", n)
    }

    static var statusUnconfirmed: String { appString("myWorkStatusUnconfirmed", "Unconfirmed") }
    static var statusToFix: String { appString("myWorkStatusConfirmed", "To fix") }
    static var statusResolved: String { appString("myWorkStatusResolved", "Resolved") }
    static var statusClosed: String { appString("myWorkStatusClosed", "Closed") }
    static var statusWaiting: String { appString("myWorkStatusWaiting", "Not started") }
    static var statusDoing: String { appString("myWorkStatusDoing", "Doing") }
    static var statusPaused: String { appString("myWorkStatusPaused", "Paused") }
    static var statusDone: String { appString("myWorkStatusDone", "Done") }
    static func subtasks(_ n: Int) -> String { plural("myWorkSubtasks", one: "1 subtask", other: "\(n) subtasks", n) }
    static func reopened(_ n: Int) -> String { fill("myWorkReopened", "Reopened %1$@×", ["\(n)"]) }

    static var justNow: String { appString("justNow", "just now") }
    static func minutesAgo(_ n: Int) -> String { fill("minutesAgo", "%1$@m ago", ["\(n)"]) }
    static func hoursAgo(_ n: Int) -> String { fill("hoursAgo", "%1$@h ago", ["\(n)"]) }
    static func daysAgo(_ n: Int) -> String { fill("daysAgo", "%1$@d ago", ["\(n)"]) }
}
