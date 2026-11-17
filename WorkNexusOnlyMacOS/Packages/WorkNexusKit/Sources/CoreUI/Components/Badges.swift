import SwiftUI

/// Ported from: core/widgets/{tinted_pill,count_badge,user_avatar,app_state_view}.dart
public struct TintedPill: View {
    @Environment(\.appTheme) private var theme
    let text: String; let tint: Color
    public init(_ text: String, tint: Color) { self.text = text; self.tint = tint }
    public var body: some View {
        Text(text).font(theme.typography.badge).foregroundStyle(tint)
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s2)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

public struct AppCountBadge: View {
    @Environment(\.appTheme) private var theme
    let count: Int
    public init(_ count: Int) { self.count = count }
    public var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)").font(theme.typography.badge).foregroundStyle(theme.colors.accentTx)
                .padding(.horizontal, theme.spacing.s6).frame(minWidth: 16, minHeight: 16)
                .background(theme.colors.red, in: Capsule())
        }
    }
}

/// Ported from: core/widgets/unread_badge.dart. An accent pill with an unread count (capped at 99+); nothing at 0.
public struct UnreadBadge: View {
    @Environment(\.appTheme) private var theme
    let count: Int
    public init(count: Int) { self.count = count }
    public static func label(for count: Int) -> String { count > 99 ? "99+" : "\(count)" }
    public var body: some View {
        if count > 0 {
            Text(Self.label(for: count)).font(theme.typography.badge).foregroundStyle(theme.colors.accentTx)
                .padding(.horizontal, theme.spacing.s6).frame(minWidth: 16, minHeight: 16)
                .background(theme.colors.accent, in: Capsule())
        }
    }
}

public struct UserAvatar: View {
    @Environment(\.appTheme) private var theme
    let name: String; var url: URL?; var size: CGFloat
    public init(name: String, url: URL? = nil, size: CGFloat = 24) { self.name = name; self.url = url; self.size = size }
    public var body: some View {
        ZStack {
            Circle().fill(color)
            Text(initials).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(theme.colors.onColorInk)
            if let url { AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear } }
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
    private var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap(\.first)
        return (parts.isEmpty ? String(name.prefix(1)) : String(parts)).uppercased()
    }
    /// Stable hue per name (same name → same colour).
    private var color: Color {
        let h = name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return Color(hue: Double(abs(h) % 360) / 360, saturation: 0.45, brightness: theme.colors.isDark ? 0.8 : 0.9)
    }
}

public enum AppStateKind { case loading, empty(String), error(String) }

public struct AppStateView: View {
    @Environment(\.appTheme) private var theme
    let kind: AppStateKind; var retry: (() -> Void)?
    public init(_ kind: AppStateKind, retry: (() -> Void)? = nil) { self.kind = kind; self.retry = retry }
    public var body: some View {
        VStack(spacing: theme.spacing.s12) {
            switch kind {
            case .loading: SkeletonRows()
            case .empty(let m): Text(m).font(theme.typography.body).foregroundStyle(theme.colors.tx3)
            case .error(let m):
                Text(m).font(theme.typography.body).foregroundStyle(theme.colors.red).multilineTextAlignment(.center)
                if let retry { AppButton("Retry", systemImage: "arrow.clockwise", action: retry) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isLoading ? .top : .center).padding(theme.spacing.s24)
    }

    private var isLoading: Bool { if case .loading = kind { true } else { false } }
}

/// Rows of placeholders (an avatar and two lines each) for a list or panel that is loading; it fades in after a moment,
/// so a load that is quick shows no flash of placeholders.
public struct SkeletonRows: View {
    @Environment(\.appTheme) private var theme
    var count: Int
    @State private var shown = false
    public init(count: Int = 6) { self.count = count }
    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s16) {
            ForEach(0..<count, id: \.self) { i in
                HStack(spacing: theme.spacing.s12) {
                    SkeletonBox(width: 32, height: 32, radius: theme.radii.pill)
                    VStack(alignment: .leading, spacing: theme.spacing.s6) {
                        SkeletonBox(width: [180, 140, 210, 120, 160, 190][i % 6], height: 12, radius: theme.radii.xs)
                        SkeletonBox(height: 10, radius: theme.radii.xs).padding(.trailing, CGFloat([40, 90, 20, 120, 60, 70][i % 6]))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(shown ? 1 : 0)
        .task { try? await Task.sleep(for: .milliseconds(120)); withAnimation(.easeOut(duration: theme.motion.base)) { shown = true } }
    }
}
