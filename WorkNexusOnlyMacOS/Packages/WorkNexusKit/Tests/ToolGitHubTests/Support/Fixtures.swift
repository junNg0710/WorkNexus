import CoreDomain
import Foundation
@testable import ToolGitHub

enum Fixtures {
    static func ticket(type: String, key: String = "42", status: UnifiedStatus = .review, providerStatus: String = "open",
                       priority: Priority = .medium, id: String = "gh-a:x", accountId: String = "gh-a",
                       projectId: String = "gh-a:octo/web", updatedAt: Date? = nil) -> Ticket {
        Ticket(id: id, accountId: accountId, projectId: projectId, providerType: .github, externalKey: key, title: "t",
               body: "", priority: priority, status: status, providerStatus: providerStatus, sourceHash: "h",
               externalType: type, updatedAt: updatedAt)
    }

    static func client(_ net: StubNetwork = .shared, baseUrl: String = "https://github.com") -> GitHubClient {
        GitHubClient(baseUrl: baseUrl, token: "pat", session: net.session)
    }

    static func adapter(_ net: StubNetwork = .shared) -> GitHubProviderAdapter {
        GitHubProviderAdapter(accountId: "gh-a", client: client(net))
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.withLock { n += 1; return n } }
}
