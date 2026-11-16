/// Not in the Flutter app.
import Foundation

/// What a chat message can be turned into (the three ZenTao's own client offers).
public enum ChatTicketKind: String, Sendable, CaseIterable { case bug, task, todo }

/// The start of a ticket written from chat messages: a one-line title and the body, as text and as the HTML ZenTao keeps.
public struct ChatTicketSeed: Hashable, Sendable {
    public var title: String
    public var text: String
    public var html: String
    public init(title: String, text: String, html: String) { self.title = title; self.text = text; self.html = html }
}

/// What the chat asks its host to open: a new bug, task or todo of `accountId`, started from `seed`.
public struct ChatTicketRequest: Hashable, Sendable {
    public var kind: ChatTicketKind
    public var accountId: String
    public var seed: ChatTicketSeed
    public init(kind: ChatTicketKind, accountId: String, seed: ChatTicketSeed) { self.kind = kind; self.accountId = accountId; self.seed = seed }
}

/// Writes the start of a ticket from one or more chat messages: the first line becomes the title, the messages the
/// body (one alone as it is, several each under who said it and when), and a last line says where it came from.
public struct DraftTicketFromMessages: Sendable {
    /// One message as the ticket quotes it.
    public struct Line: Hashable, Sendable {
        public var sender: String
        public var sentAt: Date
        public var text: String
        public init(sender: String, sentAt: Date, text: String) { self.sender = sender; self.sentAt = sentAt; self.text = text }
    }

    public static let titleLimit = 80
    public init() {}

    /// - Parameters:
    ///   - source: where the messages are from ("From chat: Team A"), the last line of the body.
    ///   - clock: how a message's time reads.
    public func callAsFunction(_ lines: [Line], source: String, clock: (Date) -> String) -> ChatTicketSeed {
        let lines = lines.sorted { $0.sentAt < $1.sentAt }.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let first = lines.first else { return ChatTicketSeed(title: "", text: "", html: "") }
        let paragraphs: [String]
        let footer: String
        if lines.count == 1 {
            paragraphs = [first.text.trimmingCharacters(in: .whitespacesAndNewlines)]
            footer = "\(source) · \(first.sender), \(clock(first.sentAt))"
        } else {
            paragraphs = lines.map { "\($0.sender) (\(clock($0.sentAt))): \($0.text.trimmingCharacters(in: .whitespacesAndNewlines))" }
            footer = source
        }
        let html = paragraphs.map { "<p>\(Self.html($0))</p>" }.joined() + "<p><em>\(Self.html(footer))</em></p>"
        return ChatTicketSeed(title: Self.title(first.text), text: (paragraphs + [footer]).joined(separator: "\n\n"), html: html)
    }

    /// The first line that says something, on one line, cut at `titleLimit`.
    static func title(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .first { !$0.isEmpty } ?? ""
        return line.count > titleLimit ? String(line.prefix(titleLimit - 1)) + "…" : line
    }

    static func html(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .split(separator: "\n", omittingEmptySubsequences: false).joined(separator: "<br/>")
    }
}
