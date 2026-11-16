import AppKit
import SwiftUI

/// Ported from: lib/core/widgets/code_block.dart
/// Selectable monospace code on a subtle boxed surface: Markdown code fences and chat code messages. With
/// `collapsedLines`, code longer than that shows only its first lines until expanded, so a pasted file doesn't
/// take over a chat thread.
public struct CodeBlock: View {
    @Environment(\.appTheme) private var theme
    @State private var expanded = false
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

    public var body: some View {
        let lineCount = code.components(separatedBy: "\n").count
        let collapsible = collapsedLines.map { lineCount > $0 } ?? false
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Text(Self.shownText(code, collapsedLines: collapsedLines, expanded: expanded))
                    .font(.custom("Space Mono", size: fontSize)).lineSpacing(fontSize * 0.2).foregroundStyle(theme.colors.tx)
                    .textSelection(.enabled).padding(theme.spacing.s12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CodeCopyButton(code: code).padding(theme.spacing.s4)
            }
            if collapsible {
                Divider().overlay(theme.colors.line)
                Button { expanded.toggle() } label: {
                    HStack(spacing: theme.spacing.s4) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: theme.sizes.icon12))
                        Text(expanded ? appString("codeBlockCollapse", "Collapse")
                             : appString("codeBlockShowAll", "Show all {count} lines").replacingOccurrences(of: "{count}", with: "\(lineCount)"))
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
