import Foundation

/// Who may post in a group: everyone, its owner and admins, or chosen members.
public enum ChatSendScope: String, CaseIterable, Hashable, Sendable { case everyone, admins, selected }

/// xxd's `committers` as a value: empty or `$ALL` lets everyone post, `$ADMINS` only the owner and admins, anything else is
/// a comma list of the user ids that may (the owner always may).
/// Ported from: lib/features/chat/domain/value_objects/chat_committers.dart
public struct ChatCommitters: Hashable, Sendable {
    public var scope: ChatSendScope
    /// Who may post when `scope` is `.selected`.
    public var userIds: Set<Int>

    public init(_ scope: ChatSendScope, _ userIds: Set<Int> = []) { self.scope = scope; self.userIds = userIds }

    public static func parse(_ raw: String) -> ChatCommitters {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value == "$ALL" { return ChatCommitters(.everyone) }
        if value == "$ADMINS" { return ChatCommitters(.admins) }
        return ChatCommitters(.selected, Set(value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }))
    }

    /// The `committers` string xxd stores.
    public func encode() -> String {
        switch scope {
        case .everyone: ""
        case .admins: "$ADMINS"
        case .selected: userIds.sorted().map(String.init).joined(separator: ",")
        }
    }
}
