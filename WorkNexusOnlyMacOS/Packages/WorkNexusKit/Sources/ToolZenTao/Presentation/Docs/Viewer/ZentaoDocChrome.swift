/// Ported from: lib/tools/zentao/presentation/widgets/zentao_doc_reader_theme.dart (+ the icon buttons of the reader's tools)
import CoreDomain
import CoreUI
import SwiftUI

/// The document reader's page: the app's own theme, or - when the reader is switched to the other brightness - the
/// theme rebuilt in that variant (same font, density, radius and accent), so only the page changes. The page sits on
/// the `card` surface, the lightest one in light mode, so code blocks and table headers (`panel2`) stand off it in both.
struct ZentaoDocReaderTheme<Content: View>: View {
    @Environment(\.appTheme) private var appTheme
    let docs: ZentaoDocsState
    let content: Content
    init(docs: ZentaoDocsState, @ViewBuilder content: () -> Content) { self.docs = docs; self.content = content() }

    var body: some View {
        let t = Self.theme(app: appTheme, forcedDark: docs.readerForcedDark, settings: docs.settings)
        content
            .environment(\.appTheme, t).environment(\.colorScheme, t.colorScheme)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(t.colors.card)
    }

    /// `app` itself, or the theme in the other brightness when the reader is forced to it.
    static func theme(app: AppTheme, forcedDark: Bool?, settings: AppSettings) -> AppTheme {
        guard let forcedDark, forcedDark != app.colors.isDark else { return app }
        var s = settings
        s.themeFollowsSystem = false
        s.variant = forcedDark ? .dark : .light
        return AppTheme(settings: s)
    }
}

/// A person's face for the document header, by login: injected by the host (the chat photo) through
/// `\.zentaoDocPersonFace`; a plain initial avatar without it.
public struct ZentaoDocPersonFace: Sendable {
    public var accountId: String
    public var name: String
    public var diameter: CGFloat
    public init(accountId: String, name: String, diameter: CGFloat) {
        self.accountId = accountId; self.name = name; self.diameter = diameter
    }
}

private struct PersonFaceKey: EnvironmentKey { static let defaultValue: ((ZentaoDocPersonFace) -> AnyView)? = nil }
private struct PersonActionKey: EnvironmentKey { static let defaultValue: ((ZentaoDocPersonFace) -> AnyView)? = nil }
public extension EnvironmentValues {
    /// The face of a document's author / editor (the chat photo by login).
    var zentaoDocPersonFace: ((ZentaoDocPersonFace) -> AnyView)? {
        get { self[PersonFaceKey.self] } set { self[PersonFaceKey.self] = newValue }
    }
    /// The button beside a person in a document's people card (message them); `diameter` is unused there.
    var zentaoDocPersonAction: ((ZentaoDocPersonFace) -> AnyView)? {
        get { self[PersonActionKey.self] } set { self[PersonActionKey.self] = newValue }
    }
}

/// An icon button of the reader's tools: lit while `selected`, a spinner while `loading`.
struct ZentaoDocToolButton: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let systemImage: String; let help: String
    var selected = false; var loading = false; var small = false
    let action: () -> Void

    var body: some View {
        let c = theme.colors
        let side = small ? theme.sizes.control32 - theme.spacing.s8 : theme.sizes.control32
        Button(action: action) {
            Group {
                if loading { ProgressView().controlSize(.small) }
                else { Image(systemName: systemImage).font(.system(size: small ? theme.sizes.icon14 : theme.sizes.icon16)) }
            }
            .foregroundStyle(selected ? c.accent : (hovering ? c.tx : c.tx2))
            .frame(width: side, height: side)
            .background(selected ? c.sel : (hovering ? c.panel2 : .clear), in: RoundedRectangle(cornerRadius: theme.radii.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }.help(help).disabled(loading)
    }
}

/// A floating card (the tools, the find bar): card fill, hairline border, medium radius.
struct ZentaoDocFloatingCard<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(theme.spacing.s2)
            .background(theme.colors.card, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}
