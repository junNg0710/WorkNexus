import CoreDomain
import Foundation

/// New feature, no Dart counterpart. Reads an `.app` bundle's `Contents/Info.plist`: the name (`CFBundleDisplayName`, else
/// `CFBundleName`, else the file's name) and the identifier. Anything that is not an application bundle is refused.
public struct PlistAppBundleReader: AppBundleReader {
    private static let notAnApp = "Not a Mac app"
    public init() {}

    public func read(path: String) -> Outcome<AppBundleInfo> {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard url.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleId = (plist["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespaces), !bundleId.isEmpty
        else { return .failure(.parse(Self.notAnApp)) }
        if let type = plist["CFBundlePackageType"] as? String, type != "APPL" { return .failure(.parse(Self.notAnApp)) }
        let fileName = url.deletingPathExtension().lastPathComponent
        let name = [plist["CFBundleDisplayName"], plist["CFBundleName"]]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? fileName
        let background = (plist["LSBackgroundOnly"] as? Bool ?? false) || (plist["LSUIElement"] as? Bool ?? false)
        return .success(AppBundleInfo(name: name, bundleId: bundleId, path: url.path, isBackground: background))
    }
}
