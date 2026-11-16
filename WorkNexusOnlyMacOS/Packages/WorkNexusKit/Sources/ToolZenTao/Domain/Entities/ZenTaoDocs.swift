import CoreDomain
import Foundation

/// Ported from: lib/tools/zentao/domain/entities/zentao_doc*.dart
/// A ZenTao document library (`GET /doclibs`).
public struct ZenTaoDocLib: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// A document as a library's list shows it (`GET /docs?lib=`). `acl` is `open`, `private`, `custom`...
public struct ZenTaoDocSummary: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var libId: String
    public var acl: String?
    public init(id: String, title: String, libId: String, acl: String? = nil) {
        self.id = id; self.title = title; self.libId = libId; self.acl = acl
    }
}

/// Someone who wrote or edited a ZenTao document: login `account` and display `name` when ZenTao sent it.
public struct ZenTaoDocPerson: Hashable, Sendable {
    public var account: String
    public var name: String?
    public var displayName: String { name ?? account }
    public init(account: String, name: String? = nil) { self.account = account; self.name = name }
}

/// One ZenTao document (`GET /docs/{id}`). A `text` document carries its body as HTML in `html`.
public struct ZenTaoDoc: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var libId: String
    public var html: String
    public var isAttachment: Bool
    public var version: Int?
    public var author: ZenTaoDocPerson?
    public var editors: [ZenTaoDocPerson]
    public var views: Int?
    public var addedDate: Date?
    public var editedDate: Date?
    public var files: [TicketAttachment]
    public var hasBody: Bool { !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public init(id: String, title: String, libId: String, html: String = "", isAttachment: Bool = false,
                version: Int? = nil, author: ZenTaoDocPerson? = nil, editors: [ZenTaoDocPerson] = [],
                views: Int? = nil, addedDate: Date? = nil, editedDate: Date? = nil, files: [TicketAttachment] = []) {
        self.id = id; self.title = title; self.libId = libId; self.html = html; self.isAttachment = isAttachment
        self.version = version; self.author = author; self.editors = editors; self.views = views
        self.addedDate = addedDate; self.editedDate = editedDate; self.files = files
    }
}

/// One field a history entry changed: its old and new value, or the lines a text diff removed and added.
public struct ZenTaoDocChange: Hashable, Sendable {
    public var field: String
    public var from: String?
    public var to: String?
    public var removed: [String]
    public var added: [String]
    public var isBody: Bool
    public init(field: String, from: String? = nil, to: String? = nil, removed: [String] = [],
                added: [String] = [], isBody: Bool = false) {
        self.field = field; self.from = from; self.to = to; self.removed = removed; self.added = added; self.isBody = isBody
    }
}

/// One entry of a document's history, as ZenTao's History panel lists it.
public struct ZenTaoDocAction: Hashable, Sendable, Identifiable {
    public var id: String
    public var action: String
    public var summary: String
    public var date: Date?
    public var actor: String?
    public var changes: [ZenTaoDocChange]
    public init(id: String, action: String, summary: String, date: Date? = nil, actor: String? = nil,
                changes: [ZenTaoDocChange] = []) {
        self.id = id; self.action = action; self.summary = summary; self.date = date; self.actor = actor; self.changes = changes
    }
}

/// What a document can be exported as: Markdown, a standalone HTML page, or a JSON backup.
public enum ZenTaoDocExportFormat: String, CaseIterable, Sendable {
    case markdown, html, backup
    public var fileExtension: String {
        switch self { case .markdown: "md"; case .html: "html"; case .backup: "json" }
    }
}

/// The libraries and documents an account keeps on top of the Docs pane, in the order they were pinned.
public struct ZenTaoDocPins: Hashable, Sendable {
    public var libs: [ZenTaoDocLib]
    public var docs: [ZenTaoDocSummary]
    public init(libs: [ZenTaoDocLib] = [], docs: [ZenTaoDocSummary] = []) { self.libs = libs; self.docs = docs }
    public var isEmpty: Bool { libs.isEmpty && docs.isEmpty }
    public func hasLib(_ id: String) -> Bool { libs.contains { $0.id == id } }
    public func hasDoc(_ id: String) -> Bool { docs.contains { $0.id == id } }
    /// Pins `lib` at the end, or unpins it when already pinned.
    public func togglingLib(_ lib: ZenTaoDocLib) -> ZenTaoDocPins {
        var next = self
        next.libs = hasLib(lib.id) ? libs.filter { $0.id != lib.id } : libs + [lib]
        return next
    }
    /// Pins `doc` at the end, or unpins it when already pinned.
    public func togglingDoc(_ doc: ZenTaoDocSummary) -> ZenTaoDocPins {
        var next = self
        next.docs = hasDoc(doc.id) ? docs.filter { $0.id != doc.id } : docs + [doc]
        return next
    }
}
