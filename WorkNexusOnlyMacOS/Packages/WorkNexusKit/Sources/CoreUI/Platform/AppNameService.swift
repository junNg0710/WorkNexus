import AppKit

/// Ported from: lib/core/platform/app_name_service.dart
/// The name the user gave the app, shown in place of the product name: the window titles and the tray tooltip. Kept in a
/// text file in the support folder. What the bundle carries (file name, Dock label, notification header) is fixed at
/// build time, so those keep the default.
@MainActor
public final class AppNameService {
    /// The longest name kept: a title bar shows little more.
    public static let maxLength = 40

    private let file: URL
    private let setTrayToolTip: ((String?) -> Void)?
    private let setWindowTitle: @MainActor (String) -> Void

    public init(file: URL = PlatformPaths.applicationSupport().appendingPathComponent("app_name.txt"),
                setTrayToolTip: ((String?) -> Void)? = nil,
                setWindowTitle: @escaping @MainActor (String) -> Void = { title in NSApp?.windows.forEach { $0.title = title } }) {
        self.file = file; self.setTrayToolTip = setTrayToolTip; self.setWindowTitle = setWindowTitle
    }

    /// The name the user gave, or nil while the app has its own.
    public func current() -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Keeps `name` as the app's name (blank gives the own name back). False when it could not be kept; the name in use
    /// stays as it was.
    @discardableResult
    public func rename(_ name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if clean.isEmpty {
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            } else {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try String(clean.prefix(Self.maxLength)).write(to: file, atomically: true, encoding: .utf8)
            }
        } catch { return false }
        apply()
        return true
    }

    /// Puts the name in use on the windows and the tray. Cosmetic: never an error.
    public func apply() {
        let name = current()
        setWindowTitle(name ?? AppIdentity.appName)
        setTrayToolTip?(name)
    }
}
