import AppKit
import Foundation

/// Ported from: lib/core/platform/open_external.dart
/// Opens `url` in the user's default browser or URL handler. Best-effort: nothing is surfaced if it fails.
@discardableResult
public func openExternally(_ url: String) -> Bool {
    guard let target = URL(string: url) else { return false }
    return NSWorkspace.shared.open(target)
}

/// Opens a link tapped in rendered content: by the `LinkRouter` (the app itself, else a mini app for that site), else in
/// the browser. `inApp` false skips the app stage, for a link that came from the app's own view of it ("open in
/// browser" on the ticket). Only web/mail links: a scheme-less path would otherwise launch as a local file.
@MainActor
@discardableResult
public func openLinkExternally(_ url: String, inApp: Bool = true, router: LinkRouter? = nil) -> Bool {
    let target = url.trimmingCharacters(in: .whitespacesAndNewlines)
    let scheme = URL(string: target)?.scheme?.lowercased()
    guard scheme == "http" || scheme == "https" || scheme == "mailto" else { return false }
    if scheme != "mailto", (router ?? .shared).route(target, skip: inApp ? [] : [.app]) { return true }
    return openExternally(target)
}

/// Shows the file at `path` in Finder, selected.
public func revealInFileManager(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
}
