import AppKit
import SwiftUI

/// Ported from: lib/core/widgets/code_block.dart
/// Selectable monospace code on a subtle boxed surface: Markdown code fences and chat code messages. With
/// `collapsedLines`, code longer than that shows only its first lines until expanded, so a pasted file doesn't
/// take over a chat thread.
public struct CodeBlock: View {
    @Environment(\.appTheme) private var theme
    @State private var expanded = false
    /// The code's rows at the width it is drawn at (only measured when it can collapse).
    @State private var rows: (count: Int, rowHeight: CGFloat)?
    @State private var measuredWidth: CGFloat = 0
    @State private var measuredCode = ""
    let code: String; let fontSize: CGFloat; let collapsedLines: Int?

    public init(_ code: String, fontSize: CGFloat, collapsedLines: Int? = nil) {
        self.code = code; self.fontSize = fontSize; self.collapsedLines = collapsedLines
    }

    /// The text shown for a given expansion state (first `collapsedLines` lines while collapsed).
    public static func shownText(_ code: String, collapsedLines: Int?, expanded: Bool) -> String {
        let lines = code.components(separatedBy: "\n")
        guard let limit = collapsedLines, lines.count > limit, !expanded else { return code }
        return lines.prefix(limit).joined(separator: "\n")
    }

    private var lineSpacing: CGFloat { fontSize * 0.2 }

    public var body: some View {
        // Rows as shown, wrapped to the block's width; before the first measure, the line breaks stand in for them.
        let rowCount = rows?.count ?? code.components(separatedBy: "\n").count
        let collapsible = collapsedLines.map { rowCount > $0 } ?? false
        let collapsed = collapsible && !expanded
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                // Past the limit's lines nothing would show anyway: dropping them keeps a long paste from laying out in full.
                Text(Self.shownText(code, collapsedLines: collapsedLines, expanded: !collapsed))
                    .font(.custom("Space Mono", size: fontSize)).lineSpacing(lineSpacing).foregroundStyle(theme.colors.tx)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: collapsed ? collapsedHeight : nil, alignment: .top).clipped()
                    .padding(theme.spacing.s12)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measure(width: $0 - theme.spacing.s12 * 2) }
                    .onChange(of: code) { measure(width: measuredWidth) }
                CodeCopyButton(code: code).padding(theme.spacing.s4)
            }
            if collapsible {
                Divider().overlay(theme.colors.line)
                Button { expanded.toggle() } label: {
                    HStack(spacing: theme.spacing.s4) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: theme.sizes.icon12))
                        Text(expanded ? appString("codeBlockCollapse", "Collapse")
                             : appString("codeBlockShowAll", "Show all {count} lines").replacingOccurrences(of: "{count}", with: "\(rowCount)"))
                            .font(theme.typography.paragraph)
                    }
                    .foregroundStyle(theme.colors.tx2).frame(maxWidth: .infinity).padding(.vertical, theme.spacing.s6)
                    .background(theme.colors.panel).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .background(theme.colors.panel2)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.sm))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.sm).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }

    /// The height of `collapsedLines` rows.
    private var collapsedHeight: CGFloat? {
        guard let limit = collapsedLines, let rows else { return nil }
        return CGFloat(limit) * rows.rowHeight + CGFloat(limit - 1) * lineSpacing
    }

    private func measure(width: CGFloat) {
        guard collapsedLines != nil, width > 0, abs(width - measuredWidth) >= 1 || measuredCode != code else { return }
        measuredWidth = width; measuredCode = code
        rows = CodeRows.measure(code, font: CodeRows.font(size: fontSize), lineSpacing: lineSpacing, width: width)
    }
}

/// Copies `code` to the clipboard, ticking for a moment once copied; sits in the corner of a code surface.
public struct CodeCopyButton: View {
    @Environment(\.appTheme) private var theme
    @State private var copied = false
    let code: String
    public init(code: String) { self.code = code }
    public var body: some View {
        AppIconButton(copied ? "checkmark" : "doc.on.doc", help: copied ? appString("codeBlockCopied", "Copied") : appString("codeBlockCopy", "Copy code")) {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
            copied = true
            Task { try? await Task.sleep(for: .seconds(2)); copied = false }
        }
        .foregroundStyle(copied ? theme.colors.green : theme.colors.tx2)
        .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
        .scaleEffect(0.85)
    }
}
