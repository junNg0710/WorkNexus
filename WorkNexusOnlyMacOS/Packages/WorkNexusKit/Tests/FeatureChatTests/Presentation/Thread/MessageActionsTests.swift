/// Ported from: test/features/chat/presentation/message_actions_test.dart + message_translation_controller_test.dart
import CoreDomain
import XCTest
@testable import FeatureChat

final class StubTranslations: MessageTranslationRepository, @unchecked Sendable {
    var stored: ChatMessageTranslation?
    var hidden: [String] = []
    func find(accountId: String, gid: String, targetLang: String) async -> Outcome<ChatMessageTranslation?> { .success(stored) }
    func watch(accountId: String, gid: String, targetLang: String) -> AsyncStream<ChatMessageTranslation?> { AsyncStream { $0.finish() } }
    func setVisible(accountId: String, gid: String, targetLang: String, visible: Bool) async -> Outcome<Void> { if !visible { hidden.append(gid) }; return .success(()) }
    func save(_ translation: ChatMessageTranslation) async -> Outcome<Void> { stored = translation; return .success(()) }
}

struct StubTranslator: ChatTextTranslator {
    var result: Outcome<(text: String, model: String?)> = .success(("Xin chao", "m1"))
    func translateText(key: String, text: String, targetLang: String, model: String?) async -> Outcome<(text: String, model: String?)> { result }
}

@MainActor
final class MessageActionsTests: XCTestCase {
    private func context(chat: ChatConversation = Make.chat("g"), translate: Bool = false, forward: Bool = false, selfId: Int? = 1,
                         account: String? = nil, store: StubTranslations = StubTranslations(), languages: [ChatAiLanguage] = []) -> ThreadContext {
        let state = ChatThreadState(accountId: "a", chat: chat, selfAccount: account)
        state.selfUserId = selfId
        var services = ChatServices(chat: StubChatRepository(), translations: translate ? store : nil, translator: translate ? StubTranslator() : nil)
        services.aiLanguages = languages
        let model = MessageTimelineModel(state: state, services: services)
        return ThreadContext(model: model, actions: ChatThreadActions(forward: forward ? { _ in } : nil, saveAsSticker: { _ in }))
    }
    private func ids(_ ctx: ThreadContext, _ m: ChatMessage, inThread: Bool = false) -> [String] {
        ctx.actions(for: m, settings: ChatSettings(), inThread: inThread).map(\.id)
    }

    /// A right-click on the text: the words picked, then copy, reply, forward - not Font, Spelling or Services.
    func testTheTextMenuIsShort() {
        let m = Make.message(content: .text("hello world"), serverId: 5)
        let ctx = context(forward: true)
        XCTAssertEqual(ctx.textMenu(for: m, settings: ChatSettings(), selection: "world").map(\.title), [L.copySelection, L.copy, L.reply, L.forward])
        XCTAssertEqual(ctx.textMenu(for: m, settings: ChatSettings(), selection: nil).map(\.title), [L.copy, L.reply, L.forward])
        XCTAssertEqual(ctx.textMenu(for: m, settings: ChatSettings(), selection: "").count, 3)
    }

    func testStoredTextOffersReplyAndCopy() {
        let m = Make.message(content: .text("hi"), serverId: 5)
        XCTAssertEqual(ids(context(), m), ["reply", "copy", "select"])
    }

    func testPendingMessageCannotBeRepliedTo() {
        XCTAssertEqual(ids(context(), Make.message(content: .text("hi"), state: .pending)), ["copy"])
    }

    func testThreadActionOnlyInAThread() {
        let m = Make.message(serverId: 5, replyTo: 2)
        XCTAssertEqual(ids(context(), m, inThread: true), ["reply", "thread", "copy", "select"])
        XCTAssertEqual(ids(context(), m, inThread: false), ["reply", "copy", "select"])
    }

    func testCreateTicketNeedsTheHostHookAndTextAndComesBeforeSelectAndRetract() {
        var asked: [(ChatTicketKind, [String])] = []
        let state = ChatThreadState(accountId: "a", chat: Make.chat("g"))
        let model = MessageTimelineModel(state: state, services: ChatServices(chat: StubChatRepository()))
        let ctx = ThreadContext(model: model, actions: ChatThreadActions(createTicket: { kind, ms in asked.append((kind, ms.map(\.gid))) }))
        let m = Make.message(at: Date(), content: .text("Login fails"), mine: true, serverId: 5)
        let actions = ctx.actions(for: m, settings: ChatSettings(), inThread: false)
        XCTAssertEqual(actions.map(\.id), ["reply", "copy", "createBug", "createTask", "createTodo", "select", "retract"])
        XCTAssertEqual(actions.filter(\.sectionStart).map(\.id), ["createBug", "select"])
        actions.first { $0.id == "createTask" }?.run()
        XCTAssertEqual(asked.map(\.0), [.task]); XCTAssertEqual(asked.first?.1, ["m1"])
        // A picture has no text to make a ticket of; a host without the hook offers none.
        XCTAssertFalse(ctx.actions(for: Make.message(content: .emoji("👍"), serverId: 6), settings: ChatSettings(), inThread: false).contains { $0.id == "createBug" })
        XCTAssertFalse(ids(context(), m).contains("createBug"))
    }

    func testSelectStartsMultipleSelectWithThatMessageAndPicksOnlyStoredMessages() {
        let ctx = context(), state = ctx.state
        let a = Make.message("a", at: Make.t0.addingTimeInterval(60), serverId: 2), b = Make.message("b", at: Make.t0, serverId: 1)
        XCTAssertFalse(ids(ctx, Make.message("p", state: .pending)).contains("select"), "not on the server yet")
        XCTAssertFalse(state.isSelecting)
        ctx.actions(for: a, settings: ChatSettings(), inThread: false).first { $0.id == "select" }?.run()
        XCTAssertEqual(state.selection?.map(\.gid), ["a"])
        state.toggleSelected(b); state.toggleSelected(Make.message("gone", serverId: 3, deleted: true)); state.toggleSelected(Make.message("n", serverId: 4, notice: true))
        XCTAssertEqual(state.selectedInOrder.map(\.gid), ["b", "a"], "oldest first, whatever the order they were picked in")
        XCTAssertTrue(state.isSelected(b))
        state.toggleSelected(a)
        XCTAssertEqual(state.selection?.map(\.gid), ["b"])
        state.endSelection()
        XCTAssertNil(state.selection)
        state.toggleSelected(b)
        XCTAssertNil(state.selection, "nothing is picked while multiple select is off")
    }

    func testForwardNeedsTheHookAndASentMessage() {
        XCTAssertTrue(ids(context(forward: true), Make.message(serverId: 5)).contains("forward"))
        XCTAssertFalse(ids(context(forward: false), Make.message(serverId: 5)).contains("forward"))
        XCTAssertFalse(ids(context(forward: true), Make.message(state: .failed)).contains("forward"))
    }

    func testRetractOnlyOwnRecentMessagesAndItComesLast() {
        let a = context().actions(for: Make.message(at: Date(), content: .text("oops"), mine: true, serverId: 5), settings: ChatSettings(), inThread: false)
        XCTAssertEqual(a.last?.id, "retract")
        XCTAssertTrue(a.last?.destructive ?? false)
        let old = Make.message(at: Make.t0, content: .text("old"), mine: true, serverId: 5)
        XCTAssertFalse(ids(context(), old).contains("retract"), "after two minutes")
        XCTAssertFalse(ids(context(), Make.message(at: Date(), serverId: 5)).contains("retract"), "not mine")
    }

    func testCopyTextTurnsMentionsIntoAtNames() {
        let ctx = context()
        let m = Make.message(content: .text("hi [@Ann](@#7)"), serverId: 5)
        XCTAssertEqual(ChatTextLabels.copyText("hi [@Ann](@#7)"), "hi @Ann")
        XCTAssertTrue(ids(ctx, m).contains("copy"))
        XCTAssertFalse(ids(ctx, Make.message(content: .emoji("👍"), serverId: 5)).contains("copy"))
        XCTAssertTrue(ids(ctx, Make.message(content: .code("x", language: nil, name: nil), serverId: 5)).contains("copy"))
        XCTAssertFalse(ids(ctx, Make.message(content: .text("x"), serverId: 5, deleted: true)).contains("copy"))
    }

    func testPinOnlyWhereAllowed() {
        let direct = context(chat: Make.chat("g", type: .one2one))
        XCTAssertTrue(ids(direct, Make.message(serverId: 5)).contains("pin"))
        let group = context(chat: Make.chat("g", type: .group))
        XCTAssertFalse(ids(group, Make.message(serverId: 5)).contains("pin"), "group pins are for admins and the owner")
        var admin = Make.chat("g", type: .group); admin.adminIds = [1]
        XCTAssertTrue(ids(context(chat: admin), Make.message(serverId: 5)).contains("pin"))
        var pinned = Make.chat("g", type: .one2one); pinned.pinnedMessageIds = [5]
        let a = context(chat: pinned).actions(for: Make.message(serverId: 5), settings: ChatSettings(), inThread: false)
        XCTAssertEqual(a.first { $0.id == "pin" }?.title, "Unpin")
    }

    func testStickerActionForImages() {
        let image = MessageContent.image(ImageContent(fileId: 3, name: "a.png", size: 1, time: 1))
        XCTAssertTrue(ids(context(), Make.message(content: image, serverId: 5)).contains("sticker"))
    }

    func testTranslateActionsFollowTheTranslationState() async {
        let ctx = context(translate: true)
        let m = Make.message("t1", content: .text("hello"), serverId: 5)
        XCTAssertTrue(ids(ctx, m).contains("translate"))
        XCTAssertFalse(ids(ctx, m).contains("retranslate"))
        XCTAssertEqual(ctx.actions(for: m, settings: ChatSettings(), inThread: false).first { $0.id == "translate" }?.title, "Translate")
        await ctx.model.translation.translate(m, lang: "vi", model: "")
        XCTAssertEqual(ctx.model.translation.entries["t1"].map { if case .done(let t) = $0 { t.text } else { "?" } }, "Xin chao")
        XCTAssertTrue(ids(ctx, m).contains("retranslate"))
        XCTAssertEqual(ctx.actions(for: m, settings: ChatSettings(), inThread: false).first { $0.id == "translate" }?.title, "Hide translation")
        XCTAssertFalse(ids(context(translate: false), m).contains("translate"), "no translator wired")
    }

    /// "Translate to" lists the chat's other languages; picking one translates this message into it only.
    func testAMessageCanBeTranslatedIntoAnotherLanguage() async {
        let ctx = context(translate: true, languages: [ChatAiLanguage(code: "vi", englishName: "Vietnamese", nativeName: "Tiếng Việt", flag: "🇻🇳"),
                                                       ChatAiLanguage(code: "zh", englishName: "Chinese", nativeName: "中文", flag: "🇨🇳")])
        let m = Make.message("t2", content: .text("hello"), serverId: 6)
        var settings = ChatSettings(); settings.translationLang = "vi"
        let to = ctx.actions(for: m, settings: settings, inThread: false).first { $0.id == "translateTo" }
        XCTAssertEqual(to?.children.map(\.title), ["🇨🇳 中文"], "the usual language is the plain Translate")
        to?.children.first?.run()
        let done = await eventuallyTrue { ctx.model.translation.language(of: "t2") == "zh" && ctx.model.translation.hasDone("t2") }
        XCTAssertTrue(done)
        XCTAssertEqual(ctx.model.translation.label(of: "zh"), "🇨🇳 中文")
        // In the right-click menu on the text too, as a submenu.
        let menu = ctx.textMenu(for: m, settings: settings, selection: nil)
        XCTAssertEqual(menu.first { $0.title == "Translate to" }?.children.map(\.title), ["🇨🇳 中文"])
    }

    private func eventuallyTrue(_ cond: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0..<100 { if cond() { return true }; try? await Task.sleep(for: .milliseconds(10)) }
        return cond()
    }

    func testTranslationFailureIsShownAndHidingKeepsItStored() async {
        let store = StubTranslations()
        let state = ChatThreadState(accountId: "a", chat: Make.chat("g"))
        let services = ChatServices(chat: StubChatRepository(), translations: store, translator: StubTranslator(result: .failure(.network("offline"))))
        let controller = MessageTranslationController(services: services)
        let m = Make.message("t2", content: .text("hello"), serverId: 6)
        _ = state
        await controller.translate(m, lang: "vi", model: "")
        XCTAssertEqual(controller.entries["t2"], .failed("offline"))
        XCTAssertTrue(controller.isShown("t2"))
        await controller.hide(m, lang: "vi")
        XCTAssertFalse(controller.isShown("t2"))
        XCTAssertEqual(store.hidden, ["t2"])
    }

    func testStoredVisibleTranslationComesBackWhenTheMessageIsShown() async {
        let store = StubTranslations()
        store.stored = ChatMessageTranslation(accountId: "a", gid: "t3", targetLang: "vi", text: "Chao", createdAt: Make.t0, visible: true)
        let ctx = context(translate: true, store: store)
        let m = Make.message("t3", content: .text("hello"), serverId: 7)
        await ctx.model.translation.restore(m, lang: "vi")
        XCTAssertTrue(ctx.model.translation.hasDone("t3"))
        store.stored?.visible = false
        let other = Make.message("t4", content: .text("hello"), serverId: 8)
        await ctx.model.translation.restore(other, lang: "vi")
        XCTAssertFalse(ctx.model.translation.isShown("t4"), "a hidden translation stays hidden")
    }

    func testReactOnlyWhenReactionsAreOnAndTheMessageIsStored() {
        let ctx = context()
        XCTAssertFalse(ctx.canReact(to: Make.message(serverId: 5)), "reactions are off by default")
        ctx.model.reactionsOn = true
        XCTAssertTrue(ctx.canReact(to: Make.message(serverId: 5)))
        XCTAssertFalse(ctx.canReact(to: Make.message()), "not stored yet")
        XCTAssertFalse(ctx.canReact(to: Make.message(content: .emoji("👍"), serverId: 5, replyTo: 2)), "a reaction itself")
        XCTAssertFalse(ctx.canReact(to: Make.message(serverId: 5, deleted: true)))
    }
}
