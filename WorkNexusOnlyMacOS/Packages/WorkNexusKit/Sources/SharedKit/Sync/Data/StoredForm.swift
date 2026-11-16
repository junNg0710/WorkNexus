import CoreDomain
import Foundation

/// Ported from: lib/core/data/mappers (ticketAsStored / commentAsStored / activityAsStored).
/// A row is compared in its *stored* form: dates at the database's millisecond precision, and the provider entity
/// as it survives its JSON column (ISO-8601 seconds). Without this an unchanged refresh would look "changed" forever.
enum StoredForm {
    private static let enc: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let dec: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    static func ms(_ d: Date) -> Date { Date(timeIntervalSince1970: (d.timeIntervalSince1970 * 1000).rounded() / 1000) }

    static func ticket(_ t: Ticket) -> Ticket {
        var s = t
        s.createdAt = t.createdAt.map(ms); s.updatedAt = t.updatedAt.map(ms)
        if let e = t.providerEntity, let data = try? enc.encode(e), let back = try? dec.decode(TicketProviderEntity.self, from: data) {
            s.providerEntity = back
        }
        return s
    }

    static func comment(_ c: Comment) -> Comment { var s = c; s.createdAt = ms(c.createdAt); return s }
    static func activity(_ e: ActivityEvent) -> ActivityEvent { var s = e; s.at = ms(e.at); return s }
}

/// First value of a repository watch stream (the current snapshot); the stream is cancelled afterwards.
func firstValue<T>(of stream: AsyncStream<T>) async -> T? {
    for await v in stream { return v }
    return nil
}
