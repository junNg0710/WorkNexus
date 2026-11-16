import CoreDomain
import Foundation
import Observation

/// Ported from: lib/features/mini_apps/presentation/widgets/cookie_import_dialog.dart (state)
/// What the "Import cookies" dialog is doing: the browser profiles found, the one chosen, its sites (read when it is chosen)
/// and the sites picked. Opened from settings every mini app's site is picked to begin with; opened from one mini app, that
/// app's `site` alone is picked and listed first, from the `source` it was last imported from, if that is still there.
@MainActor @Observable
final class CookieImportDialogModel {
    enum Sites { case idle, loading, loaded([CookieSite]), failed(Failure) }

    private(set) var sources: [CookieSource] = []
    private(set) var loadingSources = true
    private(set) var source: CookieSource?
    private(set) var sites: Sites = .idle
    /// The sites picked for `source`.
    private(set) var picked: Set<String> = []
    private(set) var importing = false
    /// "Also import the saved passwords for these sites": off until the user asks for it.
    var includePasswords = false

    let focusSite: String?
    private let preferred: CookieSource?
    private let cookies: CookieImportModel
    @ObservationIgnored private var generation = 0

    init(cookies: CookieImportModel, site: String? = nil, source: CookieSource? = nil) {
        self.cookies = cookies; focusSite = site; preferred = source
    }

    /// Finds the browser profiles. Nothing is read (and so no keychain prompt appears) until the user picks a browser —
    /// unless the dialog was opened for a mini app imported before, which starts from the profile it came from.
    func load() async {
        loadingSources = true
        await cookies.loadSources()
        sources = cookies.sources
        loadingSources = false
        guard let first = preferred.flatMap({ sources.contains($0) ? $0 : nil }) else { return }
        await choose(first)
    }

    /// The browsers that have a readable profile here, Chrome first.
    var browsers: [CookieBrowser] { CookieBrowser.allCases.filter { b in sources.contains { $0.browser == b } } }

    /// `browser`'s profiles.
    func profiles(of browser: CookieBrowser) -> [CookieSource] { sources.filter { $0.browser == browser } }

    /// Picks `browser` (its main profile) and reads its sites.
    func chooseBrowser(_ browser: CookieBrowser) async {
        guard source?.browser != browser else { return }
        let all = profiles(of: browser)
        guard let main = all.first(where: { $0.profileId.hasSuffix("/Default") || $0.profileName == "Default" }) ?? all.first else { return }
        await choose(main)
    }

    func choose(_ next: CookieSource) async {
        source = next; sites = .loading; picked = []
        // Passwords are asked for anew with every profile: never carried over from the last one.
        includePasswords = false
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

    /// Whether the chosen browser's saved passwords can be imported too (not Firefox's, not Safari's).
    var passwordsSupported: Bool { source.map { cookies.canImportPasswords(from: $0.browser) } ?? false }

    /// Imports the picked sites from the chosen profile; nil when there is nothing to import. `passwords` is how the saved
    /// passwords of those same sites went, when the user asked for them (and the cookies went in).
    func importPicked() async -> (source: CookieSource, result: Outcome<Int>, passwords: Outcome<Int>?)? {
        guard let source, !picked.isEmpty, !importing else { return nil }
        importing = true
        defer { importing = false }
        let sites = picked
        let result = await cookies.importSites(sites, from: source)
        guard case .success = result, includePasswords, passwordsSupported else { return (source, result, nil) }
        return (source, result, await cookies.importPasswords(sites, from: source))
    }
}
