import CoreDomain
import XCTest
@testable import ToolZenTao

final class ZenTaoTodoTests: XCTestCase {
    private struct OneClient: ZenTaoClientProvider {
        let client: ZenTaoClient?
        func zenTaoClient(accountId: String) async -> ZenTaoClient? { client }
    }
    private final class Recorder: ZenTaoTodos, @unchecked Sendable {
        var sent: [ZenTaoTodoDraft] = []
        func createTodo(accountId: String, todo: ZenTaoTodoDraft) async -> Outcome<Int?> { sent.append(todo); return .success(9) }
    }
    private let day = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 15))!

    func testCreatePostsAPlainAllDayTodoOfTheUserAndAnswersItsId() async throws {
        let server = StubServer { req in
            if req.path.hasSuffix("/tokens") { return .json(["token": "t"]) }
            return .json(["id": 31, "name": "Call An"], status: 201)
        }
        let service = ZenTaoTodoService(clients: OneClient(client: makeClient(server)))
        let id = await service.createTodo(accountId: "zt", todo: ZenTaoTodoDraft(name: "Call An", desc: "about <login>\nsoon\n\nthanks", date: day, pri: 2)).unwrap()
        XCTAssertEqual(id, 31)
        let post = try XCTUnwrap(server.requests.first { $0.method == "POST" && $0.path.hasSuffix("/api.php/v1/todos") })
        XCTAssertEqual(post.header("Token"), "t")
        let body = try XCTUnwrap(asMap(post.jsonBody))
        XCTAssertEqual(body["name"] as? String, "Call An")
        XCTAssertEqual(body["type"] as? String, "custom")
        XCTAssertEqual(body["date"] as? String, "2026-11-17")
        XCTAssertEqual(body["pri"] as? Int, 2)
        XCTAssertEqual(body["desc"] as? String, "<p>about &lt;login&gt;<br/>soon</p><p>thanks</p>")
        XCTAssertNil(body["begin"], "no time of day: ZenTao keeps it as an all-day todo")
    }

    func testARefusalIsReportedWithWhatZenTaoSaid() async {
        for reply in [StubResponse.json(["error": "name required"], status: 400), .json(["result": "fail", "message": ["name": ["required"]] as JSON]),
                      .json(["error": "no rights"], status: 403)] {
            let server = StubServer { req in req.path.hasSuffix("/tokens") ? .json(["token": "t"]) : reply }
            let result = await ZenTaoTodoService(clients: OneClient(client: makeClient(server))).createTodo(accountId: "zt", todo: ZenTaoTodoDraft(name: "x", date: day))
            guard case .failure(let f) = result else { return XCTFail("expected a failure") }
            XCTAssertTrue(f.message.contains("required") || f.message.contains("no rights"), f.message)
        }
        let signedOut = await ZenTaoTodoService(clients: OneClient(client: nil)).createTodo(accountId: "zt", todo: ZenTaoTodoDraft(name: "x", date: day))
        guard case .failure(.auth) = signedOut else { return XCTFail("expected an auth failure") }
    }

    func testTheUseCaseTrimsRequiresANameAndKeepsThePriorityInRange() async {
        let todos = Recorder()
        let refused = await CreateZenTaoTodo(todos)(accountId: "zt", ZenTaoTodoDraft(name: "  \n", date: day))
        guard case .failure(.validation) = refused else { return XCTFail("expected a validation failure") }
        XCTAssertTrue(todos.sent.isEmpty)
        _ = await CreateZenTaoTodo(todos)(accountId: "zt", ZenTaoTodoDraft(name: "  Call An ", desc: " note \n", date: day, pri: 9))
        XCTAssertEqual(todos.sent, [ZenTaoTodoDraft(name: "Call An", desc: "note", date: day, pri: 4)])
        XCTAssertEqual(CreateZenTaoTodo.ready(ZenTaoTodoDraft(name: String(repeating: "a", count: 300), date: day))?.name.count, ZenTaoTodoDraft.nameLimit)
        XCTAssertEqual(ZenTaoTodoDraft(name: "x", desc: "", date: day).descHtml, "")
    }

    @MainActor func testThePromptOpensWithWhatItWasAskedFor() {
        let prompt = ZentaoTodoPrompt(todos: Recorder())
        XCTAssertNil(prompt.seed)
        prompt.open(accountId: "zt", name: "Call An", desc: "note")
        XCTAssertEqual(prompt.seed, ZentaoTodoPrompt.Seed(accountId: "zt", name: "Call An", desc: "note"))
    }
}
