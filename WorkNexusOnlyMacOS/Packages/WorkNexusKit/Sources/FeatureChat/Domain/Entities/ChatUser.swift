import Foundation

/// A ZenTao user as known to chat.
/// Ported from: lib/features/chat/domain/entities/chat_user.dart
public struct ChatUser: Hashable, Sendable, Identifiable {
    public var accountId: String
    public var userId: Int
    public var account: String
    public var realname: String
    public var avatarUrl: String?
    public var deleted: Bool
    public var email: String?
    public var mobile: String?
    public var phone: String?
    public var role: String?
    /// xxd presence (`online`, `away`, `busy`, `offline`…).
    public var status: String?

    public var id: String { "\(accountId)#\(userId)" }

    public init(accountId: String, userId: Int, account: String, realname: String, avatarUrl: String? = nil, deleted: Bool = false,
                email: String? = nil, mobile: String? = nil, phone: String? = nil, role: String? = nil, status: String? = nil) {
        self.accountId = accountId; self.userId = userId; self.account = account; self.realname = realname
        self.avatarUrl = avatarUrl; self.deleted = deleted; self.email = email; self.mobile = mobile
        self.phone = phone; self.role = role; self.status = status
    }
}
