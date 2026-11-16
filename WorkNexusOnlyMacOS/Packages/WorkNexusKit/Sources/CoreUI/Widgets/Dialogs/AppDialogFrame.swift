import SwiftUI

/// Ported from: lib/core/widgets/app_dialog_frame.dart
/// The app's dialog chrome: a rounded card with a title row (optional trailing view and a close button), the
/// content, and `actions` on a footer under a hairline (no footer when `actions` is empty). Width defaults to
/// `sizes.dialogMd`; usable inside `.appDialog(...)` or a plain `.sheet`.
public struct AppDialogFrame<Content: View, Actions: View, HeaderTrailing: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let leadingIcon: String?
    let maxWidth: CGFloat?
    let onClose: () -> Void
    let headerTrailing: HeaderTrailing
    let content: Content
    let actions: Actions
    let hasActions: Bool

    /// - Parameters: `leadingIcon` is an SF Symbol tinted with the accent; `onClose` runs for the close button.
    public init(title: String, leadingIcon: String? = nil, maxWidth: CGFloat? = nil, onClose: @escaping () -> Void,
                @ViewBuilder headerTrailing: () -> HeaderTrailing = { EmptyView() },
                @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.title = title; self.leadingIcon = leadingIcon; self.maxWidth = maxWidth; self.onClose = onClose
        self.headerTrailing = headerTrailing(); self.content = content(); self.actions = actions()
        hasActions = Actions.self != EmptyView.self
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.spacing.s8) {
                if let leadingIcon {
                    Image(systemName: leadingIcon).font(.system(size: theme.sizes.icon18)).foregroundStyle(theme.colors.accent)
                }
                Text(title).font(theme.typography.title).foregroundStyle(theme.colors.tx).lineLimit(2)
                Spacer(minLength: 0)
                headerTrailing
                AppIconButton("xmark", help: appString("close", "Close"), action: onClose)
            }
            .padding(.top, theme.spacing.s20).padding(.leading, theme.spacing.s24).padding(.trailing, theme.spacing.s16)
            .padding(.bottom, theme.spacing.s12)
            content
            if hasActions {
                Divider().overlay(theme.colors.line)
                HStack(spacing: theme.spacing.s10) { actions }
                    .padding(.horizontal, theme.spacing.s24).padding(.vertical, theme.spacing.s16)
            }
        }
        .frame(maxWidth: maxWidth ?? theme.sizes.dialogMd)
        .appGlass(in: RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous), fallback: theme.colors.panel)
        .shadow(color: theme.colors.scrim.opacity(0.25), radius: theme.spacing.s24, y: theme.spacing.s8)
        .onExitCommand(perform: onClose)
    }
}

public extension AppDialogFrame where HeaderTrailing == EmptyView {
    init(title: String, leadingIcon: String? = nil, maxWidth: CGFloat? = nil, onClose: @escaping () -> Void,
         @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.init(title: title, leadingIcon: leadingIcon, maxWidth: maxWidth, onClose: onClose,
                  headerTrailing: { EmptyView() }, content: content, actions: actions)
    }
}

public extension AppDialogFrame where Actions == EmptyView {
    init(title: String, leadingIcon: String? = nil, maxWidth: CGFloat? = nil, onClose: @escaping () -> Void,
         @ViewBuilder headerTrailing: () -> HeaderTrailing = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.init(title: title, leadingIcon: leadingIcon, maxWidth: maxWidth, onClose: onClose,
                  headerTrailing: headerTrailing, content: content, actions: { EmptyView() })
    }
}

/// Presents `content` as a centred dialog on a dimming scrim, inside the same view hierarchy (no window sheet): over the
/// whole window when a `DialogCenter` is in the environment (see `dialogHost`), else over the view it modifies — Flutter's `showDialog` for a SwiftUI ZStack host. A click on the scrim and Esc
/// dismiss it when `dismissOnScrim` is true.
public struct AppDialogPresentation<DialogContent: View>: ViewModifier {
    @Environment(\.appTheme) private var theme
    @Environment(\.dialogCenter) private var center
    @Binding var isPresented: Bool
    let dismissOnScrim: Bool
    let dialog: () -> DialogContent
    @State private var entryId = UUID()

    public func body(content: Content) -> some View {
        if let center {
            // Window-level: drawn by `dialogHost` so it is never clipped to this view.
            content
                .onChange(of: isPresented, initial: true) { _, now in sync(now, center) }
                .onDisappear { center.remove(entryId) }
        } else {
            content.overlay {
                if isPresented {
                    ZStack {
                        theme.colors.scrim.opacity(0.45).ignoresSafeArea()
                            .onTapGesture { if dismissOnScrim { isPresented = false } }
                        dialog().padding(theme.spacing.s24)
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .animation(.easeOut(duration: theme.motion.base), value: isPresented)
        }
    }

    private func sync(_ presented: Bool, _ center: DialogCenter) {
        if presented {
            center.present(.init(id: entryId, dismissOnScrim: dismissOnScrim, content: { AnyView(dialog()) },
                                 dismiss: { isPresented = false }))
        } else { center.remove(entryId) }
    }
}

public extension View {
    /// Shows `content` as an `AppDialogFrame`-style dialog while `isPresented` is true.
    func appDialog<D: View>(isPresented: Binding<Bool>, dismissOnScrim: Bool = true,
                            @ViewBuilder content: @escaping () -> D) -> some View {
        modifier(AppDialogPresentation(isPresented: isPresented, dismissOnScrim: dismissOnScrim, dialog: content))
    }

    /// Item-driven variant: presented while `item` is non-nil.
    func appDialog<Item, D: View>(item: Binding<Item?>, dismissOnScrim: Bool = true,
                                  @ViewBuilder content: @escaping (Item) -> D) -> some View {
        appDialog(isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
                  dismissOnScrim: dismissOnScrim) {
            if let v = item.wrappedValue { content(v) }
        }
    }
}
