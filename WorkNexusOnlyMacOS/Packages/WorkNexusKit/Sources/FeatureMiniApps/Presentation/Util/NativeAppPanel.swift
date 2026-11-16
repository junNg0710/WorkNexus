import AppKit
import UniformTypeIdentifiers

/// New feature, no Dart counterpart. The open panel that picks an app outside the installed list (and locates a missing one).
@MainActor
public enum NativeAppPanel {
    /// The path of the `.app` the user picked, or nil when cancelled.
    public static func chooseApp(message: String? = nil) -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let message { panel.message = message }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
