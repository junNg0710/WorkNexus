/// Not in the Flutter app.
import CoreDomain
import CoreUI
import Observation
import SharedKit
import SwiftUI

/// Asks for a new personal todo from anywhere in the app (a chat message → "Create todo"): the host calls `open`, and
/// the dialog `zentaoTodoPrompt` puts over the window does the rest.
@MainActor @Observable
public final class ZentaoTodoPrompt {
    /// What the dialog opens filled in with.
    public struct Seed: Equatable, Sendable {
        public var accountId: String
        public var name: String
        public var desc: String
    }

    public var seed: Seed?
    @ObservationIgnored let todos: ZenTaoTodos
    /// Told once a todo was made (the host shows its toast).
    @ObservationIgnored public var onCreated: (() -> Void)?

    public init(todos: ZenTaoTodos) { self.todos = todos }

    public func open(accountId: String, name: String = "", desc: String = "") {
        seed = Seed(accountId: accountId, name: name, desc: desc)
    }
}

public extension View {
    /// Shows the "New todo" dialog over this view whenever `prompt` is asked for one.
    func zentaoTodoPrompt(_ prompt: ZentaoTodoPrompt) -> some View { modifier(ZentaoTodoPromptHost(prompt: prompt)) }
}

private struct ZentaoTodoPromptHost: ViewModifier {
    @Bindable var prompt: ZentaoTodoPrompt

    func body(content: Content) -> some View {
        content.appDialog(item: $prompt.seed, dismissOnScrim: false) { seed in
            ZentaoTodoDialog(seed: seed, todos: prompt.todos, onClose: { prompt.seed = nil }, onCreated: { prompt.onCreated?() })
        }
    }
}

/// "New todo": name, day, priority and a note; saved to the account's own todo list in ZenTao.
struct ZentaoTodoDialog: View {
    @Environment(\.appTheme) private var theme
    let seed: ZentaoTodoPrompt.Seed
    let todos: ZenTaoTodos
    let onClose: () -> Void
    let onCreated: () -> Void
    @State private var draft: ZenTaoTodoDraft
    @State private var busy = false
    @State private var failure: String?

    init(seed: ZentaoTodoPrompt.Seed, todos: ZenTaoTodos, now: Date = Date(), onClose: @escaping () -> Void, onCreated: @escaping () -> Void = {}) {
        self.seed = seed; self.todos = todos; self.onClose = onClose; self.onCreated = onCreated
        _draft = State(initialValue: ZenTaoTodoDraft(name: seed.name, desc: seed.desc, date: now))
    }

    private func submit() {
        guard !busy else { return }
        busy = true; failure = nil
        Task {
            switch await CreateZenTaoTodo(todos)(accountId: seed.accountId, draft) {
            case .success: onCreated(); onClose()
            case .failure(let f): failure = f.message; busy = false
            }
        }
    }

    var body: some View {
        ZentaoActionFrame(title: appString("zentaoTodoNew", "New todo"), icon: "calendar.badge.plus", submitLabel: appString("save", "Save"),
                          busy: busy, canSubmit: CreateZenTaoTodo.ready(draft) != nil, onSubmit: submit, onClose: onClose) {
            ZentaoFieldLabel(appString("zentaoTodoName", "Todo"))
            ZentaoTextInput(text: $draft.name, onSubmit: submit)
            ZentaoFieldGap()
            HStack(alignment: .top, spacing: theme.spacing.s24) {
                VStack(alignment: .leading, spacing: 0) {
                    ZentaoFieldLabel(appString("zentaoTodoDate", "Date"))
                    AppDateField(value: draft.date) { if let day = $0 { draft.date = day } }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ZentaoFieldLabel(appString("priority", "Priority"))
                    HStack(spacing: theme.spacing.s6) {
                        ForEach(Array(ZenTaoTodoDraft.priorities), id: \.self) { p in
                            FilterOptionChip(FilterChipOption(label: "\(p)", active: draft.pri == p, onTap: { draft.pri = p }))
                        }
                    }
                }
            }
            ZentaoFieldGap()
            ZentaoFieldLabel(appString("description", "Description"))
            TextField("", text: $draft.desc, axis: .vertical).lineLimit(4...10).textFieldStyle(.plain)
                .font(theme.typography.body).foregroundStyle(theme.colors.tx).padding(theme.spacing.s8)
                .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
            if let failure {
                ZentaoFieldGap()
                AppInlineNote(failure, isError: true)
            }
        }
    }
}
