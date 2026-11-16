/// Ported from: lib/tools/zentao/presentation/providers/zentao_doc_providers.dart (the session state: the open document,
/// the tree filter, the expanded libraries, the reader's brightness) and the docs sections' pane collapse.
import CoreDomain
import CoreTools
import CoreGraphics
import Foundation
import Observation

/// The document open in the reader, as its library and id.
public struct ZentaoOpenDoc: Equatable, Sendable {
    public var libId: String
    public var docId: String
    public init(libId: String, docId: String) { self.libId = libId; self.docId = docId }
}

/// Session state of the Docs section (the open document per account, expanded libraries, pane collapse), and the
/// cache-backed lists the Docs views read: libraries, a library's documents, the pins, a document and its history.
/// The `watch*` streams of `ZenTaoDocRepository` (the local cache) feed it; `ensure(_:account:)` fetches into that
/// cache. Created once by `ZentaoModule`, so it outlives the nav pane, which the shell rebuilds on every trip to
/// Tasks or Bugs.
@MainActor @Observable
public final class ZentaoDocsState {
    /// How long a fetch stays fresh: leaving Docs for a moment doesn't refetch the libraries and every opened library
    /// on return.
    public static let idleLife: TimeInterval = 600

    @ObservationIgnored public let deps: ZentaoDependencies?
    @ObservationIgnored let repo: ZenTaoDocRepository
    @ObservationIgnored let exportDoc: ExportZenTaoDoc
    @ObservationIgnored let settingsRepo: SettingsRepository?
    @ObservationIgnored let openScope: @MainActor (_ libId: String, _ accountId: String) -> Void
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored var fetchedAt: [ZentaoDocFetch: Date] = [:]
    @ObservationIgnored var watchers: [String: Task<Void, Never>] = [:]
    /// Where each document was being read (its scroll offset), so a trip to Tasks or Bugs and back keeps the place.
    @ObservationIgnored public var readingOffsets: [String: CGFloat] = [:]

    /// The document open for each account, kept for the session apart from the location's scope - which a trip to
    /// Tasks or Bugs clears - so coming back to Docs shows the document left open.
    public private(set) var openDocs: [String: ZentaoOpenDoc] = [:]
    /// The tree's filter text per account.
    public private(set) var filters: [String: String] = [:]
    /// The libraries opened in the tree, as `accountId|libId`.
    public private(set) var expandedLibs: Set<String> = []
    /// The nav panes folded away (`accountId|section`), so a document can take the width. The shell reads it through
    /// `isPaneCollapsed` when it hosts the pane.
    public private(set) var collapsedPanes: Set<String> = []
    /// The app settings (the reader's brightness, the date format).
    public internal(set) var settings = AppSettings()

    // Cache-backed data; an entry exists once the cache has answered (an empty list is an answer).
    public internal(set) var libs: [String: [ZenTaoDocLib]] = [:]
    public internal(set) var docLists: [String: [ZenTaoDocSummary]] = [:]
    public internal(set) var pins: [String: ZenTaoDocPins] = [:]
    public internal(set) var docCache: [String: ZenTaoDoc] = [:]
    /// Documents the cache has answered for (a missing one is answered with nothing).
    public internal(set) var docAnswered: Set<String> = []
    public internal(set) var histories: [String: [ZenTaoDocAction]] = [:]
    public internal(set) var syncs: [ZentaoDocFetch: ZentaoDocSyncStatus] = [:]

    public init(deps: ZentaoDependencies) {
        self.deps = deps
        repo = deps.docs; exportDoc = deps.exportDoc; settingsRepo = deps.services.settings
        let nav = deps.nav
        openScope = { libId, accountId in nav.setScope(libId, accountId: accountId) }
        now = { Date() }
    }

    /// For tests and previews: the collaborators given one by one.
    init(repo: ZenTaoDocRepository, exportDoc: ExportZenTaoDoc? = nil, settings: SettingsRepository? = nil,
         openScope: @escaping @MainActor (String, String) -> Void = { _, _ in }, now: @escaping () -> Date = { Date() }) {
        deps = nil; self.repo = repo; self.exportDoc = exportDoc ?? ExportZenTaoDoc(repo)
        settingsRepo = settings; self.openScope = openScope; self.now = now
    }

    // MARK: Keys

    public static func libKey(_ accountId: String, _ libId: String) -> String { "\(accountId)|\(libId)" }
    public static func paneKey(_ accountId: String, _ section: SectionID) -> String { "\(accountId)|\(section.rawValue)" }

    // MARK: Open document, filter, expansion

    public func openDoc(for accountId: String) -> ZentaoOpenDoc? { openDocs[accountId] }

    /// Opens document `docId` of library `libId` in `accountId`'s reader. The library also becomes the location's
    /// scope (the breadcrumb shows it), but the reader follows `openDocs`, which outlives a scope reset.
    public func open(accountId: String, libId: String, docId: String) {
        openScope(libId, accountId)
        openDocs[accountId] = ZentaoOpenDoc(libId: libId, docId: docId)
    }

    public func filter(for accountId: String) -> String { filters[accountId] ?? "" }
    public func setFilter(_ text: String, accountId: String) { filters[accountId] = text }

    public func isExpanded(accountId: String, libId: String) -> Bool { expandedLibs.contains(Self.libKey(accountId, libId)) }
    public func toggleExpanded(accountId: String, libId: String) {
        let key = Self.libKey(accountId, libId)
        if expandedLibs.contains(key) { expandedLibs.remove(key) } else { expandedLibs.insert(key) }
    }
    public func expand(accountId: String, libId: String) { expandedLibs.insert(Self.libKey(accountId, libId)) }

    public func isPaneCollapsed(accountId: String, section: SectionID) -> Bool {
        collapsedPanes.contains(Self.paneKey(accountId, section))
    }
    public func setPane(collapsed: Bool, accountId: String, section: SectionID) {
        let key = Self.paneKey(accountId, section)
        if collapsed { collapsedPanes.insert(key) } else { collapsedPanes.remove(key) }
    }

    // MARK: Reader brightness

    /// The look the reader is forced to (`true`: dark), or nil to follow the app's theme: a dark app may read a long
    /// document on light, as ZenTao's web shows it. Kept in the app settings, so it survives a restart.
    public var readerForcedDark: Bool? {
        switch settings.docsReaderBrightness { case "dark": true; case "light": false; default: nil }
    }

    /// What `AppSettings.docsReaderBrightness` becomes when the reader flips from what it shows (`currentDark`):
    /// landing back on the app's own brightness (`appDark`) follows the app again (nil).
    public nonisolated static func nextReaderBrightness(currentDark: Bool, appDark: Bool) -> String? {
        let nextDark = !currentDark
        return nextDark == appDark ? nil : (nextDark ? "dark" : "light")
    }

    public func toggleReaderBrightness(currentDark: Bool, appDark: Bool) {
        settings.docsReaderBrightness = Self.nextReaderBrightness(currentDark: currentDark, appDark: appDark)
        guard let settingsRepo else { return }
        let saved = settings
        Task { _ = await settingsRepo.save(saved) }
    }

    // MARK: Actions on the cache

    /// Pins `lib` or `doc` to the top of the tree, or unpins it.
    @discardableResult
    public func togglePin(accountId: String, lib: ZenTaoDocLib? = nil, doc: ZenTaoDocSummary? = nil) async -> Outcome<Void> {
        await ToggleZenTaoDocPin(repo)(accountId: accountId, lib: lib, doc: doc)
    }

    /// The document as Markdown, for the clipboard.
    public func markdown(_ doc: ZenTaoDoc) -> String { ZenTaoDocMarkdown.render(doc) }

    /// Saves `doc` to Downloads in `format`; the saved path.
    public func export(account: Account, doc: ZenTaoDoc, format: ZenTaoDocExportFormat) async -> Outcome<String> {
        await exportDoc(account, doc, format)
    }
}
