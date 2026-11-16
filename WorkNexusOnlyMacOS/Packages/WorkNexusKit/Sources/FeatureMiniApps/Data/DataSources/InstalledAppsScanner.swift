import CoreDomain
import Foundation

/// New feature, no Dart counterpart. Lists the `.app` bundles in /Applications, ~/Applications and /System/Applications, and
/// the folders inside them (Utilities…), one level down.
public struct InstalledAppsScanner: InstalledAppsSource {
    private let roots: [URL]
    private let reader: AppBundleReader

    public init(roots: [URL] = InstalledAppsScanner.defaultRoots, reader: AppBundleReader = PlistAppBundleReader()) {
        self.roots = roots; self.reader = reader
    }

    public static var defaultRoots: [URL] {
        [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
         URL(fileURLWithPath: "/System/Applications")]
    }

    public func installed() async -> [AppBundleInfo] {
        let roots = roots, reader = reader
        return await Task.detached(priority: .utility) { Self.scan(roots, reader) }.value
    }

    static func scan(_ roots: [URL], _ reader: AppBundleReader) -> [AppBundleInfo] {
        var seen = Set<String>(), found: [AppBundleInfo] = []
        for root in roots {
            for url in bundles(in: root, depth: 1) {
                guard case .success(let info) = reader.read(path: url.path), !info.isBackground, seen.insert(info.bundleId).inserted else { continue }
                found.append(info)
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The `.app` bundles directly in `folder`, and — while `depth` allows — in the plain folders beside them.
    private static func bundles(in folder: URL, depth: Int) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                                   options: [.skipsHiddenFiles])) ?? []
        var out: [URL] = []
        for url in items {
            if url.pathExtension.lowercased() == "app" { out.append(url) }
            else if depth > 0, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { out += bundles(in: url, depth: depth - 1) }
        }
        return out
    }
}
