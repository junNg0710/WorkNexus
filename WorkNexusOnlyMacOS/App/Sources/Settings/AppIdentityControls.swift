import AppKit
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/core/widgets/quick_settings_app_{name,icon}_control.dart
/// The app's identity: the name it goes by (typed in place, kept on Return or when the field loses focus, emptied to go back to
/// the own name; at most `AppNameService.maxLength` characters) and the picture it shows as its icon (a preview, a button to
/// pick another image, one to go back to the app's own). A failed save or an unreadable image says so.
struct AppIdentityControls: View {
    @Environment(\.appTheme) private var theme
    let root: CompositionRoot
    @State private var name = ""
    @State private var saved = ""
    @State private var iconTick = 0
    @FocusState private var nameFocused: Bool

    private var platform: PlatformServices { root.platform }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s12) {
            VStack(alignment: .leading, spacing: theme.spacing.s4) {
                Text(appString("appName", "App name")).font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
                HStack {
                    TextField(AppIdentity.appName, text: $name).textFieldStyle(.plain).font(theme.typography.body)
                        .focused($nameFocused).onSubmit(commitName)
                    Text("\(name.count)/\(AppNameService.maxLength)").font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
                }
                .padding(.horizontal, theme.spacing.s10).frame(height: theme.sizes.control36)
                .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(nameFocused ? theme.colors.accent : theme.colors.line, lineWidth: theme.borders.hairline))
            }
            HStack(spacing: theme.spacing.s10) {
                Image(nsImage: currentIcon).resizable().frame(width: theme.sizes.control36, height: theme.sizes.control36)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radii.md))
                    .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
                    .id(iconTick)
                AppButton(appString("appIconChoose", "Choose image…"), systemImage: "photo", action: chooseIcon)
                if platform.iconService.current() != nil {
                    AppIconButton("arrow.counterclockwise", help: appString("appIconReset", "Use the default icon")) {
                        platform.iconService.reset(); iconTick += 1
                    }
                }
            }
        }
        .onChange(of: name) { _, v in if v.count > AppNameService.maxLength { name = String(v.prefix(AppNameService.maxLength)) } }
        .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
        .onDisappear(perform: commitName)
        .task { saved = platform.nameService.current() ?? ""; name = saved }
    }

    /// The icon in use: the picked picture, else the app's own.
    private var currentIcon: NSImage {
        platform.iconService.current().flatMap { NSImage(contentsOf: $0) } ?? NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
    }

    private func commitName() {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed != saved else { return }
        if platform.nameService.rename(typed) { saved = typed }
        else { root.shell.toasts.show(appString("appNameSaveFailed", "The app name could not be saved."), kind: .error) }
    }

    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if platform.iconService.choose(url) { iconTick += 1 }
        else { root.shell.toasts.show(appString("appIconInvalid", "That file is not an image the app can read."), kind: .error) }
    }
}
