import Observation
import SwiftUI

/// Ported from: lib/core/widgets/file_drop_target.dart
/// How many targets of a `FileDropZones` group files hover over (0 or 1, briefly 2 while moving between them).
@MainActor @Observable
public final class FileDropZonesModel {
    public private(set) var hovering = 0
    public init() {}
    func enter() { hovering += 1 }
    func leave() { hovering = max(hovering - 1, 0) }
}

private struct FileDropZonesKey: EnvironmentKey { static let defaultValue: FileDropZonesModel? = nil }
extension EnvironmentValues {
    var fileDropZones: FileDropZonesModel? {
        get { self[FileDropZonesKey.self] }
        set { self[FileDropZonesKey.self] = newValue }
    }
}

/// Groups the `FileDropTarget`s under it: while files hover over any of them, all show their hints - the one
/// under the pointer highlighted - so the user sees which area does what before letting go.
public struct FileDropZones<Content: View>: View {
    @State private var model = FileDropZonesModel()
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View { content.environment(\.fileDropZones, model) }
}

/// Takes files dragged in from the OS onto `content`: while they hover, the area is outlined with `hint` in
/// its middle; on drop, `onDrop` gets their contents (folders are skipped). Inside `FileDropZones` the hint also
/// shows while files hover over another target of the group. With `enabled` false it takes nothing.
public struct FileDropTarget<Content: View>: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    @Environment(\.fileDropZones) private var zones
    @State private var hovering = false
    let hint: String
    let enabled: Bool
    let onDrop: ([DroppedFile]) async -> Void
    let content: Content

    public init(hint: String, enabled: Bool = true, onDrop: @escaping ([DroppedFile]) async -> Void,
                @ViewBuilder content: () -> Content) {
        self.hint = hint; self.enabled = enabled; self.onDrop = onDrop; self.content = content()
    }

    private func hover(_ on: Bool) {
        guard on != hovering else { return }
        hovering = on
        if on { zones?.enter() } else { zones?.leave() }
    }

    private func drop(_ urls: [URL]) -> Bool {
        hover(false)
        guard enabled, !urls.isEmpty else { return false }
        Task { @MainActor in
            guard let files = await DroppedFiles.read(urls) else {
                toasts?.show(appString("dropFilesFailed", "Couldn't read the dropped files"), kind: .error)
                return
            }
            if !files.isEmpty { await onDrop(files) }
        }
        return true
    }

    public var body: some View {
        let shown = enabled && (hovering || (zones?.hovering ?? 0) > 0)
        content
            .overlay { FileDropOverlay(hint: hint, active: hovering).opacity(shown ? 1 : 0).allowsHitTesting(false) }
            .animation(.easeOut(duration: theme.motion.fast), value: shown)
            .dropDestination(for: URL.self, action: { urls, _ in drop(urls) }, isTargeted: { hover($0 && enabled) })
            .onDisappear { if hovering { hovering = false; zones?.leave() } }
    }
}

/// The outline and hint shown while files hover: accent over the target under the pointer, muted over the other
/// targets of its group.
struct FileDropOverlay: View {
    @Environment(\.appTheme) private var theme
    let hint: String
    let active: Bool

    var body: some View {
        let tint = active ? theme.colors.accent : theme.colors.tx2
        ZStack {
            RoundedRectangle(cornerRadius: theme.radii.md).fill(tint.opacity(active ? 0.08 : 0.04))
            RoundedRectangle(cornerRadius: theme.radii.md).stroke(tint, lineWidth: theme.borders.thick)
            HStack(spacing: theme.spacing.s6) {
                Image(systemName: "square.and.arrow.up").font(.system(size: theme.sizes.icon16))
                Text(hint).font(theme.typography.metaStrong)
            }
            .foregroundStyle(theme.colors.accentTx)
            .padding(.horizontal, theme.spacing.s20).padding(.vertical, theme.spacing.s10)
            .background(tint, in: Capsule())
        }
    }
}
