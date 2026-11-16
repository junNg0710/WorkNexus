import Foundation

/// Ported from: lib/core/domain/entities/comment.dart + activity_event.dart
public enum CommentOrigin: String, Codable, Sendable { case provider, internalNote }

public struct Comment: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var ticketId: String
    public var authorName: String
    public var body: String
    public var createdAt: Date
    public var origin: CommentOrigin
    public var synced: Bool
    public init(id: String, ticketId: String, authorName: String, body: String, createdAt: Date,
                origin: CommentOrigin = .provider, synced: Bool = true) {
        self.id = id; self.ticketId = ticketId; self.authorName = authorName; self.body = body
        self.createdAt = createdAt; self.origin = origin; self.synced = synced
    }
}

public struct ActivityEvent: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var ticketId: String
    public var actor: String
    public var action: String
    public var at: Date
    public var detail: String?
    public var attachments: [String]
    public init(id: String, ticketId: String, actor: String, action: String, at: Date,
                detail: String? = nil, attachments: [String] = []) {
        self.id = id; self.ticketId = ticketId; self.actor = actor; self.action = action
        self.at = at; self.detail = detail; self.attachments = attachments
    }
}
