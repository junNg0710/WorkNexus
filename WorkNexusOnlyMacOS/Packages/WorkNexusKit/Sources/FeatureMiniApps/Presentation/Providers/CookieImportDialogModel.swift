import CoreDomain
import Foundation
import Observation

/// Ported from: lib/features/mini_apps/presentation/widgets/cookie_import_dialog.dart (state)
/// What the "Import cookies" dialog is doing: the browser profiles found, the one chosen, its sites (read when it is chosen)
/// and the sites picked. Opened from settings every mini app's site is picked to begin with; opened from one mini app, that
/// app's `site` alone is picked and listed first, from the `source` it was last imported from, if that is still there.
@MainActor @Observable
final class CookieImportDialogModel {
    enum Sites { case loading, loaded([CookieSite]), failed(Failure) }

    private(set) var sources: [CookieSource] = []
    private(set) var loadingSources = true
    private(set) var source: CookieSource?
    private(set) var sites: Sites = .loading
    /// The sites picked for `source`.
    private(set) var picked: Set<String> = []
    private(set) var importing = false

    let focusSite: String?
    private let preferred: CookieSource?
    private let cookies: CookieImportModel
    @ObservationIgnored private var generation = 0

    init(cookies: CookieImportModel, site: String? = nil, source: CookieSource? = nil) {
        self.cookies = cookies; focusSite = site; preferred = source
    }

    /// Finds the browser profiles and reads the first one's (or the preferred one's) sites.
    func load() async {
        loadingSources = true
        await cookies.loadSources()
        sources = cookies.sources
        loadingSources = false
        guard let first = preferred.flatMap({ sources.contains($0) ? $0 : nil }) ?? sources.first else { return }
        await choose(first)
    }

    func choose(_ next: CookieSource) async {
        source = next; sites = .loading; picked = []
        generation += 1
        let mine = generation
        let result = await cookies.sites(of: next)
        // Another profile was chosen meanwhile: its answer is the one that counts.
        guard mine == generation else { return }
        switch result {
        case .success(let all):
            let ordered = Self.ordered(all, focus: focusSite)
            sites = .loaded(ordered)
            picked = Set(ordered.filter { focusSite == nil ? $0.usedByMiniApp : $0.site == focusSite }.map(\.site))
        case .failure(let failure): sites = .failed(failure)
        }
    }

    /// Reads the chosen profile again (after a refused read).
    func retry() async { if let source { await choose(source) } }

    /// The sites with `focus` first.
    static func ordered(_ all: [CookieSite], focus: String?) -> [CookieSite] {
        guard let focus else { return all }
        return all.filter { $0.site == focus } + all.filter { $0.site != focus }
    }

    func toggle(_ site: String) {
        if picked.contains(site) { picked.remove(site) } else { picked.insert(site) }
    }

    func pick(_ shown: [CookieSite]) { picked.formUnion(shown.map(\.site)) }
    func pickNone() { picked = [] }

    var canImport: Bool { source != nil && !picked.isEmpty && !importing }

    /// Imports the picked sites from the chosen profile; nil when there is nothing to import.
    func importPicked() async -> (source: CookieSource, result: Outcome<Int>)? {
        guard let source, !picked.isEmpty, !importing else { return nil }
        importing = true
        defer { importing = false }
        return (source, await cookies.importSites(picked, from: source))
    }
}
