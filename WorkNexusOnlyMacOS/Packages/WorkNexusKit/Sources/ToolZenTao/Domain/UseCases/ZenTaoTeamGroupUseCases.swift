import CoreDomain
import Foundation

/// Checks and tidies a team group before it is saved: a name, at least one person, nobody twice.
public struct BuildTeamGroup: Sendable {
    public enum Problem: Error, Equatable, Sendable { case noName, noMembers }
    public init() {}

    public func callAsFunction(id: String? = nil, accountId: String, name: String, members: [ZenTaoTeamMember],
                               createdAt: Date = Date()) -> Result<ZenTaoTeamGroup, Problem> {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .failure(.noName) }
        var seen = Set<String>()
        let unique = members.filter { !$0.login.isEmpty && seen.insert($0.login).inserted }
        if unique.isEmpty { return .failure(.noMembers) }
        return .success(ZenTaoTeamGroup(id: id ?? UUID().uuidString, accountId: accountId, name: name, members: unique, createdAt: createdAt))
    }
}
