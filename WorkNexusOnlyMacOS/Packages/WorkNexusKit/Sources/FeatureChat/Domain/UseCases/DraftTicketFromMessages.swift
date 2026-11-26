/// Not in the Flutter app.
import Foundation

/// What a chat message can be turned into (the three ZenTao's own client offers).
public enum ChatTicketKind: String, Sendable, CaseIterable { case bug, task, todo }

/// A picture message quoted in a ticket: its bytes, and the `token` that stands in the body's HTML where it goes (the
/// ticket's editor uploads the picture and puts it there).
public struct ChatTicketPicture: Hashable, Sendable {
    public var token: String
    public var name: String
    public var data: Data
    public init(token: String, name: String, data: Data) { self.token = token; self.name = name; self.data = data }

    /// What stands for picture number `index` (from 0) in the body.
    public static func token(_ index: Int) -> String { "{{chat-picture-\(index + 1)}}" }
}

/// The start of a ticket written from chat messages: a one-line title and the body, as text and as the HTML ZenTao
/// keeps, and the pictures among the messages.
public struct ChatTicketSeed: Hashable, Sendable {
    public var title: String
    public var text: String
    public var html: String
    public var pictures: [ChatTicketPicture]
    public init(title: String, text: String, html: String, pictures: [ChatTicketPicture] = []) {
        self.title = title; self.text = text; self.html = html; self.pictures = pictures
    }
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
        /// Set for a picture message whose bytes are at hand: what stands for it in the HTML (`text` is its preview).
        public var pictureToken: String?
        public init(sender: String, sentAt: Date, text: String, pictureToken: String? = nil) {
            self.sender = sender; self.sentAt = sentAt; self.text = text; self.pictureToken = pictureToken
        }
    }

    public static let titleLimit = 80
    public init() {}

    /// - Parameters:
    ///   - source: where the messages are from ("From chat: Team A"), the last line of the body.
    ///   - clock: how a message's time reads.
    public func callAsFunction(_ lines: [Line], source: String, clock: (Date) -> String) -> ChatTicketSeed {
        let lines = lines.sorted { $0.sentAt < $1.sentAt }.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let first = lines.first else { return ChatTicketSeed(title: "", text: "", html: "") }
        let paragraphs: [String], body: [String]
        let footer: String
        if lines.count == 1 {
            paragraphs = [first.text.trimmingCharacters(in: .whitespacesAndNewlines)]
            body = [first.pictureToken.map { "<p>\($0)</p>" } ?? "<p>\(Self.html(paragraphs[0]))</p>"]
            footer = "\(source) · \(first.sender), \(clock(first.sentAt))"
        } else {
            let heads = lines.map { "\($0.sender) (\(clock($0.sentAt))):" }
            paragraphs = zip(heads, lines).map { "\($0) \($1.text.trimmingCharacters(in: .whitespacesAndNewlines))" }
            // A picture goes under who sent it, in a paragraph of its own.
            body = zip(zip(heads, paragraphs), lines).map { pair, line in
                line.pictureToken.map { "<p>\(Self.html(pair.0))</p><p>\($0)</p>" } ?? "<p>\(Self.html(pair.1))</p>"
            }
            footer = source
        }
        // The first message with words names the ticket; pictures alone leave their preview ("Image") as the title.
        let named = lines.first { $0.pictureToken == nil } ?? first
        return ChatTicketSeed(title: Self.title(named.text), text: (paragraphs + [footer]).joined(separator: "\n\n"),
                              html: body.joined() + "<p><em>\(Self.html(footer))</em></p>")
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
