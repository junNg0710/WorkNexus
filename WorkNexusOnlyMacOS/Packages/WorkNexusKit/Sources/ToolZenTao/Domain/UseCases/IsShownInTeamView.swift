/// Not in the Flutter app: which executions' tasks a team view shows.
import Foundation

/// A team view gathers each person's tasks from every execution. Routine executions - a daily report list - would
/// bury the real work, so they are left out unless the user shows them; opening such an execution still lists them.
public struct IsShownInTeamView: Sendable {
    public init() {}

    /// `choices` is `AppSettings.teamExecutionVisibility`: the user's pick per "accountId:executionId".
    public func callAsFunction(accountId: String, executionId: String?, executionName: String?, choices: [String: Bool]) -> Bool {
        if let executionId, let pick = choices[Self.key(accountId: accountId, executionId: executionId)] { return pick }
        return !Self.isRoutine(executionName)
    }

    /// The key of an execution in `choices`, the same as a pinned execution's.
    public static func key(accountId: String, executionId: String) -> String { "\(accountId):\(executionId)" }

    /// An execution kept for routine reports rather than work, by its name ("VN_Daily_Tasks").
    public static func isRoutine(_ name: String?) -> Bool { (name ?? "").range(of: "daily", options: .caseInsensitive) != nil }
}
