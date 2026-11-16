import Foundation

/// Ported from: lib/features/app_update/domain/usecases/build_issue_report_url.dart
/// The GitHub "new issue" page of the repository this build comes from, app and system details already in the body.
public struct BuildIssueReportURL: Sendable {
    private let config: AppUpdateConfig
    public init(config: AppUpdateConfig = AppUpdateConfig()) { self.config = config }

    public func callAsFunction(appVersion: String, system: String) -> URL {
        var c = URLComponents()
        c.scheme = "https"; c.host = "github.com"
        c.path = "/\(config.githubOwner)/\(config.githubRepo)/issues/new"
        c.queryItems = [URLQueryItem(name: "body", value:
            "**What happened?**\n\n\n**What did you expect?**\n\n\n---\nApp: \(config.appName) \(appVersion)\nSystem: \(system)")]
        return c.url!
    }
}
