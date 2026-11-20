/// Not in the Flutter app.
import Foundation

public extension ZenTaoTeamGroup {
    /// The group every account has without saving one: the user alone, so a board shows their own work across every
    /// execution (product). Never stored; its name is drawn by the view ("Only me").
    static func onlyMe(accountId: String, login: String) -> ZenTaoTeamGroup {
        ZenTaoTeamGroup(id: "\(onlyMePrefix)\(accountId)", accountId: accountId, name: "",
                        members: [ZenTaoTeamMember(login: login, name: login)], createdAt: Date(timeIntervalSince1970: 0))
    }

    static let onlyMePrefix = "onlyMe:"

    var isOnlyMe: Bool { id.hasPrefix(Self.onlyMePrefix) }
}

/// What a board opens on when the user comes to it.
public enum ZenTaoDefaultBoardScope: Equatable, Sendable {
    case onlyMe
    case team(ZenTaoTeamGroup)
    /// The execution (product) the navigation has.
    case scope
    /// The last choice was a saved group, and the groups are not read yet.
    case waitForGroups
}

/// The scope a board opens on: the user's last choice for that board of that account, else their own work. A saved
/// group that was deleted since falls back to their own work too; without a login there is no "own work" to show.
public struct ResolveDefaultBoardScope: Sendable {
    public init() {}

    public func callAsFunction(_ choice: ZenTaoBoardScopeChoice?, groups: [ZenTaoTeamGroup]?, login: String) -> ZenTaoDefaultBoardScope {
        let mine: ZenTaoDefaultBoardScope = login.trimmingCharacters(in: .whitespaces).isEmpty ? .scope : .onlyMe
        switch choice {
        case nil, .onlyMe?: return mine
        case .scope?: return .scope
        case .team(let id)?:
            guard let groups else { return .waitForGroups }
            return groups.first { $0.id == id }.map { .team($0) } ?? mine
        }
    }
}
